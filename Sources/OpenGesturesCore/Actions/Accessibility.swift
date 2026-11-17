import ApplicationServices
import Foundation

public enum Accessibility {
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that leads to Privacy & Security settings.
    public static func requestTrust() {
        // The value of kAXTrustedCheckOptionPrompt, which Swift 6 treats as
        // shared mutable state.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func minimizeFocusedWindow() {
        guard let window = focusedWindow() else { return }
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
    }

    static func zoomFocusedWindow() {
        guard let window = focusedWindow(), let button: AXUIElement = attribute(window, kAXZoomButtonAttribute) else { return }
        AXUIElementPerformAction(button, kAXPressAction as CFString)
    }

    static func toggleFullScreen() {
        guard let window = focusedWindow() else { return }
        let key = "AXFullScreen" as CFString
        let isFullScreen: Bool = attribute(window, key as String) ?? false
        AXUIElementSetAttributeValue(window, key, (!isFullScreen) as CFBoolean)
    }

    /// Presses a menu item in the frontmost application, matching titles
    /// without regard to case or a trailing ellipsis.
    @discardableResult
    static func pressMenuItem(_ path: [String], processIdentifier: pid_t) -> Bool {
        let application = AXUIElementCreateApplication(processIdentifier)
        guard var container: AXUIElement = attribute(application, kAXMenuBarAttribute) else { return false }

        for (index, title) in path.enumerated() {
            let wanted = normalize(title)
            let children: [AXUIElement] = attribute(container, kAXChildrenAttribute) ?? []
            guard let item = children.first(where: { child in
                let childTitle: String? = attribute(child, kAXTitleAttribute)
                return childTitle.map(normalize) == wanted
            }) else {
                Log.actions.error("Menu item \"\(title, privacy: .public)\" not found")
                return false
            }
            if index == path.count - 1 {
                return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
            }
            let submenus: [AXUIElement] = attribute(item, kAXChildrenAttribute) ?? []
            guard let submenu = submenus.first else { return false }
            container = submenu
        }
        return false
    }

    private static func focusedWindow() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        guard let application: AXUIElement = attribute(system, kAXFocusedApplicationAttribute) else { return nil }
        return attribute(application, kAXFocusedWindowAttribute)
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private static func normalize(_ title: String) -> String {
        title.replacingOccurrences(of: "…", with: "")
            .replacingOccurrences(of: "...", with: "")
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
    }
}
