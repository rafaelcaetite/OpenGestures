import Foundation

/// A finger in contact with a multitouch surface.
public struct Touch: Hashable, Sendable {
    public var id: Int32
    /// Millimetres from the bottom-left corner of the surface.
    public var position: Point
    /// Fraction of the surface from the bottom-left corner, 0 through 1.
    public var normalized: Point

    public init(id: Int32, position: Point, normalized: Point) {
        self.id = id
        self.position = position
        self.normalized = normalized
    }
}

/// Every finger touching a device at one instant.
public struct TouchFrame: Sendable {
    public var timestamp: TimeInterval
    public var touches: [Touch]

    public init(timestamp: TimeInterval, touches: [Touch]) {
        self.timestamp = timestamp
        self.touches = touches
    }
}

public enum DeviceKind: String, CaseIterable, Sendable {
    case trackpad
    case mouse

    /// The configuration table that holds this device's bindings.
    public var sectionName: String { rawValue.uppercased() }
}

public struct DeviceInfo: Hashable, Sendable {
    public var id: UInt64
    public var kind: DeviceKind
    public var familyID: Int32
    public var isBuiltIn: Bool
    /// Surface size in millimetres.
    public var width: Double
    public var height: Double

    public init(id: UInt64, kind: DeviceKind, familyID: Int32, isBuiltIn: Bool, width: Double, height: Double) {
        self.id = id
        self.kind = kind
        self.familyID = familyID
        self.isBuiltIn = isBuiltIn
        self.width = width
        self.height = height
    }

    public var displayName: String {
        switch kind {
        case .trackpad: isBuiltIn ? "Built-in trackpad" : "Magic Trackpad"
        case .mouse: "Magic Mouse"
        }
    }
}
