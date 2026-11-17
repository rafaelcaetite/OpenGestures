import Foundation

/// Actions that need more than a keystroke to perform.
public enum BuiltInAction: String, CaseIterable, Sendable {
    case missionControl = "mission-control"
    case appExpose = "app-expose"
    case showDesktop = "show-desktop"
    case launchpad
    case previousApp = "previous-app"

    case nextTab = "next-tab"
    case previousTab = "previous-tab"
    case newTab = "new-tab"
    case closeTab = "close-tab"
    case reopenTab = "reopen-tab"

    case maximize
    case fullScreen = "full-screen"
    case minimize

    case playPause = "play-pause"
    case nextTrack = "next-track"
    case previousTrack = "previous-track"
    case mute
    case volumeUp = "volume-up"
    case volumeDown = "volume-down"
    case brightnessUp = "brightness-up"
    case brightnessDown = "brightness-down"
    case keyboardBacklightUp = "keyboard-backlight-up"
    case keyboardBacklightDown = "keyboard-backlight-down"
    case volumeUpFine = "volume-up-fine"
    case volumeDownFine = "volume-down-fine"
    case brightnessUpFine = "brightness-up-fine"
    case brightnessDownFine = "brightness-down-fine"
    case keyboardBacklightUpFine = "keyboard-backlight-up-fine"
    case keyboardBacklightDownFine = "keyboard-backlight-down-fine"

    case middleClick = "middle-click"

    public var summary: String {
        switch self {
        case .missionControl: "Open Mission Control"
        case .appExpose: "Show all windows of the frontmost application"
        case .showDesktop: "Show the desktop"
        case .launchpad: "Open Launchpad or Apps"
        case .previousApp: "Switch to the previously used application (⌘⇥)"
        case .nextTab: "Next tab (⌃⇥)"
        case .previousTab: "Previous tab (⌃⇧⇥)"
        case .newTab: "New tab (⌘T)"
        case .closeTab: "Close tab or window (⌘W)"
        case .reopenTab: "Reopen the last closed tab (⌘⇧T)"
        case .maximize: "Zoom the focused window, like clicking its green button with Option"
        case .fullScreen: "Toggle full screen for the focused window"
        case .minimize: "Minimize the focused window"
        case .playPause: "Play or pause media"
        case .nextTrack: "Next track"
        case .previousTrack: "Previous track"
        case .mute: "Mute or unmute"
        case .volumeUp: "Raise the volume one step"
        case .volumeDown: "Lower the volume one step"
        case .brightnessUp: "Raise display brightness"
        case .brightnessDown: "Lower display brightness"
        case .keyboardBacklightUp: "Raise keyboard backlight"
        case .keyboardBacklightDown: "Lower keyboard backlight"
        case .volumeUpFine: "Raise the volume a quarter step"
        case .volumeDownFine: "Lower the volume a quarter step"
        case .brightnessUpFine: "Raise display brightness a quarter step"
        case .brightnessDownFine: "Lower display brightness a quarter step"
        case .keyboardBacklightUpFine: "Raise keyboard backlight a quarter step"
        case .keyboardBacklightDownFine: "Lower keyboard backlight a quarter step"
        case .middleClick: "Middle click at the pointer (same as mouse-3)"
        }
    }
}
