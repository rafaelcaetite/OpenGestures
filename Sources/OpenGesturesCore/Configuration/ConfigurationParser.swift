import Foundation

public struct ConfigurationError: Error, Equatable, CustomStringConvertible {
    public var line: Int?
    public var message: String

    public init(line: Int?, message: String) {
        self.line = line
        self.message = message
    }

    public var description: String {
        line.map { "line \($0): \(message)" } ?? message
    }
}

public enum ConfigurationParser {
    public static func parse(_ text: String) throws(ConfigurationError) -> Configuration {
        let document: TOMLTable
        do {
            document = try TOMLParser.parse(text)
        } catch {
            throw ConfigurationError(line: error.line, message: error.message)
        }

        var configuration = Configuration()
        for key in document.keys {
            guard let entry = document.entry(key) else { continue }
            if key == "GENERAL" {
                configuration.settings = try parseSettings(entry, warnings: &configuration.warnings)
            } else if let device = DeviceKind.allCases.first(where: { $0.sectionName == key }) {
                configuration.sections += try parseDevice(device, entry)
            } else {
                configuration.warnings.append("line \(entry.line): unknown section \"\(key)\" ignored")
            }
        }
        return configuration
    }

    // MARK: - General settings

    private static func parseSettings(_ entry: TOMLTable.Entry, warnings: inout [String]) throws(ConfigurationError) -> Settings {
        guard case .table(let table) = entry.value else {
            throw ConfigurationError(line: entry.line, message: "GENERAL must be a table")
        }
        var settings = Settings()
        for key in table.keys {
            guard let item = table.entry(key) else { continue }
            func fail(_ message: String) -> ConfigurationError {
                ConfigurationError(line: item.line, message: "\(key): \(message)")
            }
            func number(in range: ClosedRange<Double>, unit: String) throws(ConfigurationError) -> Double {
                guard let value = item.value.doubleValue, range.contains(value) else {
                    throw fail("expected a number of \(unit) from \(range.lowerBound.formatted()) to \(range.upperBound.formatted())")
                }
                return value
            }
            func flag() throws(ConfigurationError) -> Bool {
                guard case .boolean(let value) = item.value else { throw fail("expected true or false") }
                return value
            }

            switch key {
            case "haptic-feedback":
                settings.hapticFeedback = try flag()
            case "show-menu-bar-icon":
                settings.showMenuBarIcon = try flag()
            case "dominant-hand":
                guard case .string(let text) = item.value, let hand = Hand(rawValue: text) else {
                    throw fail("expected \"left\" or \"right\"")
                }
                settings.recognizer.dominantHand = hand
            case "tap-duration":
                settings.recognizer.tapDuration = try number(in: 50...1000, unit: "milliseconds") / 1000
            case "double-tap-interval":
                settings.recognizer.doubleTapInterval = try number(in: 100...1000, unit: "milliseconds") / 1000
            case "swipe-distance":
                settings.recognizer.swipeDistance = try number(in: 5...80, unit: "millimetres")
            case "slide-step":
                settings.recognizer.slideStep = try number(in: SlideBinding.stepRange, unit: "millimetres")
            case "edge-size":
                settings.edgeSize = try number(in: 0.05...0.4, unit: "fractions of the surface")
            default:
                warnings.append("line \(item.line): unknown setting \"\(key)\" ignored")
            }
        }
        return settings
    }

    // MARK: - Bindings

    private static func parseDevice(_ device: DeviceKind, _ entry: TOMLTable.Entry) throws(ConfigurationError) -> [BindingSection] {
        guard case .table(let table) = entry.value, !table.isInline else {
            throw ConfigurationError(line: entry.line, message: "\(device.sectionName) must be a table")
        }
        var global = BindingSection(device: device, scope: .global, line: table.line)
        var scoped: [BindingSection] = []

        for key in table.keys {
            guard let item = table.entry(key) else { continue }
            if case .table(let inner) = item.value, !inner.isInline {
                guard let scope = ApplicationScope.parse(key) else {
                    throw ConfigurationError(line: inner.line, message: "[\(device.sectionName).\"\(key)\"] names no application")
                }
                var section = BindingSection(device: device, scope: scope, line: inner.line)
                for innerKey in inner.keys {
                    guard let innerItem = inner.entry(innerKey) else { continue }
                    if case .table(let nested) = innerItem.value, !nested.isInline {
                        throw ConfigurationError(line: nested.line, message: "application sections cannot be nested")
                    }
                    section.add(try parseBinding(innerKey, innerItem, device: device))
                }
                scoped.append(section)
            } else {
                global.add(try parseBinding(key, item, device: device))
            }
        }
        return [global] + scoped
    }

    private static func parseBinding(_ key: String, _ item: TOMLTable.Entry, device: DeviceKind) throws(ConfigurationError) -> BindingEntry {
        var name = key
        var requiresFunctionKey = false
        if name.lowercased().hasPrefix("fn+") {
            requiresFunctionKey = true
            name = String(name.dropFirst(3))
        }
        guard let gesture = Gesture(rawValue: name) else {
            var message = "unknown gesture \"\(name)\""
            if let suggestion = suggestion(for: name) {
                message += "; did you mean \"\(suggestion)\"?"
            }
            throw ConfigurationError(line: item.line, message: message)
        }
        guard gesture.supportedDevices.contains(device) else {
            let available = gesture.supportedDevices.map(\.sectionName).sorted().joined(separator: ", ")
            throw ConfigurationError(line: item.line, message: "\(name) is not available in \(device.sectionName); use it in \(available)")
        }

        let binding: Binding
        do {
            binding = gesture.isContinuous
                ? .slide(try BindingParser.parseSlide(item.value))
                : .action(try BindingParser.parseAction(item.value))
        } catch {
            throw ConfigurationError(line: item.line, message: "\(key): \(error.message)")
        }
        return BindingEntry(
            key: GestureKey(gesture, requiresFunctionKey: requiresFunctionKey),
            binding: binding,
            line: item.line,
            note: item.comment
        )
    }

    static func suggestion(for name: String) -> String? {
        let scored = Gesture.allCases.map { ($0.rawValue, editDistance(name, $0.rawValue)) }
        guard let best = scored.min(by: { $0.1 < $1.1 }), best.1 <= 3 else { return nil }
        return best.0
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var previous = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...max(b.count, 1) where !b.isEmpty {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            previous = current
        }
        return previous[b.count]
    }
}
