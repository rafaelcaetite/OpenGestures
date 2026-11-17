import Carbon.HIToolbox
import CoreGraphics

public struct Modifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let control = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let shift = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)
    public static let function = Modifiers(rawValue: 1 << 4)

    /// Modifier keys in the order they are pressed.
    static let ordered: [(Modifiers, keyCode: UInt16, flag: CGEventFlags, symbol: String)] = [
        (.control, UInt16(kVK_Control), .maskControl, "⌃"),
        (.option, UInt16(kVK_Option), .maskAlternate, "⌥"),
        (.shift, UInt16(kVK_Shift), .maskShift, "⇧"),
        (.command, UInt16(kVK_Command), .maskCommand, "⌘"),
        (.function, UInt16(kVK_Function), .maskSecondaryFn, "fn "),
    ]

    var flags: CGEventFlags {
        Self.ordered.reduce(into: CGEventFlags()) { result, entry in
            if contains(entry.0) { result.insert(entry.flag) }
        }
    }

    static let names: [String: Modifiers] = [
        "cmd": .command, "command": .command, "⌘": .command,
        "shift": .shift, "⇧": .shift,
        "opt": .option, "option": .option, "alt": .option, "⌥": .option,
        "ctrl": .control, "control": .control, "⌃": .control,
        "fn": .function,
    ]
}

/// A key combination such as `cmd+shift+4`.
///
/// Named keys (`return`, `f5`, `left`) map to fixed key codes. Single
/// characters are resolved against the active keyboard layout when the
/// keystroke is sent, so `cmd+z` presses the key labelled Z on any layout.
public struct Keystroke: Hashable, Sendable, CustomStringConvertible {
    public enum Key: Hashable, Sendable {
        case code(UInt16)
        case character(String)
    }

    public var key: Key
    public var modifiers: Modifiers

    public init(key: Key, modifiers: Modifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    public static func parse(_ text: String) throws(BindingError) -> Keystroke {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw BindingError("empty keystroke") }

        let keyToken: String
        let modifierTokens: [Substring]
        if trimmed == "+" {
            keyToken = "+"
            modifierTokens = []
        } else if trimmed.hasSuffix("++") {
            keyToken = "+"
            modifierTokens = trimmed.dropLast(2).split(separator: "+", omittingEmptySubsequences: false)
        } else {
            let parts = trimmed.split(separator: "+", omittingEmptySubsequences: false)
            keyToken = String(parts[parts.count - 1])
            modifierTokens = Array(parts.dropLast())
        }

        var modifiers: Modifiers = []
        for token in modifierTokens {
            let name = token.trimmingCharacters(in: .whitespaces).lowercased()
            guard let modifier = Modifiers.names[name] else {
                throw BindingError("unknown modifier \"\(token)\" in \"\(text)\"")
            }
            modifiers.insert(modifier)
        }

        let name = keyToken.trimmingCharacters(in: .whitespaces)
        let lowered = name.lowercased()
        if let code = namedKeys[lowered] {
            return Keystroke(key: .code(code), modifiers: modifiers)
        }
        if let character = characterNames[lowered] {
            return Keystroke(key: .character(character), modifiers: modifiers)
        }
        guard name.count == 1 else {
            throw BindingError("unknown key \"\(name)\" in \"\(text)\"")
        }
        if name != lowered, name.first?.isLetter == true {
            modifiers.insert(.shift)
        }
        return Keystroke(key: .character(lowered), modifiers: modifiers)
    }

    public var description: String {
        let prefix = Modifiers.ordered.filter { modifiers.contains($0.0) }.map(\.symbol).joined()
        switch key {
        case .code(let code):
            let name = Self.namedKeys.first { $0.value == code }?.key ?? "key\(code)"
            return prefix + name
        case .character(let character):
            return prefix + character.uppercased()
        }
    }

    static let namedKeys: [String: UInt16] = {
        var keys: [String: UInt16] = [
            "return": UInt16(kVK_Return),
            "enter": UInt16(kVK_Return),
            "tab": UInt16(kVK_Tab),
            "space": UInt16(kVK_Space),
            "delete": UInt16(kVK_Delete),
            "backspace": UInt16(kVK_Delete),
            "forward-delete": UInt16(kVK_ForwardDelete),
            "escape": UInt16(kVK_Escape),
            "esc": UInt16(kVK_Escape),
            "up": UInt16(kVK_UpArrow),
            "down": UInt16(kVK_DownArrow),
            "left": UInt16(kVK_LeftArrow),
            "right": UInt16(kVK_RightArrow),
            "home": UInt16(kVK_Home),
            "end": UInt16(kVK_End),
            "page-up": UInt16(kVK_PageUp),
            "page-down": UInt16(kVK_PageDown),
            "help": UInt16(kVK_Help),
            "keypad-enter": UInt16(kVK_ANSI_KeypadEnter),
        ]
        let functionKeys = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
        ]
        for (offset, code) in functionKeys.enumerated() {
            keys["f\(offset + 1)"] = UInt16(code)
        }
        return keys
    }()

    static let characterNames: [String: String] = [
        "plus": "+", "minus": "-", "equal": "=", "equals": "=",
        "comma": ",", "period": ".", "slash": "/", "backslash": "\\",
        "semicolon": ";", "quote": "'", "backtick": "`", "grave": "`",
        "left-bracket": "[", "right-bracket": "]",
    ]
}
