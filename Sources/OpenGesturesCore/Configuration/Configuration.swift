import Foundation

public struct Settings: Equatable, Sendable {
    public var hapticFeedback = true
    public var showMenuBarIcon = true
    /// Width of the edge zones for area clicks, as a fraction of the surface.
    public var edgeSize = 0.15
    /// Scroll direction for the trackpad and for mice, independent of each
    /// other. Nil follows the system's natural scrolling setting.
    public var trackpadNaturalScrolling: Bool?
    public var mouseNaturalScrolling: Bool?
    public var recognizer = RecognizerSettings()

    public init() {}
}

/// The application a binding applies to.
public struct ApplicationIdentity: Equatable, Sendable {
    public var name: String?
    public var bundleIdentifier: String?

    public init(name: String?, bundleIdentifier: String?) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
    }

    func matches(_ pattern: String) -> Bool {
        [name, bundleIdentifier].contains { $0?.caseInsensitiveCompare(pattern) == .orderedSame }
    }
}

public enum ApplicationScope: Equatable, Sendable {
    case global
    case only([String])
    case except([String])

    public func matches(_ application: ApplicationIdentity?) -> Bool {
        switch self {
        case .global:
            return true
        case .only(let names):
            guard let application else { return false }
            return names.contains(where: application.matches)
        case .except(let names):
            guard let application else { return true }
            return !names.contains(where: application.matches)
        }
    }

    public var title: String {
        switch self {
        case .global: "All applications"
        case .only(let names): names.joined(separator: ", ")
        case .except(let names): "All except " + names.joined(separator: ", ")
        }
    }

    /// Parses the quoted part of a heading such as `[TRACKPAD."Safari, Mail"]`.
    /// A leading `!` inverts the list.
    static func parse(_ text: String) -> ApplicationScope? {
        var body = text.trimmingCharacters(in: .whitespaces)
        let inverted = body.hasPrefix("!")
        if inverted { body.removeFirst() }
        let names = body.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !names.isEmpty else { return nil }
        return inverted ? .except(names) : .only(names)
    }
}

public struct GestureKey: Hashable, Sendable {
    public var gesture: Gesture
    /// The binding only applies while Fn is held.
    public var requiresFunctionKey: Bool

    public init(_ gesture: Gesture, requiresFunctionKey: Bool = false) {
        self.gesture = gesture
        self.requiresFunctionKey = requiresFunctionKey
    }

    public var name: String {
        (requiresFunctionKey ? "fn+" : "") + gesture.rawValue
    }
}

public struct BindingEntry: Sendable {
    public var key: GestureKey
    public var binding: Binding
    public var line: Int
    /// The comment written after the binding, if any.
    public var note: String?
}

public struct BindingSection: Sendable {
    public var device: DeviceKind
    public var scope: ApplicationScope
    public var line: Int
    public private(set) var entries: [BindingEntry] = []
    private var index: [GestureKey: Int] = [:]

    init(device: DeviceKind, scope: ApplicationScope, line: Int) {
        self.device = device
        self.scope = scope
        self.line = line
    }

    mutating func add(_ entry: BindingEntry) {
        index[entry.key] = entries.count
        entries.append(entry)
    }

    public func binding(for key: GestureKey) -> Binding? {
        index[key].map { entries[$0].binding }
    }
}

public struct Configuration: Sendable {
    public var settings = Settings()
    public var sections: [BindingSection] = []
    public var warnings: [String] = []

    public init() {}

    /// The binding that applies to `gesture` right now.
    ///
    /// Sections limited to the frontmost application win over sections that
    /// exclude other applications, which win over global ones. While Fn is
    /// held, `fn+` bindings are searched first in all of them.
    public func binding(
        for gesture: Gesture,
        device: DeviceKind,
        application: ApplicationIdentity?,
        functionKeyDown: Bool
    ) -> Binding? {
        let candidates = sections(for: device, application: application)
        if functionKeyDown {
            let key = GestureKey(gesture, requiresFunctionKey: true)
            for section in candidates {
                if let binding = section.binding(for: key) { return binding }
            }
        }
        let key = GestureKey(gesture)
        for section in candidates {
            if let binding = section.binding(for: key) { return binding }
        }
        return nil
    }

    func sections(for device: DeviceKind, application: ApplicationIdentity?) -> [BindingSection] {
        let matching = sections.filter { $0.device == device && $0.scope.matches(application) }
        let only = matching.filter { if case .only = $0.scope { true } else { false } }
        let except = matching.filter { if case .except = $0.scope { true } else { false } }
        let global = matching.filter { $0.scope == .global }
        return only + except + global
    }

    public var hasClickBindings: Bool {
        sections.contains { section in
            section.entries.contains { $0.key.gesture.category == .click }
        }
    }

    public var bindingCount: Int {
        sections.reduce(0) { $0 + $1.entries.count }
    }

    public func slideTarget(for binding: SlideBinding) -> SlideTarget {
        SlideTarget(directions: Set(binding.actions.keys), step: binding.step ?? settings.recognizer.slideStep)
    }
}
