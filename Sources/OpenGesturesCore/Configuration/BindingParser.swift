import Foundation

/// Turns binding values from the configuration file into bindings.
enum BindingParser {
    static func parseAction(_ value: TOMLValue) throws(BindingError) -> ActionBinding {
        switch value {
        case .string(let text):
            return ActionBinding(steps: [try parseStep(text)], source: text)
        case .array(let elements):
            let steps = try parseSequence(elements)
            return ActionBinding(steps: steps, source: describe(elements))
        case .table(let table):
            return try parseExpandedAction(table)
        default:
            throw BindingError("expected a string, an array or a table, found a \(value.typeName)")
        }
    }

    static func parseSlide(_ value: TOMLValue) throws(BindingError) -> SlideBinding {
        switch value {
        case .string(let name):
            guard let preset = SlidePreset(rawValue: name) else {
                let names = SlidePreset.allCases.map(\.rawValue).joined(separator: ", ")
                throw BindingError("unknown slide preset \"\(name)\"; use one of \(names), or a table with up, down, left or right")
            }
            return try binding(for: preset)
        case .table(let table):
            return try parseSlideTable(table)
        default:
            throw BindingError("a slide takes a preset name or a table with up, down, left or right")
        }
    }

    static func parseStep(_ raw: String) throws(BindingError) -> ActionStep {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if let rest = text.removingPrefix("url:") {
            guard !rest.isEmpty else { throw BindingError("url: needs an address") }
            return .openURL(rest)
        }
        if let rest = text.removingPrefix("script:") {
            guard !rest.isEmpty else { throw BindingError("script: needs a path") }
            return .runScript(rest)
        }
        if let rest = text.removingPrefix("menu:") {
            let path = rest.split(separator: ">").map { $0.trimmingCharacters(in: .whitespaces) }
            guard path.count >= 2, !path.contains(where: \.isEmpty) else {
                throw BindingError("menu: needs a path such as \"menu:File > New Window\"")
            }
            return .menuCommand(path)
        }
        if let rest = text.removingPrefix("app:") {
            guard !rest.isEmpty else { throw BindingError("app: needs an application name or bundle identifier") }
            return .openApplication(rest)
        }
        if let rest = raw.trimmingCharacters(in: .newlines).removingPrefix("text:") {
            return .typeText(rest)
        }
        if let rest = text.removingPrefix("sound:") {
            return .playSound(rest)
        }
        if let rest = text.removingPrefix("say:") {
            return .speak(rest)
        }
        if let rest = text.removingPrefix("wait:") {
            guard let milliseconds = Int(rest), (0...10_000).contains(milliseconds) else {
                throw BindingError("wait: takes milliseconds from 0 to 10000")
            }
            return .wait(milliseconds: milliseconds)
        }
        if text.contains("://") {
            return .openURL(text)
        }
        if let action = BuiltInAction(rawValue: text) {
            return action == .middleClick ? .mouseButton(3) : .builtIn(action)
        }
        if let rest = text.removingPrefix("mouse-") {
            guard let button = Int(rest), (3...32).contains(button) else {
                throw BindingError("mouse buttons run from mouse-3 to mouse-32")
            }
            return .mouseButton(button)
        }
        return .keystroke(try Keystroke.parse(text))
    }

    // MARK: - Private

    private static func parseSequence(_ elements: [TOMLValue]) throws(BindingError) -> [ActionStep] {
        guard !elements.isEmpty else { throw BindingError("empty sequence") }
        var steps: [ActionStep] = []
        for element in elements {
            guard case .string(let text) = element else {
                throw BindingError("sequence elements must be strings")
            }
            steps.append(try parseStep(text))
        }
        let totalWait = steps.reduce(0) { total, step in
            if case .wait(let milliseconds) = step { return total + milliseconds }
            return total
        }
        guard totalWait <= 10_000 else {
            throw BindingError("waits in one sequence add up to more than 10 seconds; use a script instead")
        }
        return steps
    }

    private static func parseExpandedAction(_ table: TOMLTable) throws(BindingError) -> ActionBinding {
        try rejectUnknownKeys(in: table, allowed: ["action", "haptic", "sound", "say"])
        var steps: [ActionStep] = []
        var source = ""
        if let sound = try string(table, "sound") {
            steps.append(.playSound(sound))
        }
        if let phrase = try string(table, "say") {
            steps.append(.speak(phrase))
        }
        if let action = table["action"] {
            let parsed = try parseAction(action)
            steps += parsed.steps
            source = parsed.source
        }
        guard !steps.isEmpty else {
            throw BindingError("a binding table needs action, sound or say")
        }
        if source.isEmpty {
            source = steps.map { "\($0)" }.joined(separator: ", ")
        }
        return ActionBinding(steps: steps, haptic: try bool(table, "haptic"), source: source)
    }

    private static func parseSlideTable(_ table: TOMLTable) throws(BindingError) -> SlideBinding {
        try rejectUnknownKeys(in: table, allowed: ["preset", "up", "down", "left", "right", "step", "haptic"])
        var binding: SlideBinding
        if let name = try string(table, "preset") {
            guard let preset = SlidePreset(rawValue: name) else {
                throw BindingError("unknown slide preset \"\(name)\"")
            }
            binding = try Self.binding(for: preset)
        } else {
            binding = SlideBinding(actions: [:], source: "")
        }
        for direction in Direction.allCases {
            if let value = table[direction.rawValue] {
                binding.actions[direction] = try parseAction(value)
            }
        }
        guard !binding.actions.isEmpty else {
            throw BindingError("a slide needs a preset or at least one of up, down, left and right")
        }
        if let step = table["step"] {
            guard let millimetres = step.doubleValue, SlideBinding.stepRange.contains(millimetres) else {
                throw BindingError("step is a distance in millimetres between 0.2 and 100")
            }
            binding.step = millimetres
        }
        binding.haptic = try bool(table, "haptic") ?? binding.haptic
        if binding.source.isEmpty || table.keys.contains(where: { Direction(rawValue: $0) != nil }) {
            binding.source = Direction.allCases.compactMap { direction in
                binding.actions[direction].map { "\(direction.rawValue): \($0.source)" }
            }.joined(separator: ", ")
        }
        return binding
    }

    private static func binding(for preset: SlidePreset) throws(BindingError) -> SlideBinding {
        var actions: [Direction: ActionBinding] = [:]
        for (direction, text) in preset.actions {
            actions[direction] = ActionBinding(steps: [try parseStep(text)], source: text)
        }
        return SlideBinding(actions: actions, step: preset.step, detent: preset.detent, source: preset.rawValue)
    }

    private static func rejectUnknownKeys(in table: TOMLTable, allowed: Set<String>) throws(BindingError) {
        if let unknown = table.keys.first(where: { !allowed.contains($0) }) {
            let names = allowed.sorted().joined(separator: ", ")
            throw BindingError("unknown option \"\(unknown)\"; expected \(names)")
        }
    }

    private static func string(_ table: TOMLTable, _ key: String) throws(BindingError) -> String? {
        guard let value = table[key] else { return nil }
        guard case .string(let text) = value else { throw BindingError("\(key) must be a string") }
        return text
    }

    private static func bool(_ table: TOMLTable, _ key: String) throws(BindingError) -> Bool? {
        guard let value = table[key] else { return nil }
        guard case .boolean(let flag) = value else { throw BindingError("\(key) must be true or false") }
        return flag
    }

    private static func describe(_ elements: [TOMLValue]) -> String {
        elements.map { element in
            if case .string(let text) = element { return text }
            return "?"
        }.joined(separator: ", ")
    }
}

extension String {
    func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }
}
