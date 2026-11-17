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

    /// Magic Mouse family identifiers, used only when the registry has no
    /// product name. Family 113 is also the built-in trackpad of some
    /// MacBook Pros, so built-in devices never count as a mouse.
    private static let mouseFamilies: Set<Int32> = [112, 113]
    /// The Touch Bar reports itself as a multitouch device.
    private static let touchBarFamily: Int32 = 176

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
                return Self.describe(reference).map { Device(reference: reference, info: $0) }
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

    /// Nil for surfaces that are not for gestures, such as the Touch Bar.
    private static func describe(_ reference: OGMTDeviceRef) -> DeviceInfo? {
        let id = OGMTDeviceID(reference)
        let family = OGMTDeviceFamilyID(reference)
        let isBuiltIn = OGMTDeviceIsBuiltIn(reference)
        let registry = RegistryDescription(multitouchID: id)

        let kind: DeviceKind
        if let registry {
            if registry.product.localizedCaseInsensitiveContains("touch bar") || (registry.rows ?? 99) <= 4 {
                return nil
            }
            kind = !isBuiltIn && registry.product.localizedCaseInsensitiveContains("mouse") ? .mouse : .trackpad
        } else {
            if family == touchBarFamily { return nil }
            kind = !isBuiltIn && mouseFamilies.contains(family) ? .mouse : .trackpad
        }

        var width = 0.0, height = 0.0
        if !OGMTDeviceSurfaceSize(reference, &width, &height) {
            (width, height) = (130, 80)
        }
        return DeviceInfo(id: id, kind: kind, familyID: family, isBuiltIn: isBuiltIn, width: width, height: height)
    }
}

/// What the I/O Registry says about a multitouch device: its product name,
/// such as "Magic Mouse" or "Apple Internal Keyboard / Trackpad", and its
/// sensor rows. More reliable than family identifiers, which differ between
/// models and, for 113, mean a mouse on some and a trackpad on others.
private struct RegistryDescription {
    var product: String
    var rows: Int?

    init?(multitouchID: UInt64) {
        guard let matching = IOServiceMatching("AppleMultitouchDevice") as NSMutableDictionary? else { return nil }
        matching["IOPropertyMatch"] = ["Multitouch ID": NSNumber(value: multitouchID)]
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        func property(_ key: String) -> Any? {
            IORegistryEntrySearchCFProperty(
                service, kIOServicePlane, key as CFString, kCFAllocatorDefault,
                IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
            )
        }
        guard let product = property("Product") as? String else { return nil }
        self.product = product
        rows = (property("Sensor Rows") as? NSNumber)?.intValue
    }
}
