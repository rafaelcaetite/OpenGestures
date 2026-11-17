import Foundation

/// Every gesture a binding can name. The raw value is the name used in the
/// configuration file.
public enum Gesture: String, CaseIterable, Sendable {
    case oneFingerTap = "one-finger-tap"
    case twoFingerTap = "two-finger-tap"
    case threeFingerTap = "three-finger-tap"
    case fourFingerTap = "four-finger-tap"
    case fiveFingerTap = "five-finger-tap"

    case oneFingerDoubleTap = "one-finger-double-tap"
    case twoFingerDoubleTap = "two-finger-double-tap"
    case threeFingerDoubleTap = "three-finger-double-tap"
    case fourFingerDoubleTap = "four-finger-double-tap"
    case fiveFingerDoubleTap = "five-finger-double-tap"

    case holdLeftTapRight = "hold-left-tap-right"
    case holdRightTapLeft = "hold-right-tap-left"
    case holdTwoTapLeft = "hold-two-tap-left"
    case holdTwoTapRight = "hold-two-tap-right"
    case holdTwoTapBetween = "hold-two-tap-between"
    case holdThreeTapLeft = "hold-three-tap-left"
    case holdThreeTapRight = "hold-three-tap-right"

    case oneFingerSwipe = "one-finger-swipe"
    case oneFingerSwipeLeft = "one-finger-swipe-left"
    case oneFingerSwipeRight = "one-finger-swipe-right"
    case oneFingerSwipeUp = "one-finger-swipe-up"
    case oneFingerSwipeDown = "one-finger-swipe-down"
    case twoFingerSwipe = "two-finger-swipe"
    case twoFingerSwipeLeft = "two-finger-swipe-left"
    case twoFingerSwipeRight = "two-finger-swipe-right"
    case twoFingerSwipeUp = "two-finger-swipe-up"
    case twoFingerSwipeDown = "two-finger-swipe-down"
    case threeFingerSwipe = "three-finger-swipe"
    case threeFingerSwipeLeft = "three-finger-swipe-left"
    case threeFingerSwipeRight = "three-finger-swipe-right"
    case threeFingerSwipeUp = "three-finger-swipe-up"
    case threeFingerSwipeDown = "three-finger-swipe-down"
    case fourFingerSwipe = "four-finger-swipe"
    case fourFingerSwipeLeft = "four-finger-swipe-left"
    case fourFingerSwipeRight = "four-finger-swipe-right"
    case fourFingerSwipeUp = "four-finger-swipe-up"
    case fourFingerSwipeDown = "four-finger-swipe-down"

    case twoFingerSlide = "two-finger-slide"
    case threeFingerSlide = "three-finger-slide"
    case fourFingerSlide = "four-finger-slide"
    case holdSlide = "hold-slide"

    case indexToPinky = "index-to-pinky"
    case pinkyToIndex = "pinky-to-index"

    case threeFingerClick = "three-finger-click"
    case fourFingerClick = "four-finger-click"

    case edgeClick = "edge-click"
    case cornerClick = "corner-click"
    case leftEdgeClick = "left-edge-click"
    case rightEdgeClick = "right-edge-click"
    case topEdgeClick = "top-edge-click"
    case bottomEdgeClick = "bottom-edge-click"
    case leftEdgeTopHalfClick = "left-edge-top-half-click"
    case leftEdgeBottomHalfClick = "left-edge-bottom-half-click"
    case rightEdgeTopHalfClick = "right-edge-top-half-click"
    case rightEdgeBottomHalfClick = "right-edge-bottom-half-click"
    case topEdgeLeftHalfClick = "top-edge-left-half-click"
    case topEdgeRightHalfClick = "top-edge-right-half-click"
    case bottomEdgeLeftHalfClick = "bottom-edge-left-half-click"
    case bottomEdgeRightHalfClick = "bottom-edge-right-half-click"
    case leftEdgeTopThirdClick = "left-edge-top-third-click"
    case leftEdgeMiddleThirdClick = "left-edge-middle-third-click"
    case leftEdgeBottomThirdClick = "left-edge-bottom-third-click"
    case rightEdgeTopThirdClick = "right-edge-top-third-click"
    case rightEdgeMiddleThirdClick = "right-edge-middle-third-click"
    case rightEdgeBottomThirdClick = "right-edge-bottom-third-click"
    case topEdgeLeftThirdClick = "top-edge-left-third-click"
    case topEdgeMiddleThirdClick = "top-edge-middle-third-click"
    case topEdgeRightThirdClick = "top-edge-right-third-click"
    case bottomEdgeLeftThirdClick = "bottom-edge-left-third-click"
    case bottomEdgeMiddleThirdClick = "bottom-edge-middle-third-click"
    case bottomEdgeRightThirdClick = "bottom-edge-right-third-click"
    case topLeftCornerClick = "top-left-corner-click"
    case topRightCornerClick = "top-right-corner-click"
    case bottomLeftCornerClick = "bottom-left-corner-click"
    case bottomRightCornerClick = "bottom-right-corner-click"

    public enum Category: String, CaseIterable, Sendable {
        case tap = "Taps"
        case doubleTap = "Double taps"
        case hold = "Hold and tap"
        case swipe = "Swipes"
        case slide = "Slides (continuous)"
        case brush = "Brushes"
        case click = "Physical clicks"
    }

    public var category: Category {
        let name = rawValue
        if name.hasSuffix("-click") { return .click }
        if self == .indexToPinky || self == .pinkyToIndex { return .brush }
        if name.hasSuffix("-slide") { return .slide }
        if name.contains("-swipe") { return .swipe }
        if name.hasPrefix("hold-") { return .hold }
        if name.hasSuffix("-double-tap") { return .doubleTap }
        return .tap
    }

    /// Continuous gestures fire repeatedly while the fingers keep moving.
    public var isContinuous: Bool { category == .slide }

    public var fingerCount: Int? {
        Self.fingerWords.firstIndex { rawValue.hasPrefix("\($0)-finger") }.map { $0 + 1 }
    }

    public var supportedDevices: Set<DeviceKind> {
        switch category {
        case .click, .brush:
            return [.trackpad]
        case .hold:
            return [.trackpad, .mouse]
        case .slide:
            return self == .twoFingerSlide ? [.mouse] : [.trackpad]
        case .swipe:
            return (fingerCount ?? 0) <= 2 ? [.mouse] : [.trackpad]
        case .tap, .doubleTap:
            switch fingerCount ?? 0 {
            case 1: return [.mouse]
            case 2, 3: return [.trackpad, .mouse]
            default: return [.trackpad]
            }
        }
    }

    public var summary: String {
        let fingers = fingerCount.map { Self.fingerWords[$0 - 1] } ?? ""
        switch self {
        case .holdLeftTapRight: return "Hold one finger, tap another to its right"
        case .holdRightTapLeft: return "Hold one finger, tap another to its left"
        case .holdTwoTapLeft: return "Hold two fingers, tap to their left"
        case .holdTwoTapRight: return "Hold two fingers, tap to their right"
        case .holdTwoTapBetween: return "Hold two fingers, tap between them"
        case .holdThreeTapLeft: return "Hold three fingers, tap to their left"
        case .holdThreeTapRight: return "Hold three fingers, tap to their right"
        case .holdSlide: return "Hold one finger still and slide another"
        case .indexToPinky: return "Land four fingers one after another, index first"
        case .pinkyToIndex: return "Land four fingers one after another, little finger first"
        case .threeFingerClick, .fourFingerClick: return "Press the trackpad with \(fingers) fingers"
        case .edgeClick: return "Press with one finger near any edge"
        case .cornerClick: return "Press with one finger in any corner"
        default: break
        }
        switch category {
        case .tap: return "Tap with \(fingers) finger\(fingers == "one" ? "" : "s")"
        case .doubleTap: return "Double-tap with \(fingers) finger\(fingers == "one" ? "" : "s")"
        case .swipe:
            let direction = rawValue.components(separatedBy: "-swipe").last?.dropFirst() ?? ""
            let suffix = direction.isEmpty ? " in any direction" : " \(direction)"
            return "Swipe \(fingers) finger\(fingers == "one" ? "" : "s")\(suffix)"
        case .slide: return "Slide \(fingers) fingers and keep moving"
        case .click:
            let area = rawValue.replacingOccurrences(of: "-click", with: "").replacingOccurrences(of: "-", with: " ")
            return "Press with one finger in the \(area) area"
        default: return rawValue
        }
    }

    // MARK: - Lookup by shape

    static let fingerWords = ["one", "two", "three", "four", "five"]

    private static func named(_ fingers: Int, _ suffix: String) -> Gesture? {
        guard (1...5).contains(fingers) else { return nil }
        return Gesture(rawValue: "\(fingerWords[fingers - 1])-finger-\(suffix)")
    }

    public static func tap(fingers: Int) -> Gesture? { named(fingers, "tap") }
    public static func doubleTap(fingers: Int) -> Gesture? { named(fingers, "double-tap") }
    public static func swipe(fingers: Int) -> Gesture? { named(fingers, "swipe") }
    public static func swipe(fingers: Int, direction: Direction) -> Gesture? {
        named(fingers, "swipe-\(direction.rawValue)")
    }
    public static func slide(fingers: Int) -> Gesture? { named(fingers, "slide") }
}
