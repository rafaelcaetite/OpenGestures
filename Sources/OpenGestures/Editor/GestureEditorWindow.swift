import AppKit
import OpenGesturesCore
import SwiftUI

/// Owns the editor window while it is open. The window, its view tree and
/// its model are released when it closes, so an idle OpenGestures carries
/// none of SwiftUI's memory.
@MainActor
final class GestureEditorWindow: NSObject, NSWindowDelegate {
    private let store: ConfigurationStore
    private var window: NSWindow?
    private var model: GestureEditorModel?

    init(store: ConfigurationStore) {
        self.store = store
    }

    func show() {
        if window == nil {
            let model = GestureEditorModel(store: store)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = String(localized: "OpenGestures")
            window.contentViewController = NSHostingController(rootView: GestureEditorView(model: model))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setFrameAutosaveName("GestureEditor")
            if !window.setFrameUsingName("GestureEditor") {
                window.center()
            }
            self.window = window
            self.model = model
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Picks up changes made to the file outside the editor.
    func configurationDidChange() {
        model?.reload()
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil
        window = nil
        model = nil
    }
}
