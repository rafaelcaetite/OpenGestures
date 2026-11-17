import AppKit
import CMultitouch

/// Connects contact frames, recognizers, the configuration and the action
/// runner.
///
/// Frames are processed synchronously on the multitouch thread under a
/// single unfair lock. Nothing is allocated or dispatched for a frame unless
/// it completes a gesture, which keeps the per-frame cost to a few
/// microseconds.
public final class GestureEngine: @unchecked Sendable {
    public struct Event: Sendable {
        public var gesture: Gesture
        public var direction: Direction?
        public var device: DeviceKind
        public var binding: Binding?
        public var application: ApplicationIdentity?
    }

    /// Per-device state, a class so it is mutated in place inside the
    /// dictionary instead of being copied.
    private final class DeviceState {
        let recognizer: GestureRecognizer
        var frame = TouchFrame(timestamp: 0, touches: [])
        var scheduledToken: Int?

        init(kind: DeviceKind, settings: RecognizerSettings) {
            recognizer = GestureRecognizer(device: kind, settings: settings)
            frame.touches.reserveCapacity(12)
        }
    }

    private let lock = UnfairLock()
    private var configuration: Configuration
    private var states: [UInt64: DeviceState] = [:]
    private var devices: [UInt64: DeviceInfo] = [:]
    /// Slide steps since the last haptic tap. Slides only come from frames,
    /// so this is only touched on the multitouch thread.
    private var slideStepsSinceHaptic = 0

    private let runner: ActionRunner
    private let applications: FrontmostApplication

    /// When false, gestures are recognized and reported but nothing runs.
    public var performsActions = true
    /// When true, every discrete gesture counts as bound. Used by `trace`.
    public var treatsAllGesturesAsBound = false
    /// Called on the multitouch thread for each recognized gesture.
    public var onEvent: (@Sendable (Event) -> Void)?

    public init(configuration: Configuration, runner: ActionRunner = ActionRunner(), applications: FrontmostApplication) {
        self.configuration = configuration
        self.runner = runner
        self.applications = applications
    }

    public func update(_ configuration: Configuration) {
        lock.withLock {
            self.configuration = configuration
            for state in states.values {
                state.recognizer.settings = configuration.settings.recognizer
            }
        }
    }

    // MARK: - Frames

    public func handleFrame(device: DeviceInfo, contacts: UnsafeBufferPointer<OGMTContact>, timestamp: Double) {
        let outputs: [RecognizedGesture] = lock.withLock {
            let state = self.state(for: device)
            state.frame.timestamp = timestamp
            state.frame.touches.removeAll(keepingCapacity: true)
            for contact in contacts
            where contact.state == OGMTContactStateMakeTouch || contact.state == OGMTContactStateTouching {
                let normalized = Point(x: Double(contact.normalized.position.x), y: Double(contact.normalized.position.y))
                state.frame.touches.append(Touch(
                    id: contact.identifier,
                    position: Point(x: normalized.x * device.width, y: normalized.y * device.height),
                    normalized: normalized
                ))
            }
            if state.frame.touches.isEmpty && !state.recognizer.isSessionActive {
                return []
            }
            let resolver = Resolver(engine: self, device: device.kind)
            let outputs = state.recognizer.process(state.frame, bindings: resolver)
            schedulePendingTap(state, device: device)
            return outputs
        }
        if !outputs.isEmpty {
            dispatch(outputs, device: device)
        }
    }

    private func state(for device: DeviceInfo) -> DeviceState {
        if let state = states[device.id] {
            return state
        }
        let state = DeviceState(kind: device.kind, settings: configuration.settings.recognizer)
        states[device.id] = state
        devices[device.id] = device
        return state
    }

    private func schedulePendingTap(_ state: DeviceState, device: DeviceInfo) {
        guard let token = state.recognizer.pendingTapToken, token != state.scheduledToken else { return }
        state.scheduledToken = token
        let delay = state.recognizer.settings.doubleTapInterval
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.resolvePendingTap(token: token, device: device)
        }
    }

    private func resolvePendingTap(token: Int, device: DeviceInfo) {
        let outputs = lock.withLock {
            states[device.id]?.recognizer.resolvePendingTap(token: token) ?? []
        }
        if !outputs.isEmpty {
            dispatch(outputs, device: device)
        }
    }

    // MARK: - Physical clicks

    /// Called for every primary-button press while click gestures are bound.
    /// Returns true if the click was turned into a gesture and should be
    /// swallowed.
    public func handlePhysicalClick() -> Bool {
        let match: (Gesture, DeviceInfo)? = lock.withLock {
            let edgeSize = configuration.settings.edgeSize
            let active = states
                .filter { devices[$0.key]?.kind == .trackpad && !$0.value.frame.touches.isEmpty }
                .max { $0.value.frame.timestamp < $1.value.frame.timestamp }
            guard let (id, state) = active, let device = devices[id] else { return nil }
            let resolver = Resolver(engine: self, device: .trackpad)
            for gesture in ClickClassifier.candidates(for: state.frame.touches, edgeSize: edgeSize)
            where resolver.isBound(gesture) {
                state.recognizer.suppressCurrentSession()
                return (gesture, device)
            }
            return nil
        }
        guard let (gesture, device) = match else { return false }
        dispatch([.gesture(gesture)], device: device)
        return true
    }

    // MARK: - Dispatch

    private func dispatch(_ outputs: [RecognizedGesture], device: DeviceInfo) {
        let application = applications.current
        let functionKeyDown = CGEventSource.flagsState(.combinedSessionState).contains(.maskSecondaryFn)
        let configuration = lock.withLock { self.configuration }

        for output in outputs {
            let (gesture, direction): (Gesture, Direction?) = switch output {
            case .gesture(let gesture): (gesture, nil)
            case .slide(let gesture, let direction): (gesture, direction)
            }
            let binding = configuration.binding(
                for: gesture, device: device.kind, application: application, functionKeyDown: functionKeyDown
            )
            onEvent?(Event(gesture: gesture, direction: direction, device: device.kind, binding: binding, application: application))

            guard performsActions, let binding else { continue }
            let context = ActionRunner.Context(
                gesture: gesture,
                direction: direction,
                device: device.kind,
                application: application,
                processIdentifier: applications.processIdentifier
            )
            switch (binding, direction) {
            case (.action(let action), nil):
                runner.perform(action, context: context)
                feedback(action.haptic ?? configuration.settings.hapticFeedback, device: device, strong: true)
            case (.slide(let slide), let direction?):
                guard let action = slide.actions[direction] else { continue }
                runner.perform(action, context: context)
                slideStepsSinceHaptic += 1
                if slideStepsSinceHaptic >= slide.detent {
                    slideStepsSinceHaptic = 0
                    feedback(slide.haptic ?? action.haptic ?? configuration.settings.hapticFeedback, device: device, strong: false)
                }
            default:
                continue
            }
        }
    }

    private func feedback(_ enabled: Bool, device: DeviceInfo, strong: Bool) {
        guard enabled, device.kind == .trackpad else { return }
        if !OGMTActuate(device.id, strong ? 6 : 3) {
            DispatchQueue.main.async {
                NSHapticFeedbackManager.defaultPerformer.perform(strong ? .generic : .alignment, performanceTime: .now)
            }
        }
    }

    // MARK: - Binding lookup

    /// Answers recognizer questions. Only consulted when a gesture is about
    /// to be decided, never on ordinary frames. Must be used under `lock`.
    private struct Resolver: GestureBindings {
        let engine: GestureEngine
        let device: DeviceKind

        private func binding(for gesture: Gesture) -> Binding? {
            engine.configuration.binding(
                for: gesture,
                device: device,
                application: engine.applications.current,
                functionKeyDown: CGEventSource.flagsState(.combinedSessionState).contains(.maskSecondaryFn)
            )
        }

        func isBound(_ gesture: Gesture) -> Bool {
            if engine.treatsAllGesturesAsBound, !gesture.isContinuous {
                return gesture.supportedDevices.contains(device)
            }
            return binding(for: gesture) != nil
        }

        func slide(for gesture: Gesture) -> SlideTarget? {
            guard case .slide(let slide) = binding(for: gesture) else { return nil }
            return engine.configuration.slideTarget(for: slide)
        }
    }
}
