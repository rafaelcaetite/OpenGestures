import Foundation

/// Maps the fingers resting on the trackpad at the moment of a physical click
/// to the gestures that click could trigger, most specific first.
public enum ClickClassifier {
    public static func candidates(for touches: [Touch], edgeSize: Double) -> [Gesture] {
        switch touches.count {
        case 1: return areaCandidates(at: touches[0].normalized, edgeSize: edgeSize)
        case 3: return [.threeFingerClick]
        case 4: return [.fourFingerClick]
        default: return []
        }
    }

    private enum Edge {
        case left, right, top, bottom
    }

    static func areaCandidates(at point: Point, edgeSize: Double) -> [Gesture] {
        let size = min(max(edgeSize, 0.01), 0.5)
        // How far into each edge zone the finger is, 0 at the inner boundary
        // and 1 at the edge itself. Absent when outside that zone.
        var depths: [(Edge, Double)] = []
        if point.x < size { depths.append((.left, (size - point.x) / size)) }
        if point.x > 1 - size { depths.append((.right, (point.x - (1 - size)) / size)) }
        if point.y < size { depths.append((.bottom, (size - point.y) / size)) }
        if point.y > 1 - size { depths.append((.top, (point.y - (1 - size)) / size)) }
        guard let primary = depths.max(by: { $0.1 < $1.1 })?.0 else { return [] }

        var result: [Gesture] = []
        let edges = Set(depths.map { "\($0.0)" })
        let horizontal = edges.contains("left") ? "left" : edges.contains("right") ? "right" : nil
        let vertical = edges.contains("top") ? "top" : edges.contains("bottom") ? "bottom" : nil
        if let horizontal, let vertical {
            result += [Gesture(rawValue: "\(vertical)-\(horizontal)-corner-click"), .cornerClick].compactMap { $0 }
        }

        let edgeName: String
        let along: Double
        let lowName: String, highName: String
        switch primary {
        case .left, .right:
            edgeName = primary == .left ? "left" : "right"
            along = point.y
            (lowName, highName) = ("bottom", "top")
        case .top, .bottom:
            edgeName = primary == .top ? "top" : "bottom"
            along = point.x
            (lowName, highName) = ("left", "right")
        }

        let third = along < 1.0 / 3 ? lowName : along > 2.0 / 3 ? highName : "middle"
        let half = along < 0.5 ? lowName : highName
        result += [
            Gesture(rawValue: "\(edgeName)-edge-\(third)-third-click"),
            Gesture(rawValue: "\(edgeName)-edge-\(half)-half-click"),
            Gesture(rawValue: "\(edgeName)-edge-click"),
            .edgeClick,
        ].compactMap { $0 }
        return result
    }
}
