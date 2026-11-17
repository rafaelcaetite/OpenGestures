import AppKit
import OpenGesturesCore
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = ConfigurationStore()
    private let applications = FrontmostApplication()
    private let lastEvent = LastEvent()
    private let loginItem = LoginItem(label: Bundle.main.bundleIdentifier ?? Log.subsystem)

    private lazy var engine = GestureEngine(configuration: Configuration(), applications: applications)
    private lazy var manager = MultitouchManager { [engine] device, contacts, timestamp in
        engine.handleFrame(device: device, contacts: contacts, timestamp: timestamp)
    }
    private lazy var clickInterceptor = ClickInterceptor(engine: engine)
    private lazy var editor = GestureEditorWindow(store: store)

    private var configuration = Configuration()
    private var configurationError: String?
    private var watcher: ConfigurationWatcher?
    private var statusItem: NSStatusItem?
    private var isEnabled = true
    private var restartWorkItem: DispatchWorkItem?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
               .contains(where: { $0.processIdentifier != getpid() }) {
            Log.app.info("Another instance is already running")
            NSApp.terminate(nil)
            return
        }

        NSApp.mainMenu = Self.makeMainMenu()
        KeyboardLayout.shared.startTracking()
        applications.startTracking()

        do {
            if try store.createIfMissing() {
                Log.configuration.info("Created \(self.store.fileURL.path, privacy: .public)")
            }
        } catch {
            Log.configuration.error("Could not create the configuration file: \(error.localizedDescription, privacy: .public)")
        }

        engine.onEvent = { [lastEvent] event in lastEvent.record(event) }
        reloadConfiguration()
        watcher = ConfigurationWatcher(url: store.fileURL) { [weak self] in
            self?.reloadConfiguration()
        }

        if !Accessibility.isTrusted {
            Accessibility.requestTrust()
        }
        observeSystem()
        enableLoginItemOnFirstLaunch()
        startInput()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopInput()
    }

    /// Opening the app again while it runs shows the gesture editor.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        editor.show()
        return false
    }

    /// An agent app shows no menu bar, but its main menu still routes key
    /// equivalents, which text fields need for copy and paste.
    private static func makeMainMenu() -> NSMenu {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let menu = NSMenu()
        let item = NSMenuItem()
        item.submenu = edit
        menu.addItem(item)
        return menu
    }

    private func observeSystem() {
        // Multitouch devices stop delivering frames across sleep.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRestart(after: 1.0) }
        }
        manager.watchDevices { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.scheduleRestart(after: 0.5) }
            }
        }
        // Posted whenever the Accessibility permission list changes.
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated {
                    self?.updateClickInterceptor()
                    self?.updateStatusItem()
                }
            }
        }
    }

    // MARK: - Input

    private func startInput() {
        guard isEnabled else { return }
        manager.start()
        updateClickInterceptor()
    }

    private func stopInput() {
        manager.stop()
        clickInterceptor.stop()
    }

    private func scheduleRestart(after delay: TimeInterval) {
        guard isEnabled else { return }
        restartWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isEnabled else { return }
                self.manager.restart()
            }
        }
        restartWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func updateClickInterceptor() {
        guard isEnabled, configuration.hasClickBindings else {
            clickInterceptor.stop()
            return
        }
        if !clickInterceptor.start() {
            Log.input.notice("Click gestures need Accessibility permission")
        }
    }

    // MARK: - Configuration

    private func reloadConfiguration() {
        do {
            let loaded = try store.load()
            configuration = loaded
            configurationError = nil
            engine.update(loaded)
            Log.configuration.info("Loaded \(loaded.bindingCount) binding(s)")
            for warning in loaded.warnings {
                Log.configuration.notice("\(warning, privacy: .public)")
            }
        } catch {
            // Keep running with the last good configuration.
            configurationError = "\(error)"
            Log.configuration.error("\(String(describing: error), privacy: .public)")
        }
        updateClickInterceptor()
        updateStatusItem()
        editor.configurationDidChange()
    }

    // MARK: - Status item

    private func updateStatusItem() {
        guard configuration.settings.showMenuBarIcon else {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
            statusItem = nil
            return
        }
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
        }
        let symbol: String
        if configurationError != nil || !Accessibility.isTrusted {
            symbol = "exclamationmark.triangle"
        } else {
            symbol = isEnabled ? "hand.draw" : "hand.raised.slash"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "OpenGestures")
        image?.isTemplate = true
        statusItem?.button?.image = image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(disabled("OpenGestures \(Version.current)"))

        if !Accessibility.isTrusted {
            menu.addItem(item(String(localized: "Grant Accessibility Permission…"), #selector(openAccessibilitySettings)))
        }
        if let configurationError {
            menu.addItem(disabled(String(localized: "Configuration error: \(configurationError)")))
        }
        if !configuration.warnings.isEmpty {
            let warnings = NSMenuItem(title: String(localized: "Warnings: \(configuration.warnings.count)"), action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            configuration.warnings.forEach { submenu.addItem(disabled($0)) }
            warnings.submenu = submenu
            menu.addItem(warnings)
        }
        if let last = lastEvent.description {
            menu.addItem(disabled(String(localized: "Last gesture: \(last)")))
        }

        menu.addItem(.separator())
        let enabled = item(String(localized: "Enabled"), #selector(toggleEnabled))
        enabled.state = isEnabled ? .on : .off
        menu.addItem(enabled)
        menu.addItem(item(String(localized: "Edit Gestures…"), #selector(showEditor), key: ","))

        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Open Configuration File"), #selector(editConfiguration)))
        menu.addItem(item(String(localized: "Show Configuration in Finder"), #selector(revealConfiguration)))
        menu.addItem(item(String(localized: "Reload Configuration"), #selector(reload)))

        menu.addItem(.separator())
        let login = item(String(localized: "Open at Login"), #selector(toggleLoginItem))
        login.state = loginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item(String(localized: "Quit OpenGestures"), #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Menu actions

    @objc private func showEditor() {
        editor.show()
    }

    @objc private func toggleEnabled() {
        isEnabled.toggle()
        if isEnabled {
            startInput()
        } else {
            stopInput()
        }
        updateStatusItem()
    }

    @objc private func editConfiguration() {
        let workspace = NSWorkspace.shared
        if let editor = workspace.urlForApplication(toOpen: .plainText) {
            workspace.open([store.fileURL], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
        } else {
            workspace.open(store.fileURL)
        }
    }

    @objc private func revealConfiguration() {
        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
    }

    @objc private func reload() {
        reloadConfiguration()
    }

    @objc private func openAccessibilitySettings() {
        Accessibility.requestTrust()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLoginItem() {
        do {
            if loginItem.isEnabled {
                try loginItem.disable()
            } else if let executable = Bundle.main.executablePath {
                try loginItem.enable(executable: executable)
            }
        } catch {
            Log.app.error("Could not change the login item: \(error.localizedDescription, privacy: .public)")
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    /// Installs the login item once, and only for an installed copy, so a
    /// build run from the source tree never registers itself.
    private func enableLoginItemOnFirstLaunch() {
        let key = "LoginItemConfigured"
        guard !UserDefaults.standard.bool(forKey: key), let executable = Bundle.main.executablePath else { return }
        let path = Bundle.main.bundlePath
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix("/Applications/") || path.hasPrefix(home + "/Applications/") else { return }
        do {
            try loginItem.enable(executable: executable)
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            Log.app.error("Could not install the login item: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// The most recent gesture, written on the multitouch thread and read when
/// the menu opens.
private final class LastEvent: @unchecked Sendable {
    private let lock = UnfairLock()
    private var value: String?

    func record(_ event: GestureEngine.Event) {
        var text = event.gesture.rawValue
        if let direction = event.direction {
            text += " \(direction.rawValue)"
        }
        if event.binding == nil {
            text += " (not bound)"
        }
        lock.withLock { value = text }
    }

    var description: String? {
        lock.withLock { value }
    }
}
