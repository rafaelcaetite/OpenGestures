import Foundation

/// A discrete binding as the gesture editor shows it.
///
/// The common shapes are decoded into fields the editor can change. Anything
/// else (sequences, scripts, menu commands, expanded tables) stays `custom`
/// and is only ever rewritten when the person picks another action.
public enum ActionDraft: Hashable, Sendable {
    case none
    case builtIn(BuiltInAction)
    case shortcut(String)
    /// An application name or bundle identifier.
    case application(String)
    case url(String)
    case text(String)
    /// The value as TOML, kept as written.
    case custom(String)

    public init(_ value: TOMLValue?) {
        guard let value else {
            self = .none
            return
        }
        guard case .string(let raw) = value else {
            self = .custom(value.tomlText)
            return
        }
        let text = raw.trimmingCharacters(in: .whitespaces)
        if let action = BuiltInAction(rawValue: text) {
            self = .builtIn(action)
        } else if let name = text.removingPrefix("app:"), !name.isEmpty {
            self = .application(name)
        } else if let address = text.removingPrefix("url:"), !address.isEmpty {
            self = .url(address)
        } else if let typed = text.removingPrefix("text:") {
            self = .text(typed)
        } else if Self.otherPrefixes.contains(where: text.hasPrefix) {
            self = .custom(value.tomlText)
        } else if text.contains("://") {
            self = .url(text)
        } else if (try? Keystroke.parse(text)) != nil {
            self = .shortcut(text)
        } else {
            self = .custom(value.tomlText)
        }
    }

    private static let otherPrefixes = ["script:", "menu:", "sound:", "say:", "wait:", "mouse-"]

    /// The value to write, or nil to remove the binding.
    public var tomlText: String? {
        switch self {
        case .none: nil
        case .builtIn(let action): TOMLValue.quoted(action.rawValue)
        case .shortcut(let keys): TOMLValue.quoted(keys)
        case .application(let name): TOMLValue.quoted("app:" + name)
        case .url(let address): TOMLValue.quoted(address.contains("://") ? address : "url:" + address)
        case .text(let typed): TOMLValue.quoted("text:" + typed)
        case .custom(let toml): toml
        }
    }
}

/// A continuous binding as the gesture editor shows it.
public enum SlideDraft: Hashable, Sendable {
    case none
    /// A preset, with the step written in the file if it has one.
    case preset(SlidePreset, step: Double?)
    case custom(String)

    public init(_ value: TOMLValue?) {
        guard let value else {
            self = .none
            return
        }
        switch value {
        case .string(let name):
            if let preset = SlidePreset(rawValue: name) {
                self = .preset(preset, step: nil)
                return
            }
        case .table(let table) where Set(table.keys).isSubset(of: ["preset", "step"]):
            if case .string(let name)? = table["preset"], let preset = SlidePreset(rawValue: name) {
                self = .preset(preset, step: table["step"]?.doubleValue)
                return
            }
        default:
            break
        }
        self = .custom(value.tomlText)
    }

    /// The value to write, or nil to remove the binding. A preset at its
    /// own step is written as just its name.
    public var tomlText: String? {
        switch self {
        case .none:
            return nil
        case .preset(let preset, let step):
            guard let step, step != preset.step else { return TOMLValue.quoted(preset.rawValue) }
            return "{ preset = \(TOMLValue.quoted(preset.rawValue)), step = \(TOMLValue.number(step)) }"
        case .custom(let toml):
            return toml
        }
    }
}
