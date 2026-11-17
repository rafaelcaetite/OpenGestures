import CMultitouch
import CoreGraphics
import Foundation
import os

/// Filters scroll events for two jobs:
///
/// - Dropping scrolls while three or more fingers drive a bound gesture, so
///   a four-finger slide does not also scroll the window under the pointer.
///   macOS starts scrolling as soon as two fingers move, before OpenGestures
///   can tell that more are landing. Once the gesture owns the trackpad,
///   every event of that scroll, momentum included, is dropped; the next
///   scroll that begins afterwards passes again.
/// - Giving the trackpad and mice their own scroll direction. macOS has one
///   natural scrolling setting for both; events from the device whose
///   chosen direction differs from it are reversed.
///
/// The source of a scroll is decided when it begins: wheel events come from
/// a mouse, and continuous ones from whichever multitouch surface has
/// fingers on it, so a Magic Mouse counts as a mouse. Later events of the
/// same scroll, and its momentum, follow that decision.
///
/// The tap runs on its own thread so scrolling never waits on the main
/// thread, and only exists while one of the two jobs is configured.
public final class ScrollInterceptor: @unchecked Sendable {
    public struct Options: Equatable, Sendable {
        /// Drop scrolls while a bound gesture owns the trackpad.
        public var blocksDuringGestures = false
        public var trackpadNaturalScrolling: Bool?
        public var mouseNaturalScrolling: Bool?

        public init() {}

        public var needsTap: Bool {
            blocksDuringGestures || trackpadNaturalScrolling != nil || mouseNaturalScrolling != nil
        }
    }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private let options = OSAllocatedUnfairLock(initialState: Options())

    // Only touched on the tap thread.
    private var droppingScroll = false
    private var reversingScroll = false
    private var systemNatural = true
    private var systemNaturalReadAt: TimeInterval = -.infinity

    public init() {}

    public var isRunning: Bool { tap != nil }

    /// Applies `options`, creating or removing the tap as needed. Returns
    /// false when a needed tap cannot be created, which happens until
    /// Accessibility permission is granted. Call from the main thread.
    @discardableResult
    public func update(_ options: Options) -> Bool {
        self.options.withLock { $0 = options }
        guard options.needsTap else {
            stop()
            return true
        }
        return start()
    }

    private func start() -> Bool {
        guard tap == nil else { return true }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: 1 << CGEventType.scrollWheel.rawValue,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let interceptor = Unmanaged<ScrollInterceptor>.fromOpaque(context).takeUnretainedValue()
                return interceptor.handle(type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            runTap()
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "\(Log.subsystem).scroll"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        return true
    }

    /// Attaches the tap to the calling thread's run loop.
    private func runTap() {
        guard let tap, let source else { return }
        let current = CFRunLoopGetCurrent()
        runLoop = current
        CFRunLoopAddSource(current, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    public func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        if let runLoop {
            CFRunLoopStop(runLoop)
        }
        self.tap = nil
        source = nil
        runLoop = nil
        OGSetScrollClaimed(false)
    }

    // MARK: - Events

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }

        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        // Began or may-begin, or a plain wheel event: the start of a scroll.
        let starts = phase == 1 || phase == 128 || (phase == 0 && momentum == 0)
        let options = options.withLock { $0 }

        if options.blocksDuringGestures, OGIsScrollClaimed() {
            droppingScroll = true
            return nil
        }
        if droppingScroll {
            guard starts else { return nil }
            droppingScroll = false
        }

        if starts {
            reversingScroll = shouldReverse(event, options: options)
        }
        if reversingScroll {
            Self.reverse(event)
        }
        return Unmanaged.passUnretained(event)
    }

    private func shouldReverse(_ event: CGEvent, options: Options) -> Bool {
        guard options.trackpadNaturalScrolling != nil || options.mouseNaturalScrolling != nil else { return false }
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let touching = OGTouchingDevices()
        let fromMouse = !continuous || (touching & Int32(OGTouchingMouse) != 0 && touching & Int32(OGTouchingTrackpad) == 0)
        guard let wanted = fromMouse ? options.mouseNaturalScrolling : options.trackpadNaturalScrolling else {
            return false
        }
        return wanted != isSystemNatural()
    }

    /// The system setting, read at most once a second; it changes rarely
    /// and a read goes through the preferences daemon.
    private func isSystemNatural() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if now - systemNaturalReadAt > 1 {
            systemNaturalReadAt = now
            let value = CFPreferencesCopyAppValue("com.apple.swipescrolldirection" as CFString, kCFPreferencesAnyApplication)
            systemNatural = (value as? Bool) ?? true
        }
        return systemNatural
    }

    /// Negates every delta. All values are read before any is written,
    /// because setting one delta field updates the related ones.
    private static func reverse(_ event: CGEvent) {
        let integerFields: [CGEventField] = [
            .scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2,
            .scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2,
        ]
        let fixedFields: [CGEventField] = [.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2]
        let integers = integerFields.map { event.getIntegerValueField($0) }
        let fixed = fixedFields.map { event.getDoubleValueField($0) }
        for (field, value) in zip(integerFields, integers) {
            event.setIntegerValueField(field, value: -value)
        }
        for (field, value) in zip(fixedFields, fixed) {
            event.setDoubleValueField(field, value: -value)
        }
    }
}
