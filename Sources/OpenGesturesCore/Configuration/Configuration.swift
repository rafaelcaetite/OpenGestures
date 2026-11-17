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
    public var sections: [BindingSection] = [] {
        didSet { lookupOrder = Self.lookupOrder(of: sections) }
    }
    public var warnings: [String] = []
    /// Indices into `sections` for each device, most specific scope first.
    /// Worked out once when sections change, so looking up a binding, which
    /// happens for every step of a slide, allocates nothing.
    private var lookupOrder: [[Int]] = Array(repeating: [], count: DeviceKind.allCases.count)

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
        let order = lookupOrder[Self.slot(device)]
        if functionKeyDown {
            let key = GestureKey(gesture, requiresFunctionKey: true)
            for index in order where sections[index].scope.matches(application) {
                if let binding = sections[index].binding(for: key) { return binding }
            }
        }
        let key = GestureKey(gesture)
        for index in order where sections[index].scope.matches(application) {
            if let binding = sections[index].binding(for: key) { return binding }
        }
        return nil
    }

    /// Sections limited to some applications come first, then sections that
    /// exclude some, then global ones; file order within each group.
    private static func lookupOrder(of sections: [BindingSection]) -> [[Int]] {
        func rank(_ scope: ApplicationScope) -> Int {
            switch scope {
            case .only: 0
            case .except: 1
            case .global: 2
            }
        }
        var order = Array(repeating: [Int](), count: DeviceKind.allCases.count)
        for device in DeviceKind.allCases {
            order[slot(device)] = sections.indices
                .filter { sections[$0].device == device }
                .sorted { (rank(sections[$0].scope), $0) < (rank(sections[$1].scope), $1) }
        }
        return order
    }

    private static func slot(_ device: DeviceKind) -> Int {
        switch device {
        case .trackpad: 0
        case .mouse: 1
        }
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
