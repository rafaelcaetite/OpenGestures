import Carbon.HIToolbox
import Foundation
import os

/// Maps characters to the key codes that type them on the active layout.
///
/// Text Input Sources must be queried on the main thread, so the map is built
/// there, at start-up and whenever the input source changes, and read from
/// any thread afterwards.
public final class KeyboardLayout: Sendable {
    public static let shared = KeyboardLayout()

    struct KeyPosition: Sendable {
        var code: UInt16
        var shift: Bool
    }

    private let map = OSAllocatedUnfairLock<[String: KeyPosition]?>(initialState: nil)

    private init() {}

    /// Builds the map for the current layout and keeps it current. Call once
    /// from the main thread.
    @MainActor
    public func startTracking() {
        rebuild()
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { KeyboardLayout.shared.rebuild() }
        }
    }

    @MainActor
    private func rebuild() {
        let current = Self.currentLayoutMap()
        map.withLock { $0 = current }
    }

    func position(of character: String) -> KeyPosition? {
        if let position = map.withLock({ $0?[character] }) {
            return position
        }
        return Self.ansi[character]
    }

    @MainActor
    private static func currentLayoutMap() -> [String: KeyPosition]? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        let keyboardType = UInt32(LMGetKbdType())

        return data.withUnsafeBytes { buffer -> [String: KeyPosition]? in
            guard let base = buffer.baseAddress else { return nil }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            var result: [String: KeyPosition] = [:]
            // Unshifted characters first, so a character reachable both ways
            // is typed without Shift.
            for shift in [false, true] {
                let modifierState = shift ? UInt32(shiftKey >> 8) & 0xFF : 0
                for code in UInt16(0)..<128 {
                    var deadKeyState: UInt32 = 0
                    var length = 0
                    var characters = [UniChar](repeating: 0, count: 4)
                    let status = UCKeyTranslate(
                        layout, code, UInt16(kUCKeyActionDisplay), modifierState, keyboardType,
                        OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, 4, &length, &characters
                    )
                    guard status == noErr, length > 0 else { continue }
                    let string = String(utf16CodeUnits: characters, count: length).lowercased()
                    if result[string] == nil {
                        result[string] = KeyPosition(code: code, shift: shift)
                    }
                }
            }
            return result
        }
    }

    /// US ANSI positions, used when no layout map is available.
    static let ansi: [String: KeyPosition] = {
        let codes: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
            "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
            "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
            "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
            "z": kVK_ANSI_Z, "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
            "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8,
            "9": kVK_ANSI_9, "=": kVK_ANSI_Equal, "-": kVK_ANSI_Minus, "[": kVK_ANSI_LeftBracket,
            "]": kVK_ANSI_RightBracket, "'": kVK_ANSI_Quote, ";": kVK_ANSI_Semicolon,
            "\\": kVK_ANSI_Backslash, ",": kVK_ANSI_Comma, "/": kVK_ANSI_Slash, ".": kVK_ANSI_Period,
            "`": kVK_ANSI_Grave,
        ]
        var positions = codes.mapValues { KeyPosition(code: UInt16($0), shift: false) }
        positions["+"] = KeyPosition(code: UInt16(kVK_ANSI_Equal), shift: true)
        return positions
    }()
}
