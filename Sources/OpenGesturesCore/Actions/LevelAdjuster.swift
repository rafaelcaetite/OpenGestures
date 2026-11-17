import AudioToolbox
import CoreAudio
import CoreGraphics
import Foundation
import os
import IOKit.hidsystem

/// Moves volume and display brightness by quarter steps, as fast as a
/// slide asks for them.
///
/// macOS takes about 10 ms to handle each synthesized media key, so a quick
/// slide that produces 60 steps used to queue more than half a second of
/// keys, and the level trailed the finger. Here steps are accumulated from
/// the multitouch thread and applied in one go: the level is set directly,
/// which takes effect at once, and a single quarter-step key is sent at most
/// every `overlayInterval` so the system overlay shows the new level. The
/// key is sent from one quarter step short of the target, so the overlay
/// lands exactly on it.
///
/// When the level cannot be set directly (an output without volume control,
/// an external display), it falls back to sending one key per step.
final class LevelAdjuster: @unchecked Sendable {
    enum Level: Sendable {
        case volume
        case brightness

        init?(_ action: BuiltInAction) {
            switch action {
            case .volumeUpFine, .volumeDownFine: self = .volume
            case .brightnessUpFine, .brightnessDownFine: self = .brightness
            default: return nil
            }
        }

        fileprivate func key(up: Bool) -> Int32 {
            switch self {
            case .volume: up ? NX_KEYTYPE_SOUND_UP : NX_KEYTYPE_SOUND_DOWN
            case .brightness: up ? NX_KEYTYPE_BRIGHTNESS_UP : NX_KEYTYPE_BRIGHTNESS_DOWN
            }
        }
    }

    /// A quarter of one of the sixteen steps macOS uses.
    private static let quarterStep: Float = 1 / 64
    private static let overlayInterval: TimeInterval = 0.033

    private let queue = DispatchQueue(label: "\(Log.subsystem).levels", qos: .userInteractive)
    private let lock = UnfairLock()
    private var pending: (level: Level, steps: Int)?
    private var drainScheduled = false

    // Only touched on `queue`.
    /// Where the level is heading, kept here instead of read back, because
    /// a key still being handled by the system would make a read stale.
    private var target: (level: Level, value: Float)?
    private var lastActivity: TimeInterval = 0
    private var lastOverlay: TimeInterval = 0
    private var overlayOwed: (level: Level, up: Bool)?
    private var overlayScheduled = false

    /// Adds one quarter step. Safe to call from any thread; never blocks on
    /// the work itself.
    func adjust(_ level: Level, up: Bool) {
        let schedule: Bool = lock.withLock {
            if let current = pending, current.level == level {
                pending = (level, current.steps + (up ? 1 : -1))
            } else {
                pending = (level, up ? 1 : -1)
            }
            defer { drainScheduled = true }
            return !drainScheduled
        }
        if schedule {
            queue.async { self.drain() }
        }
    }

    private func drain() {
        let taken = lock.withLock {
            defer {
                pending = nil
                drainScheduled = false
            }
            return pending
        }
        guard let (level, steps) = taken, steps != 0 else { return }
        let up = steps > 0
        let now = ProcessInfo.processInfo.systemUptime

        // Start from the real level when a new slide begins, in case it was
        // changed some other way since the last one.
        var base = target?.level == level && now - lastActivity < 0.5 ? target?.value : nil
        if base == nil {
            base = Self.read(level)
        }
        lastActivity = now
        guard let base else {
            for _ in 0..<abs(steps) {
                EventPoster.postSystemKey(level.key(up: up), fine: true)
            }
            return
        }

        let value = min(max(base + Float(steps) * Self.quarterStep, 0), 1)
        target = (level, value)
        if now - lastOverlay >= Self.overlayInterval {
            showOverlay(level, at: value, up: up)
        } else {
            Self.write(level, value)
            overlayOwed = (level, up)
            scheduleOwedOverlay(after: Self.overlayInterval - (now - lastOverlay))
        }
    }

    /// Sets the level a quarter step short of `value` and sends the key that
    /// covers the rest, which also draws the overlay. Waits, briefly, for the
    /// system to apply the key, so later steps never race with it, then
    /// settles on `value` exactly.
    private func showOverlay(_ level: Level, at value: Float, up: Bool) {
        let start = up ? max(value - Self.quarterStep, 0) : min(value + Self.quarterStep, 1)
        Self.write(level, start)
        EventPoster.postSystemKey(level.key(up: up), fine: true)
        let deadline = ProcessInfo.processInfo.systemUptime + 0.05
        while ProcessInfo.processInfo.systemUptime < deadline {
            if let now = Self.read(level), abs(now - start) > 0.001 { break }
            usleep(1_000)
        }
        if start != value || Self.read(level).map({ abs($0 - value) > 0.001 }) == true {
            Self.write(level, value)
        }
        lastOverlay = ProcessInfo.processInfo.systemUptime
        overlayOwed = nil
    }

    private func scheduleOwedOverlay(after delay: TimeInterval) {
        guard !overlayScheduled else { return }
        overlayScheduled = true
        queue.asyncAfter(deadline: .now() + max(delay, 0)) {
            self.overlayScheduled = false
            guard let owed = self.overlayOwed, let target = self.target, target.level == owed.level else { return }
            self.showOverlay(owed.level, at: target.value, up: owed.up)
        }
    }

    // MARK: - Reading and writing levels

    private static func read(_ level: Level) -> Float? {
        switch level {
        case .volume: SystemVolume.get()
        case .brightness: DisplayBrightness.get()
        }
    }

    private static func write(_ level: Level, _ value: Float) {
        switch level {
        case .volume: SystemVolume.set(value)
        case .brightness: DisplayBrightness.set(value)
        }
    }
}

/// The main volume of the default output device, through Core Audio.
///
/// Finding the default device costs about half a millisecond, more than the
/// read itself, so the device and whether its volume can be set are kept
/// until Core Audio reports that the default output changed.
private enum SystemVolume {
    private static let volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    private struct Output {
        var device: AudioObjectID
        var settable: Bool
    }

    private static let cache = OSAllocatedUnfairLock<Output?>(initialState: nil)

    private static let watchDefaultOutput: Void = {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, nil) { _, _ in
            cache.withLock { $0 = nil }
        }
    }()

    private static func output() -> Output? {
        _ = watchDefaultOutput
        if let cached = cache.withLock({ $0 }) {
            return cached
        }
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        var volume = volumeAddress
        var settable: DarwinBoolean = false
        let canSet = AudioObjectIsPropertySettable(device, &volume, &settable) == noErr && settable.boolValue
        let output = Output(device: device, settable: canSet)
        cache.withLock { $0 = output }
        return output
    }

    /// Nil when the output has no volume the system can set.
    static func get() -> Float? {
        guard let output = output(), output.settable else { return nil }
        var address = volumeAddress
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(output.device, &address, 0, nil, &size, &volume) == noErr else { return nil }
        return volume
    }

    static func set(_ value: Float) {
        guard let output = output(), output.settable else { return }
        var address = volumeAddress
        var volume = Float32(value)
        AudioObjectSetPropertyData(output.device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
    }
}

/// The built-in display's brightness, through the private DisplayServices
/// framework that the brightness keys use. Loaded on first use.
private enum DisplayBrightness {
    private typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Set = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let functions: (get: Get, set: Set)? = {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_LAZY),
              let get = dlsym(handle, "DisplayServicesGetBrightness"),
              let set = dlsym(handle, "DisplayServicesSetBrightness")
        else { return nil }
        return (unsafeBitCast(get, to: Get.self), unsafeBitCast(set, to: Set.self))
    }()

    private static func builtInDisplay() -> CGDirectDisplayID? {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    static func get() -> Float? {
        guard let functions, let display = builtInDisplay() else { return nil }
        var value: Float = 0
        return functions.get(display, &value) == 0 ? value : nil
    }

    static func set(_ value: Float) {
        guard let functions, let display = builtInDisplay() else { return }
        _ = functions.set(display, value)
    }
}
