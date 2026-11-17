import CMultitouch
import Foundation
import IOKit

/// Connects to every multitouch device and forwards their contact frames.
///
/// Frames are delivered on a thread owned by MultitouchSupport, roughly a
/// hundred times a second while fingers are down and not at all otherwise.
public final class MultitouchManager: @unchecked Sendable {
    public typealias FrameHandler = @Sendable (
        _ device: DeviceInfo,
        _ contacts: UnsafeBufferPointer<OGMTContact>,
        _ timestamp: Double
    ) -> Void

    private struct Device {
        var reference: OGMTDeviceRef
        var info: DeviceInfo
    }

    /// Magic Mouse family identifiers. Everything else is treated as a trackpad.
    private static let mouseFamilies: Set<Int32> = [112, 113]

    private let handler: FrameHandler
    private let lock = UnfairLock()
    private var deviceList: CFArray?
    private var devices: [Device] = []

    private var notificationPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var onDevicesChanged: (@Sendable () -> Void)?

    public init(handler: @escaping FrameHandler) {
        self.handler = handler
    }

    deinit {
        stop()
        stopWatchingDevices()
    }

    public static var isAvailable: Bool { OGMTIsAvailable() }

    public var connectedDevices: [DeviceInfo] {
        lock.withLock { devices.map(\.info) }
    }

    public var isRunning: Bool {
        lock.withLock { deviceList != nil }
    }

    public func start() {
        guard OGMTIsAvailable() else {
            Log.input.error("MultitouchSupport is unavailable on this system")
            return
        }
        OGMTSetFrameHandler({ context, device, contacts, count, timestamp in
            guard let context else { return }
            let manager = Unmanaged<MultitouchManager>.fromOpaque(context).takeUnretainedValue()
            manager.receive(device: device, contacts: contacts, count: Int(count), timestamp: timestamp)
        }, Unmanaged.passUnretained(self).toOpaque())

        lock.withLock {
            guard deviceList == nil, let list = OGMTCopyDevices() else { return }
            deviceList = list
            devices = (0..<CFArrayGetCount(list)).compactMap { index in
                guard let raw = CFArrayGetValueAtIndex(list, index) else { return nil }
                let reference = UnsafeMutableRawPointer(mutating: raw)
                return Device(reference: reference, info: Self.describe(reference))
            }
            for device in devices {
                OGMTStartDevice(device.reference)
            }
        }
        for device in connectedDevices {
            Log.input.info("Listening to \(device.displayName, privacy: .public) (family \(device.familyID))")
        }
    }

    public func stop() {
        lock.withLock {
            for device in devices {
                OGMTStopDevice(device.reference)
            }
            devices.removeAll()
            deviceList = nil
        }
    }

    public func restart() {
        stop()
        start()
    }

    /// Calls `onChange` on the main thread when a multitouch device is
    /// attached or removed. Uses IOKit notifications, so nothing polls.
    public func watchDevices(onChange: @escaping @Sendable () -> Void) {
        guard notificationPort == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notificationPort = port
        onDevicesChanged = onChange
        IONotificationPortSetDispatchQueue(port, .main)

        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceMatchingCallback = { context, iterator in
            MultitouchManager.drain(iterator)
            guard let context else { return }
            Unmanaged<MultitouchManager>.fromOpaque(context).takeUnretainedValue().onDevicesChanged?()
        }
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let status = IOServiceAddMatchingNotification(
                port, type, IOServiceMatching("AppleMultitouchDevice"), callback, context, &iterator
            )
            if status == KERN_SUCCESS {
                // Arms the notification; the devices already present are
                // picked up by start().
                Self.drain(iterator)
                iterators.append(iterator)
            }
        }
    }

    private func stopWatchingDevices() {
        iterators.forEach { IOObjectRelease($0) }
        iterators.removeAll()
        if let port = notificationPort {
            IONotificationPortDestroy(port)
        }
        notificationPort = nil
    }

    private static func drain(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            IOObjectRelease(service)
        }
    }

    // MARK: - Frames

    private func receive(device: OGMTDeviceRef, contacts: UnsafePointer<OGMTContact>?, count: Int, timestamp: Double) {
        let info: DeviceInfo? = lock.withLock {
            devices.first { $0.reference == device }?.info
        }
        guard let info else { return }
        handler(info, UnsafeBufferPointer(start: contacts, count: contacts == nil ? 0 : count), timestamp)
    }

    private static func describe(_ reference: OGMTDeviceRef) -> DeviceInfo {
        let family = OGMTDeviceFamilyID(reference)
        var width = 0.0, height = 0.0
        if !OGMTDeviceSurfaceSize(reference, &width, &height) {
            (width, height) = (130, 80)
        }
        return DeviceInfo(
            id: OGMTDeviceID(reference),
            kind: mouseFamilies.contains(family) ? .mouse : .trackpad,
            familyID: family,
            isBuiltIn: OGMTDeviceIsBuiltIn(reference),
            width: width,
            height: height
        )
    }
}
