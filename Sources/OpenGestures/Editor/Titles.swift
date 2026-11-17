import Foundation
import OpenGesturesCore

/// Display names for the editor. Keys are the English text; translations
/// live in Resources/<language>.lproj/Localizable.strings.
enum Titles {
    static func gesture(_ gesture: Gesture) -> String {
        let fingers = gesture.fingerCount ?? 0
        switch gesture {
        case .holdLeftTapRight: return String(localized: "Hold, tap right")
        case .holdRightTapLeft: return String(localized: "Hold, tap left")
        case .holdTwoTapLeft: return String(localized: "Hold two, tap left")
        case .holdTwoTapRight: return String(localized: "Hold two, tap right")
        case .holdTwoTapBetween: return String(localized: "Hold two, tap between")
        case .holdThreeTapLeft: return String(localized: "Hold three, tap left")
        case .holdThreeTapRight: return String(localized: "Hold three, tap right")
        case .holdSlide: return String(localized: "Hold and slide")
        case .indexToPinky: return String(localized: "Index to pinky")
        case .pinkyToIndex: return String(localized: "Pinky to index")
        case .edgeClick: return String(localized: "Click any edge")
        case .cornerClick: return String(localized: "Click any corner")
        case .topLeftCornerClick: return String(localized: "Click top-left corner")
        case .topRightCornerClick: return String(localized: "Click top-right corner")
        case .bottomLeftCornerClick: return String(localized: "Click bottom-left corner")
        case .bottomRightCornerClick: return String(localized: "Click bottom-right corner")
        case .threeFingerClick, .fourFingerClick: return String(localized: "\(fingers)-finger click")
        default: break
        }

        switch gesture.category {
        case .tap:
            return fingers == 1 ? String(localized: "One-finger tap") : String(localized: "\(fingers)-finger tap")
        case .doubleTap:
            return fingers == 1
                ? String(localized: "One-finger double tap")
                : String(localized: "\(fingers)-finger double tap")
        case .swipe:
            guard let direction = SwipeShape(gesture)?.direction else {
                return fingers == 1 ? String(localized: "One-finger swipe") : String(localized: "\(fingers)-finger swipe")
            }
            let way = Self.direction(direction)
            return fingers == 1
                ? String(localized: "One-finger swipe \(way)")
                : String(localized: "\(fingers)-finger swipe \(way)")
        case .slide:
            return String(localized: "\(fingers)-finger slide")
        case .click:
            return edgeClick(gesture) ?? gesture.rawValue
        case .hold, .brush:
            return gesture.rawValue
        }
    }

    private static func direction(_ direction: Direction) -> String {
        switch direction {
        case .left: String(localized: "left", comment: "Swipe direction")
        case .right: String(localized: "right", comment: "Swipe direction")
        case .up: String(localized: "up", comment: "Swipe direction")
        case .down: String(localized: "down", comment: "Swipe direction")
        }
    }

    private static func edgeClick(_ gesture: Gesture) -> String? {
        guard let zone = ClickZone(gesture), let edge = zone.edge else { return nil }
        let part: String? = switch zone.part {
        case nil: nil
        case .half(.top): String(localized: "top half")
        case .half(.bottom): String(localized: "bottom half")
        case .half(.left): String(localized: "left half")
        case .half(.right): String(localized: "right half")
        case .third(.top): String(localized: "top third")
        case .third(.middle): String(localized: "middle third")
        case .third(.bottom): String(localized: "bottom third")
        case .third(.left): String(localized: "left third")
        case .third(.right): String(localized: "right third")
        }
        switch (edge, part) {
        case (.left, nil): return String(localized: "Click left edge")
        case (.right, nil): return String(localized: "Click right edge")
        case (.top, nil): return String(localized: "Click top edge")
        case (.bottom, nil): return String(localized: "Click bottom edge")
        case (.left, let part?): return String(localized: "Click left edge, \(part)")
        case (.right, let part?): return String(localized: "Click right edge, \(part)")
        case (.top, let part?): return String(localized: "Click top edge, \(part)")
        case (.bottom, let part?): return String(localized: "Click bottom edge, \(part)")
        }
    }

    static func category(_ category: Gesture.Category) -> String {
        switch category {
        case .tap: String(localized: "Taps")
        case .doubleTap: String(localized: "Double taps")
        case .hold: String(localized: "Hold and tap")
        case .swipe: String(localized: "Swipes")
        case .slide: String(localized: "Continuous slides")
        case .brush: String(localized: "Finger rolls")
        case .click: String(localized: "Clicks")
        }
    }

    static func device(_ device: DeviceKind) -> String {
        switch device {
        case .trackpad: String(localized: "Trackpad")
        case .mouse: String(localized: "Magic Mouse")
        }
    }

    static func preset(_ preset: SlidePreset) -> String {
        switch preset {
        case .volume: String(localized: "Volume")
        case .brightness: String(localized: "Display brightness")
        case .keyboardBacklight: String(localized: "Keyboard backlight")
        case .zoom: String(localized: "Zoom")
        case .tabs: String(localized: "Switch tabs")
        case .history: String(localized: "Back and forward")
        case .undo: String(localized: "Undo and redo")
        case .spaces: String(localized: "Switch desktops")
        case .tracks: String(localized: "Previous and next track")
        case .apps: String(localized: "Switch apps")
        }
    }

    static func action(_ action: BuiltInAction) -> String {
        switch action {
        case .missionControl: String(localized: "Mission Control")
        case .appExpose: String(localized: "App windows")
        case .showDesktop: String(localized: "Show desktop")
        case .launchpad: String(localized: "Launchpad")
        case .nextApp: String(localized: "Next app")
        case .previousApp: String(localized: "Previous app")
        case .lastApp: String(localized: "Last used app")
        case .nextTab: String(localized: "Next tab")
        case .previousTab: String(localized: "Previous tab")
        case .newTab: String(localized: "New tab")
        case .closeTab: String(localized: "Close tab")
        case .reopenTab: String(localized: "Reopen closed tab")
        case .maximize: String(localized: "Zoom window")
        case .fullScreen: String(localized: "Full screen")
        case .minimize: String(localized: "Minimize window")
        case .playPause: String(localized: "Play or pause")
        case .nextTrack: String(localized: "Next track")
        case .previousTrack: String(localized: "Previous track")
        case .mute: String(localized: "Mute")
        case .volumeUp: String(localized: "Volume up")
        case .volumeDown: String(localized: "Volume down")
        case .brightnessUp: String(localized: "Brightness up")
        case .brightnessDown: String(localized: "Brightness down")
        case .keyboardBacklightUp: String(localized: "Keyboard backlight up")
        case .keyboardBacklightDown: String(localized: "Keyboard backlight down")
        case .volumeUpFine: String(localized: "Volume up a little")
        case .volumeDownFine: String(localized: "Volume down a little")
        case .brightnessUpFine: String(localized: "Brightness up a little")
        case .brightnessDownFine: String(localized: "Brightness down a little")
        case .keyboardBacklightUpFine: String(localized: "Keyboard backlight up a little")
        case .keyboardBacklightDownFine: String(localized: "Keyboard backlight down a little")
        case .middleClick: String(localized: "Middle click")
        }
    }

    /// Built-in actions as the action menu groups them.
    static let actionGroups: [(title: String, actions: [BuiltInAction])] = [
        (String(localized: "System"), [.missionControl, .appExpose, .showDesktop, .launchpad]),
        (String(localized: "Apps"), [.nextApp, .previousApp, .lastApp]),
        (String(localized: "Tabs"), [.nextTab, .previousTab, .newTab, .closeTab, .reopenTab]),
        (String(localized: "Windows"), [.maximize, .fullScreen, .minimize]),
        (String(localized: "Media"), [.playPause, .nextTrack, .previousTrack, .mute, .volumeUp, .volumeDown]),
        (String(localized: "Display"), [.brightnessUp, .brightnessDown, .keyboardBacklightUp, .keyboardBacklightDown]),
        (String(localized: "Mouse"), [.middleClick]),
    ]

    /// A macOS feature named by `SystemGestures`, as System Settings calls it.
    static func feature(_ name: String) -> String {
        String(localized: String.LocalizationValue(name))
    }
}

/// The direction of a swipe gesture, read from its name.
struct SwipeShape {
    var direction: Direction?

    init?(_ gesture: Gesture) {
        guard gesture.category == .swipe else { return nil }
        direction = Direction.allCases.first { gesture.rawValue.hasSuffix("-swipe-\($0.rawValue)") }
    }
}

/// Where an area click lands, read from its name.
struct ClickZone {
    enum Edge { case left, right, top, bottom }
    enum Half { case top, bottom, left, right }
    enum Third { case top, middle, bottom, left, right }
    enum Part { case half(Half), third(Third) }

    /// Nil for corners.
    var edge: Edge?
    var part: Part?
    /// For corners: the corner, as (right, top).
    var corner: (right: Bool, top: Bool)?

    init?(_ gesture: Gesture) {
        let name = gesture.rawValue
        guard gesture.category == .click, name != "edge-click", name != "corner-click",
              !name.contains("finger") else { return nil }
        if name.hasSuffix("-corner-click") {
            corner = (name.contains("right"), name.hasPrefix("top"))
            return
        }
        let words = name.replacingOccurrences(of: "-click", with: "").split(separator: "-").map(String.init)
        switch words.first {
        case "left": edge = .left
        case "right": edge = .right
        case "top": edge = .top
        case "bottom": edge = .bottom
        default: return nil
        }
        // "left-edge-top-half" → ["left", "edge", "top", "half"]
        guard words.count == 4 else { return }
        switch (words[2], words[3]) {
        case ("top", "half"): part = .half(.top)
        case ("bottom", "half"): part = .half(.bottom)
        case ("left", "half"): part = .half(.left)
        case ("right", "half"): part = .half(.right)
        case ("top", "third"): part = .third(.top)
        case ("middle", "third"): part = .third(.middle)
        case ("bottom", "third"): part = .third(.bottom)
        case ("left", "third"): part = .third(.left)
        case ("right", "third"): part = .third(.right)
        default: break
        }
    }
}
