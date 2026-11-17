import Foundation

/// A value from a TOML document.
public enum TOMLValue: Equatable, Sendable {
    case string(String)
    case integer(Int)
    case float(Double)
    case boolean(Bool)
    case array([TOMLValue])
    case table(TOMLTable)

    var typeName: String {
        switch self {
        case .string: "string"
        case .integer: "integer"
        case .float: "number"
        case .boolean: "boolean"
        case .array: "array"
        case .table: "table"
        }
    }

    var doubleValue: Double? {
        switch self {
        case .integer(let value): Double(value)
        case .float(let value): value
        default: nil
        }
    }
}

/// A TOML table that remembers key order, source lines and trailing comments.
public struct TOMLTable: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public var value: TOMLValue
        public var line: Int
        public var comment: String?
    }

    public private(set) var keys: [String] = []
    private var entries: [String: Entry] = [:]
    /// True for `{ ... }` tables written inline, false for `[header]` tables.
    public var isInline: Bool
    /// Line of the header that defined the table, or of its first key.
    public var line: Int

    public init(isInline: Bool = false, line: Int = 0) {
        self.isInline = isInline
        self.line = line
    }

    public subscript(key: String) -> TOMLValue? {
        entries[key]?.value
    }

    public func entry(_ key: String) -> Entry? {
        entries[key]
    }

    public var isEmpty: Bool { keys.isEmpty }

    mutating func set(_ key: String, _ value: TOMLValue, line: Int, comment: String? = nil) {
        if entries[key] == nil {
            keys.append(key)
        }
        entries[key] = Entry(value: value, line: line, comment: comment)
    }

    mutating func setComment(_ comment: String, for key: String) {
        entries[key]?.comment = comment
    }
}

public struct TOMLError: Error, Equatable, CustomStringConvertible {
    public var line: Int
    public var message: String

    public var description: String { "line \(line): \(message)" }
}

/// Parses the subset of TOML 1.0 that configuration files need: tables,
/// dotted and quoted keys, strings, integers, floats, booleans, arrays and
/// inline tables. Dates, multi-line strings and arrays of tables are rejected
/// with a clear error. Bare keys may also contain "+".
public struct TOMLParser {
    private let characters: [Character]
    private var index = 0
    private var line = 1
    private var root = TOMLTable(line: 1)
    private var currentPath: [String] = []
    private var definedTables: Set<[String]> = []

    public static func parse(_ text: String) throws(TOMLError) -> TOMLTable {
        var parser = TOMLParser(characters: Array(text))
        try parser.parseDocument()
        return parser.root
    }

    private init(characters: [Character]) {
        self.characters = characters
    }

    // MARK: Document structure

    private mutating func parseDocument() throws(TOMLError) {
        while true {
            skipWhitespaceCommentsAndNewlines()
            guard let character = peek() else { return }
            if character == "[" {
                try parseHeader()
            } else {
                let startLine = line
                let path = try parseKeyPath()
                skipWhitespace()
                try expect("=")
                skipWhitespace()
                let value = try parseValue()
                try insert(value, at: currentPath + path, line: startLine)
                skipWhitespace()
                if let comment = readComment() {
                    try annotate(currentPath + path, comment: comment)
                }
                try expectEndOfLine()
            }
        }
    }

    private mutating func parseHeader() throws(TOMLError) {
        let headerLine = line
        advance()
        if peek() == "[" {
            throw error("arrays of tables ([[...]]) are not supported")
        }
        skipWhitespace()
        let path = try parseKeyPath()
        skipWhitespace()
        try expect("]")
        if definedTables.contains(path) {
            throw error("table [\(path.joined(separator: "."))] is defined more than once", line: headerLine)
        }
        definedTables.insert(path)
        try ensureTable(at: path, line: headerLine)
        currentPath = path
        skipWhitespace()
        _ = readComment()
        try expectEndOfLine()
    }

    private mutating func ensureTable(at path: [String], line: Int) throws(TOMLError) {
        try Self.modify(&root, path: path, line: line) { (table: inout TOMLTable) throws(TOMLError) in
            if table.line == 0 { table.line = line }
        }
    }

    private mutating func insert(_ value: TOMLValue, at path: [String], line: Int) throws(TOMLError) {
        let parent = Array(path.dropLast())
        let key = path[path.count - 1]
        let errorLine = line
        try Self.modify(&root, path: parent, line: line) { (table: inout TOMLTable) throws(TOMLError) in
            if table[key] != nil {
                throw TOMLError(line: errorLine, message: "key \"\(key)\" is defined more than once")
            }
            if case .table(var inner) = value {
                inner.line = errorLine
                table.set(key, .table(inner), line: errorLine)
            } else {
                table.set(key, value, line: errorLine)
            }
        }
    }

    private mutating func annotate(_ path: [String], comment: String) throws(TOMLError) {
        let parent = Array(path.dropLast())
        let key = path[path.count - 1]
        try Self.modify(&root, path: parent, line: line) { (table: inout TOMLTable) throws(TOMLError) in
            table.setComment(comment, for: key)
        }
    }

    /// Walks to the table at `path`, creating implicit tables on the way.
    private static func modify(
        _ table: inout TOMLTable,
        path: [String],
        line: Int,
        _ body: (inout TOMLTable) throws(TOMLError) -> Void
    ) throws(TOMLError) {
        guard let head = path.first else {
            try body(&table)
            return
        }
        var child: TOMLTable
        switch table[head] {
        case .table(let existing):
            if existing.isInline {
                throw TOMLError(line: existing.line, message: "inline table \"\(head)\" cannot be extended")
            }
            child = existing
        case .none:
            child = TOMLTable(line: line)
        case .some(let other):
            throw TOMLError(line: table.entry(head)?.line ?? 0, message: "\"\(head)\" is a \(other.typeName), not a table")
        }
        try modify(&child, path: Array(path.dropFirst()), line: line, body)
        table.set(head, .table(child), line: table.entry(head)?.line ?? child.line)
    }

    // MARK: Keys

    private mutating func parseKeyPath() throws(TOMLError) -> [String] {
        var parts = [try parseKey()]
        while true {
            skipWhitespace()
            guard peek() == "." else { return parts }
            advance()
            skipWhitespace()
            parts.append(try parseKey())
        }
    }

    private mutating func parseKey() throws(TOMLError) -> String {
        switch peek() {
        case "\"": return try parseBasicString()
        case "'": return try parseLiteralString()
        default:
            var key = ""
            // "+" is accepted in bare keys, beyond TOML 1.0, so gestures can be
            // written as fn+four-finger-tap without quotes.
            while let character = peek(), character.isLetter || character.isNumber || "-_+".contains(character) {
                key.append(character)
                advance()
            }
            if key.isEmpty {
                throw error(peek().map { "unexpected \"\($0)\", expected a key" } ?? "expected a key")
            }
            return key
        }
    }

    // MARK: Values

    private mutating func parseValue() throws(TOMLError) -> TOMLValue {
        guard let character = peek() else { throw error("expected a value") }
        switch character {
        case "\"":
            if lookahead("\"\"\"") { throw error("multi-line strings are not supported") }
            return .string(try parseBasicString())
        case "'":
            if lookahead("'''") { throw error("multi-line strings are not supported") }
            return .string(try parseLiteralString())
        case "[":
            return .array(try parseArray())
        case "{":
            return .table(try parseInlineTable())
        case "t", "f":
            if lookahead("true") { advance(by: 4); return .boolean(true) }
            if lookahead("false") { advance(by: 5); return .boolean(false) }
            throw error("unexpected \"\(character)\", expected a value")
        default:
            return try parseNumber()
        }
    }

    private mutating func parseBasicString() throws(TOMLError) -> String {
        advance()
        var result = ""
        while let character = peek() {
            advance()
            switch character {
            case "\"":
                return result
            case "\n":
                throw error("unterminated string")
            case "\\":
                guard let escaped = peek() else { throw error("unterminated string") }
                advance()
                switch escaped {
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "r": result.append("\r")
                case "b": result.append("\u{08}")
                case "f": result.append("\u{0C}")
                case "u", "U":
                    let length = escaped == "u" ? 4 : 8
                    var hex = ""
                    for _ in 0..<length {
                        guard let digit = peek(), digit.isHexDigit else { throw error("invalid unicode escape") }
                        hex.append(digit)
                        advance()
                    }
                    guard let code = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(code) else {
                        throw error("invalid unicode escape")
                    }
                    result.unicodeScalars.append(scalar)
                default:
                    throw error("invalid escape \"\\\(escaped)\"")
                }
            default:
                result.append(character)
            }
        }
        throw error("unterminated string")
    }

    private mutating func parseLiteralString() throws(TOMLError) -> String {
        advance()
        var result = ""
        while let character = peek() {
            advance()
            if character == "'" { return result }
            if character == "\n" { break }
            result.append(character)
        }
        throw error("unterminated string")
    }

    private mutating func parseNumber() throws(TOMLError) -> TOMLValue {
        var text = ""
        while let character = peek(), character.isNumber || "+-._eE:TZ".contains(character) || character.isLetter {
            text.append(character)
            advance()
        }
        if text.isEmpty {
            throw error(peek().map { "unexpected \"\($0)\", expected a value" } ?? "expected a value")
        }
        if text.contains(":") || text.filter({ $0 == "-" }).count >= 2 && !text.hasPrefix("-") {
            throw error("dates and times are not supported")
        }
        let digits = text.replacingOccurrences(of: "_", with: "")
        if let integer = Int(digits) {
            return .integer(integer)
        }
        if digits.contains(where: { ".eE".contains($0) }), let number = Double(digits), number.isFinite {
            return .float(number)
        }
        throw error("invalid value \"\(text)\"")
    }

    private mutating func parseArray() throws(TOMLError) -> [TOMLValue] {
        advance()
        var values: [TOMLValue] = []
        while true {
            skipWhitespaceCommentsAndNewlines()
            if peek() == "]" {
                advance()
                return values
            }
            values.append(try parseValue())
            skipWhitespaceCommentsAndNewlines()
            switch peek() {
            case ",": advance()
            case "]": advance(); return values
            default: throw error("expected \",\" or \"]\" in array")
            }
        }
    }

    private mutating func parseInlineTable() throws(TOMLError) -> TOMLTable {
        let startLine = line
        advance()
        var table = TOMLTable(isInline: true, line: startLine)
        while true {
            skipWhitespaceCommentsAndNewlines()
            if peek() == "}" {
                advance()
                return table
            }
            let keyLine = line
            let path = try parseKeyPath()
            skipWhitespace()
            try expect("=")
            skipWhitespace()
            let value = try parseValue()
            let parent = Array(path.dropLast())
            let key = path[path.count - 1]
            try Self.modify(&table, path: parent, line: keyLine) { (inner: inout TOMLTable) throws(TOMLError) in
                if inner[key] != nil {
                    throw TOMLError(line: keyLine, message: "key \"\(key)\" is defined more than once")
                }
                inner.set(key, value, line: keyLine)
            }
            skipWhitespaceCommentsAndNewlines()
            switch peek() {
            case ",": advance()
            case "}": advance(); return table
            default: throw error("expected \",\" or \"}\" in inline table")
            }
        }
    }

    // MARK: Scanning

    private func peek() -> Character? {
        index < characters.count ? characters[index] : nil
    }

    private func lookahead(_ text: String) -> Bool {
        var position = index
        for character in text {
            guard position < characters.count, characters[position] == character else { return false }
            position += 1
        }
        return true
    }

    private mutating func advance(by count: Int = 1) {
        for _ in 0..<count where index < characters.count {
            if characters[index] == "\n" { line += 1 }
            index += 1
        }
    }

    private mutating func skipWhitespace() {
        while let character = peek(), character == " " || character == "\t" {
            advance()
        }
    }

    private mutating func skipWhitespaceCommentsAndNewlines() {
        while let character = peek() {
            if character == " " || character == "\t" || character.isNewline {
                advance()
            } else if character == "#" {
                _ = readComment()
            } else {
                return
            }
        }
    }

    /// Consumes a `#` comment up to the end of the line and returns its text.
    private mutating func readComment() -> String? {
        guard peek() == "#" else { return nil }
        advance()
        var text = ""
        while let character = peek(), !character.isNewline {
            text.append(character)
            advance()
        }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private mutating func expect(_ character: Character) throws(TOMLError) {
        guard peek() == character else {
            throw error(peek().map { "expected \"\(character)\", found \"\($0)\"" } ?? "expected \"\(character)\"")
        }
        advance()
    }

    private mutating func expectEndOfLine() throws(TOMLError) {
        skipWhitespace()
        guard let character = peek() else { return }
        guard character.isNewline else {
            throw error("unexpected \"\(character)\" after value")
        }
        advance()
    }

    private func error(_ message: String, line: Int? = nil) -> TOMLError {
        TOMLError(line: line ?? self.line, message: message)
    }
}
