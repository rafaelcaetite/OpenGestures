import Foundation

public struct BindingError: Error, Equatable, CustomStringConvertible {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

/// One thing a binding does. A binding runs its steps in order.
public enum ActionStep: Hashable, Sendable {
    case keystroke(Keystroke)
    case builtIn(BuiltInAction)
    /// Buttons are numbered from 1 (primary); 3 is the middle button.
    case mouseButton(Int)
    /// A URL that may contain `{{placeholders}}`.
    case openURL(String)
    case runScript(String)
    /// Titles from the menu bar down, such as ["File", "New Window"].
    case menuCommand([String])
    case openApplication(String)
    case typeText(String)
    case playSound(String)
    case speak(String)
    case wait(milliseconds: Int)
}

/// What a discrete gesture does.
public struct ActionBinding: Hashable, Sendable {
    public var steps: [ActionStep]
    /// Overrides the general haptic-feedback setting for this binding.
    public var haptic: Bool?
    /// The binding as written in the configuration, for display.
    public var source: String

    public init(steps: [ActionStep], haptic: Bool? = nil, source: String) {
        self.steps = steps
        self.haptic = haptic
        self.source = source
    }
}

/// What a continuous gesture does for each step of movement.
public struct SlideBinding: Hashable, Sendable {
    public var actions: [Direction: ActionBinding]
    /// Millimetres between steps; the general slide-step setting when nil.
    public var step: Double?
    /// Steps between two haptic taps. Fine-grained presets tap once per
    /// whole step instead of on every quarter.
    public var detent: Int
    public var haptic: Bool?
    public var source: String

    public init(
        actions: [Direction: ActionBinding],
        step: Double? = nil,
        detent: Int = 1,
        haptic: Bool? = nil,
        source: String
    ) {
        self.actions = actions
        self.step = step
        self.detent = max(1, detent)
        self.haptic = haptic
        self.source = source
    }
}

extension SlideBinding {
    /// Accepted step distances, in millimetres.
    public static let stepRange: ClosedRange<Double> = 0.2...100
}

public enum Binding: Hashable, Sendable {
    case action(ActionBinding)
    case slide(SlideBinding)

    public var source: String {
        switch self {
        case .action(let binding): binding.source
        case .slide(let binding): binding.source
        }
    }
}

/// Ready-made slide bindings.
public enum SlidePreset: String, CaseIterable, Sendable {
    case volume
    case brightness
    case keyboardBacklight = "keyboard-backlight"
    case zoom
    case tabs
    case history
    case undo
    case spaces
    case tracks

    public var actions: [Direction: String] {
        switch self {
        case .volume: [.up: "volume-up-fine", .down: "volume-down-fine"]
        case .brightness: [.up: "brightness-up-fine", .down: "brightness-down-fine"]
        case .keyboardBacklight: [.up: "keyboard-backlight-up-fine", .down: "keyboard-backlight-down-fine"]
        case .zoom: [.up: "cmd+=", .down: "cmd+-"]
        case .tabs: [.right: "next-tab", .left: "previous-tab"]
        case .history: [.left: "cmd+[", .right: "cmd+]"]
        case .undo: [.left: "cmd+z", .right: "cmd+shift+z"]
        case .spaces: [.left: "ctrl+left", .right: "ctrl+right"]
        case .tracks: [.left: "previous-track", .right: "next-track"]
        }
    }

    /// Step distance in millimetres, when the preset needs its own instead
    /// of the general setting.
    ///
    /// Level presets move in quarter steps, 64 from bottom to top, so 0.8 mm
    /// covers the whole range in about 5 cm: one stroke of the hand.
    public var step: Double? {
        switch self {
        case .volume, .brightness, .keyboardBacklight: 0.8
        case .zoom: 8
        case .undo: 10
        case .tabs: 15
        case .history, .spaces, .tracks: 25
        }
    }

    /// Quarter-step presets tap the trackpad once per whole step.
    public var detent: Int {
        switch self {
        case .volume, .brightness, .keyboardBacklight: 4
        default: 1
        }
    }

    /// Steps from the lowest to the highest level, for presets that set a level.
    public var levels: Int? {
        switch self {
        case .volume, .brightness, .keyboardBacklight: 64
        default: nil
        }
    }

    public var summary: String {
        switch self {
        case .volume: "Up and down change the volume"
        case .brightness: "Up and down change display brightness"
        case .keyboardBacklight: "Up and down change keyboard backlight"
        case .zoom: "Up zooms in (⌘=), down zooms out (⌘-)"
        case .tabs: "Left and right move between tabs"
        case .history: "Left goes back (⌘[), right goes forward (⌘])"
        case .undo: "Left undoes (⌘Z), right redoes (⌘⇧Z)"
        case .spaces: "Left and right move between desktops"
        case .tracks: "Left and right skip between tracks"
        }
    }
}
