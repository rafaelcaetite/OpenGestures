import Foundation

public struct Point: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Point(x: 0, y: 0)

    public static func + (lhs: Point, rhs: Point) -> Point {
        Point(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    public static func - (lhs: Point, rhs: Point) -> Point {
        Point(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    public func distance(to other: Point) -> Double {
        hypot(x - other.x, y - other.y)
    }

    public func component(along axis: Axis) -> Double {
        axis == .horizontal ? x : y
    }
}

public enum Axis: String, Sendable {
    case horizontal
    case vertical
}

public enum Direction: String, CaseIterable, Sendable {
    case up
    case down
    case left
    case right

    public var axis: Axis {
        switch self {
        case .up, .down: .vertical
        case .left, .right: .horizontal
        }
    }

    /// Up and right increase the coordinate along their axis.
    public var isPositive: Bool {
        self == .up || self == .right
    }

    public static func along(_ axis: Axis, positive: Bool) -> Direction {
        switch axis {
        case .horizontal: positive ? .right : .left
        case .vertical: positive ? .up : .down
        }
    }
}

public enum Hand: String, Sendable {
    case left
    case right
}
