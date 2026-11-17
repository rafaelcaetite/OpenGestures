import Foundation

/// Edits single keys of a configuration file in place.
///
/// Only the lines of the key being changed are touched, so comments, blank
/// lines, commented-out examples and the order of everything else survive an
/// edit made from the gesture editor. Values are passed already written as
/// TOML, such as `"volume"` or `{ preset = "volume", step = 0.6 }`.
public struct ConfigurationDocument: Equatable, Sendable {
    public private(set) var text: String

    public init(text: String) {
        self.text = text
    }

    /// Sets `key` in the table `[section]` to `value`, or removes the key when
    /// `value` is nil. A missing table is appended to the end of the file.
    public mutating func set(_ key: String, to value: String?, in section: String) {
        var lines = text.components(separatedBy: "\n")
        let layout = Self.layout(of: lines, section: section)

        guard let layout else {
            guard let value else { return }
            while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
                lines.removeLast()
            }
            if !lines.isEmpty {
                lines.append("")
            }
            lines += ["[\(section)]", "\(key) = \(value)", ""]
            text = lines.joined(separator: "\n")
            return
        }

        if let range = layout.keys[key] {
            if let value {
                let first = lines[range.lowerBound]
                let indent = String(first.prefix { $0 == " " || $0 == "\t" })
                // Keep a comment written after a one-line value.
                let comment = range.count == 1 ? Self.trailingComment(of: first) : ""
                lines.replaceSubrange(range, with: ["\(indent)\(key) = \(value)\(comment)"])
            } else {
                lines.removeSubrange(range)
            }
        } else if let value {
            lines.insert("\(key) = \(value)", at: layout.insertionLine)
        }
        text = lines.joined(separator: "\n")
    }

    // MARK: - Scanning

    private struct SectionLayout {
        /// Line ranges of the keys written directly in the section.
        var keys: [String: Range<Int>] = [:]
        /// Where a new key goes: after the last key, or below the header.
        var insertionLine: Int
    }

    private static func layout(of lines: [String], section: String) -> SectionLayout? {
        let header = "[\(section)]"
        guard let headerLine = lines.firstIndex(where: { code(of: $0).trimmingCharacters(in: .whitespaces) == header }) else {
            return nil
        }

        var layout = SectionLayout(insertionLine: headerLine + 1)
        var index = headerLine + 1
        while index < lines.count {
            let body = code(of: lines[index]).trimmingCharacters(in: .whitespaces)
            if body.hasPrefix("[") { break }
            guard let equals = body.firstIndex(of: "=") else {
                index += 1
                continue
            }
            let key = body[..<equals].trimmingCharacters(in: .whitespaces)
            // A value may open brackets that close on later lines.
            var depth = nesting(of: lines[index])
            var end = index + 1
            while depth > 0, end < lines.count {
                depth += nesting(of: lines[end])
                end += 1
            }
            layout.keys[key] = index..<end
            layout.insertionLine = end
            index = end
        }
        return layout
    }

    /// The line up to its comment, ignoring `#` inside strings.
    private static func code(of line: String) -> Substring {
        line[..<(commentStart(in: line) ?? line.endIndex)]
    }

    private static func trailingComment(of line: String) -> String {
        guard let start = commentStart(in: line) else { return "" }
        var gapStart = start
        while gapStart > line.startIndex, line[line.index(before: gapStart)].isWhitespace {
            gapStart = line.index(before: gapStart)
        }
        return String(line[gapStart...])
    }

    private static func commentStart(in line: String) -> String.Index? {
        var quote: Character?
        var escaped = false
        for index in line.indices {
            let character = line[index]
            if let open = quote {
                if escaped {
                    escaped = false
                } else if character == "\\" && open == "\"" {
                    escaped = true
                } else if character == open {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "#" {
                return index
            }
        }
        return nil
    }

    /// Brackets and braces opened minus those closed, outside strings.
    private static func nesting(of line: String) -> Int {
        var depth = 0
        var quote: Character?
        var escaped = false
        for character in code(of: line) {
            if let open = quote {
                if escaped {
                    escaped = false
                } else if character == "\\" && open == "\"" {
                    escaped = true
                } else if character == open {
                    quote = nil
                }
                continue
            }
            switch character {
            case "\"", "'": quote = character
            case "[", "{": depth += 1
            case "]", "}": depth -= 1
            default: break
            }
        }
        return depth
    }
}

extension TOMLValue {
    /// The value written as TOML, on one line.
    public var tomlText: String {
        switch self {
        case .string(let text): return Self.quoted(text)
        case .integer(let value): return String(value)
        case .float(let value): return Self.number(value)
        case .boolean(let value): return value ? "true" : "false"
        case .array(let elements): return "[" + elements.map(\.tomlText).joined(separator: ", ") + "]"
        case .table(let table):
            let pairs = table.keys.compactMap { key in table[key].map { "\(key) = \($0.tomlText)" } }
            return pairs.isEmpty ? "{}" : "{ " + pairs.joined(separator: ", ") + " }"
        }
    }

    /// A basic string with the characters TOML requires escaped.
    public static func quoted(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\t": result += "\\t"
            case "\r": result += "\\r"
            case _ where scalar.value < 0x20 || scalar.value == 0x7F:
                result += String(format: "\\u%04X", scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }

    /// A float rounded to two decimals, written without trailing zeros.
    public static func number(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() {
            return String(format: "%.1f", rounded)
        }
        return String(rounded)
    }
}
