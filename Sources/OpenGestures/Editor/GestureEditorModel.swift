import AppKit
import OpenGesturesCore

/// The state behind the gesture editor: the configuration file as text, its
/// parsed form, and edits written back one key at a time.
///
/// Only the global `[TRACKPAD]` and `[MOUSE]` tables are edited here.
/// Application-specific tables and `fn+` bindings stay in the file, where the
/// editor leaves them untouched.
@MainActor
final class GestureEditorModel: ObservableObject {
    @Published var device: DeviceKind = .trackpad {
        didSet { if device != oldValue { selection = firstGesture } }
    }
    @Published var search = ""
    @Published var selection: Gesture?
    @Published private(set) var settings = Settings()
    /// Why the file cannot be edited right now, if it cannot.
    @Published private(set) var problem: String?
    @Published private(set) var writeError: String?

    let store: ConfigurationStore
    private var document = ConfigurationDocument(text: "")
    private var tables: [DeviceKind: TOMLTable] = [:]
    private var configuration = Configuration()

    init(store: ConfigurationStore) {
        self.store = store
        reload()
        selection = firstGesture
    }

    // MARK: - Reading

    func reload() {
        let text: String
        do {
            text = try String(contentsOf: store.fileURL, encoding: .utf8)
        } catch {
            problem = error.localizedDescription
            return
        }
        apply(text)
    }

    private func apply(_ text: String) {
        document = ConfigurationDocument(text: text)
        do {
            let root = try TOMLParser.parse(text)
            var tables: [DeviceKind: TOMLTable] = [:]
            for device in DeviceKind.allCases {
                if case .table(let table)? = root[device.sectionName] {
                    tables[device] = table
                }
            }
            self.tables = tables
            configuration = try ConfigurationParser.parse(text)
            settings = configuration.settings
            problem = nil
        } catch {
            problem = "\(error)"
        }
    }

    var isEditable: Bool { problem == nil }

    func gestures(in category: Gesture.Category) -> [Gesture] {
        Gesture.allCases.filter { gesture in
            gesture.category == category
                && gesture.supportedDevices.contains(device)
                && !isBound(gesture)
                && matchesSearch(gesture)
        }
    }

    var boundGestures: [Gesture] {
        Gesture.allCases.filter { $0.supportedDevices.contains(device) && isBound($0) && matchesSearch($0) }
    }

    private var firstGesture: Gesture? {
        boundGestures.first ?? Gesture.allCases.first { $0.supportedDevices.contains(device) }
    }

    private func matchesSearch(_ gesture: Gesture) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return Titles.gesture(gesture).localizedCaseInsensitiveContains(query)
            || gesture.rawValue.localizedCaseInsensitiveContains(query)
    }

    private func value(for gesture: Gesture) -> TOMLValue? {
        guard let value = tables[device]?[gesture.rawValue] else { return nil }
        if case .table(let table) = value, !table.isInline { return nil }
        return value
    }

    func isBound(_ gesture: Gesture) -> Bool {
        value(for: gesture) != nil
    }

    func action(for gesture: Gesture) -> ActionDraft {
        ActionDraft(value(for: gesture))
    }

    func slide(for gesture: Gesture) -> SlideDraft {
        SlideDraft(value(for: gesture))
    }

    /// One line describing what a bound gesture does, for the list.
    func summary(for gesture: Gesture) -> String? {
        guard isBound(gesture) else { return nil }
        if gesture.isContinuous {
            switch slide(for: gesture) {
            case .none: return nil
            case .preset(let preset, _): return Titles.preset(preset)
            case .custom: return String(localized: "Custom")
            }
        }
        return Self.describe(action(for: gesture))
    }

    static func describe(_ action: ActionDraft) -> String? {
        switch action {
        case .none: nil
        case .builtIn(let action): Titles.action(action)
        case .shortcut(let keys): (try? Keystroke.parse(keys))?.description ?? keys
        case .application(let name): ApplicationReference(name).displayName
        case .url(let address): address
        case .text(let text): "“\(text)”"
        case .custom: String(localized: "Custom")
        }
    }

    /// macOS features that also react to this gesture as it is bound now.
    func overlaps(for gesture: Gesture) -> [String] {
        guard device == .trackpad, isEditable else { return [] }
        guard let binding = configuration.binding(
            for: gesture, device: .trackpad, application: nil, functionKeyDown: false
        ) else { return [] }
        return SystemGestures.overlaps(gesture, binding: binding)
    }

    // MARK: - Writing

    func set(_ action: ActionDraft, for gesture: Gesture) {
        write(action.tomlText, key: gesture.rawValue, section: device.sectionName)
    }

    func set(_ slide: SlideDraft, for gesture: Gesture) {
        write(slide.tomlText, key: gesture.rawValue, section: device.sectionName)
    }

    func setHapticFeedback(_ enabled: Bool) {
        write(enabled ? "true" : "false", key: "haptic-feedback", section: "GENERAL")
    }

    func setDominantHand(_ hand: Hand) {
        write(TOMLValue.quoted(hand.rawValue), key: "dominant-hand", section: "GENERAL")
    }

    private func write(_ value: String?, key: String, section: String) {
        guard isEditable else { return }
        var edited = document
        edited.set(key, to: value, in: section)
        guard edited != document else { return }
        do {
            // Never save a file the app itself would refuse to load.
            _ = try ConfigurationParser.parse(edited.text)
            try edited.text.write(to: store.fileURL, atomically: true, encoding: .utf8)
            writeError = nil
            apply(edited.text)
        } catch {
            writeError = "\(error)"
        }
    }

    // MARK: - Files

    func openConfigurationFile() {
        let workspace = NSWorkspace.shared
        if let editor = workspace.urlForApplication(toOpen: .plainText) {
            workspace.open([store.fileURL], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
        } else {
            workspace.open(store.fileURL)
        }
    }

    func openTrackpadSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// An application named in a binding, by name or bundle identifier.
struct ApplicationReference {
    let name: String
    let url: URL?

    init(_ name: String) {
        self.name = name
        let folders = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                       NSHomeDirectory() + "/Applications"]
        url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name)
            ?? folders.lazy
                .map { URL(fileURLWithPath: $0).appendingPathComponent(name + ".app") }
                .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    var displayName: String {
        guard let url else { return name }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    var icon: NSImage? {
        url.map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}
