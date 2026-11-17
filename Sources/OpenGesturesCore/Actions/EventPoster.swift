import AppKit
import CoreGraphics
import IOKit.hidsystem

/// Synthesizes keyboard, media-key and mouse events.
enum EventPoster {
    /// Presses or releases modifier keys on their own, as flag changes, which
    /// is how the system sees a real modifier key. A key combination posted
    /// while they are down passes them as `holding`.
    static func setModifiers(_ modifiers: Modifiers, down: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        var flags = down ? CGEventFlags() : modifiers.flags
        let pressed = Modifiers.ordered.filter { modifiers.contains($0.0) }
        for modifier in down ? pressed : pressed.reversed() {
            if down { flags.insert(modifier.flag) } else { flags.remove(modifier.flag) }
            let event = CGEvent(keyboardEventSource: source, virtualKey: modifier.keyCode, keyDown: down)
            event?.type = .flagsChanged
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    static func post(_ keystroke: Keystroke, holding held: Modifiers = []) {
        var modifiers = keystroke.modifiers
        let code: UInt16
        switch keystroke.key {
        case .code(let value):
            code = value
        case .character(let character):
            guard let position = KeyboardLayout.shared.position(of: character) else {
                Log.actions.error("No key types \"\(character, privacy: .public)\" on the current keyboard layout")
                return
            }
            code = position.code
            if position.shift { modifiers.insert(.shift) }
        }

        let source = CGEventSource(stateID: .hidSystemState)
        // Modifiers already held stay down and are not pressed again.
        let pressed = Modifiers.ordered.filter { modifiers.contains($0.0) && !held.contains($0.0) }
        var flags = held.flags

        // Modifiers are pressed as separate key events before the key itself.
        // Some hotkey listeners ignore a key event that merely carries flags.
        for modifier in pressed {
            flags.insert(modifier.flag)
            post(source, modifier.keyCode, down: true, flags: flags)
        }
        post(source, code, down: true, flags: flags)
        post(source, code, down: false, flags: flags)
        for modifier in pressed.reversed() {
            flags.remove(modifier.flag)
            post(source, modifier.keyCode, down: false, flags: flags)
        }
    }

    private static func post(_ source: CGEventSource?, _ code: UInt16, down: Bool, flags: CGEventFlags) {
        let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }

    /// Media and brightness keys travel as system-defined events, which is
    /// also what makes macOS show its volume and brightness overlays.
    ///
    /// A `fine` key carries Option and Shift, which macOS treats as a quarter
    /// of a step, the same as pressing those modifiers with the real key.
    static func postSystemKey(_ key: Int32, fine: Bool = false) {
        let modifiers: NSEvent.ModifierFlags = fine ? [.option, .shift] : []
        for down in [true, false] {
            let state = down ? 0xA : 0xB
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)).union(modifiers),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: Int((key << 16) | Int32(state << 8)),
                data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    /// Clicks mouse button `number` (1 is primary, 3 is middle) at the pointer.
    static func click(button number: Int) {
        let location = CGEvent(source: nil)?.location ?? .zero
        let index = Int64(number - 1)
        let (downType, upType): (CGEventType, CGEventType) = switch number {
        case 1: (.leftMouseDown, .leftMouseUp)
        case 2: (.rightMouseDown, .rightMouseUp)
        default: (.otherMouseDown, .otherMouseUp)
        }
        let button = CGMouseButton(rawValue: UInt32(min(index, 31))) ?? .center
        for type in [downType, upType] {
            let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location, mouseButton: button)
            event?.setIntegerValueField(.mouseEventButtonNumber, value: index)
            event?.post(tap: .cghidEventTap)
        }
    }

    static func type(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        let units = Array(text.utf16)
        var start = 0
        // Events carry at most 20 UTF-16 code units each.
        while start < units.count {
            let end = min(start + 20, units.count)
            var chunk = Array(units[start..<end])
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
                event?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                event?.post(tap: .cghidEventTap)
            }
            start = end
        }
    }
}
