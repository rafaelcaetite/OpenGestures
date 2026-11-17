import CMultitouch
import CoreGraphics
import Foundation

/// Drops scroll events while three or more fingers drive a bound gesture,
/// so a four-finger slide does not also scroll the window under the pointer.
///
/// macOS starts scrolling as soon as two fingers move, before OpenGestures
/// can tell that more are landing. Once the gesture owns the trackpad, every
/// scroll event of that scroll, including its momentum after the fingers
/// lift, is dropped; the next scroll that begins afterwards passes again.
///
/// The tap runs on its own thread so scrolling never waits on the main
/// thread, and only exists while a three- or four-finger slide or swipe is
/// bound. Deciding costs one atomic load per scroll event.
public final class ScrollBlocker: @unchecked Sendable {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    /// Only touched on the tap thread.
    private var droppingScroll = false

    public init() {}

    public var isRunning: Bool { tap != nil }

    /// Returns false when the tap cannot be created, which happens until
    /// Accessibility permission is granted. Call from the main thread.
    @discardableResult
    public func start() -> Bool {
        guard tap == nil else { return true }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: 1 << CGEventType.scrollWheel.rawValue,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let blocker = Unmanaged<ScrollBlocker>.fromOpaque(context).takeUnretainedValue()
                return blocker.handle(type, event)
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

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }

        if OGIsScrollClaimed() {
            droppingScroll = true
            return nil
        }
        if droppingScroll {
            let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
            let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
            // kCGScrollPhaseBegan: a new scroll, unrelated to the gesture.
            if phase == 1 || (phase == 0 && momentum == 0) {
                droppingScroll = false
            } else {
                return nil
            }
        }
        return Unmanaged.passUnretained(event)
    }
}
