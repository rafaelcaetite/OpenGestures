import AppKit
import OpenGesturesCore
import SwiftUI

/// A field that records the next key combination pressed while it is active.
/// Escape cancels.
struct ShortcutRecorder: View {
    let shortcut: String?
    var startsRecording = false
    let onRecord: (String) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Text(label)
                    .font(isRecording || display == nil ? .body : .body.monospaced())
                    .foregroundStyle(isRecording ? Color.accentColor : display == nil ? .secondary : .primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(width: 200, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isRecording ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear { if startsRecording { start() } }
        .onDisappear(perform: stop)
    }

    private var display: String? {
        shortcut.flatMap { try? Keystroke.parse($0) }?.description
    }

    private var label: String {
        if isRecording { return String(localized: "Press the keys…") }
        return display ?? String(localized: "Record shortcut")
    }

    private func toggle() {
        isRecording ? stop() : start()
    }

    private func start() {
        guard monitor == nil else { return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { handle(event) }
            return nil
        }
    }

    private func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53, flags.subtracting(.function).isEmpty {
            stop()
            return
        }
        if let keys = Self.keystroke(for: event) {
            onRecord(keys)
        }
        stop()
    }

    /// The configuration spelling of the key combination in `event`.
    static func keystroke(for event: NSEvent) -> String? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var parts: [String] = []
        if flags.contains(.control) { parts.append("ctrl") }
        if flags.contains(.option) { parts.append("opt") }
        if flags.contains(.shift) { parts.append("shift") }
        if flags.contains(.command) { parts.append("cmd") }

        if let name = Keystroke.name(forKeyCode: event.keyCode) {
            parts.append(name)
        } else if let character = event.characters(byApplyingModifiers: [])?.lowercased(),
                  character.count == 1, !character.unicodeScalars.contains(where: { $0.value < 0x20 }) {
            parts.append(character)
        } else {
            return nil
        }
        let keys = parts.joined(separator: "+")
        return (try? Keystroke.parse(keys)) == nil ? nil : keys
    }
}
