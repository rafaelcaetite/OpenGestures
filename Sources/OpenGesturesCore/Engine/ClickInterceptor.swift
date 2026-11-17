import CoreGraphics

/// Watches primary-button presses so that clicks with three or four fingers,
/// or in an edge or corner, can trigger bindings instead.
///
/// The event tap only exists while click gestures are bound; otherwise mouse
/// events never pass through OpenGestures at all. Create, start and stop it
/// on the main thread; the tap delivers events on the main run loop.
public final class ClickInterceptor: @unchecked Sendable {
    private let engine: GestureEngine
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var swallowing = false

    public init(engine: GestureEngine) {
        self.engine = engine
    }

    public var isRunning: Bool { tap != nil }

    /// Returns false when the tap cannot be created, which happens until
    /// Accessibility permission is granted.
    @discardableResult
    public func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let interceptor = Unmanaged<ClickInterceptor>.fromOpaque(context).takeUnretainedValue()
                return interceptor.handle(type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    public func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        source = nil
        swallowing = false
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .leftMouseDown:
            if engine.handlePhysicalClick() {
                swallowing = true
                return nil
            }
        case .leftMouseDragged:
            if swallowing { return nil }
        case .leftMouseUp:
            if swallowing {
                swallowing = false
                return nil
            }
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }
}
