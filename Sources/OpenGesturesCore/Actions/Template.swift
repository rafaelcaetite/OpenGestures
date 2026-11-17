import Foundation

/// Expands `{{placeholders}}` in URLs.
///
/// Placeholders: `clipboard`, `date` (2026-01-31), `time` (14:05),
/// `datetime` (ISO 8601), `timestamp` (Unix seconds) and `date:FORMAT` with
/// any `DateFormatter` pattern. Filters follow a bar: `urlencode`, `trim`,
/// `lowercase`, `uppercase`. Unknown placeholders are left untouched.
public enum Template {
    public struct Context {
        public var clipboard: () -> String
        public var now: Date
        public var timeZone: TimeZone

        public init(clipboard: @escaping () -> String, now: Date = Date(), timeZone: TimeZone = .current) {
            self.clipboard = clipboard
            self.now = now
            self.timeZone = timeZone
        }
    }

    public static func render(_ template: String, context: Context) -> String {
        var output = ""
        var remainder = Substring(template)
        while let open = remainder.range(of: "{{") {
            output += remainder[..<open.lowerBound]
            let afterOpen = remainder[open.upperBound...]
            guard let close = afterOpen.range(of: "}}") else {
                output += remainder[open.lowerBound...]
                return output
            }
            let expression = afterOpen[..<close.lowerBound]
            if let value = evaluate(expression, context: context) {
                output += value
            } else {
                output += remainder[open.lowerBound..<close.upperBound]
            }
            remainder = afterOpen[close.upperBound...]
        }
        return output + remainder
    }

    private static func evaluate(_ expression: Substring, context: Context) -> String? {
        let parts = expression.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard var value = value(of: parts[0], context: context) else { return nil }
        for filter in parts.dropFirst() {
            switch filter {
            case "urlencode": value = value.addingPercentEncoding(withAllowedCharacters: .urlUnreserved) ?? value
            case "trim": value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            case "lowercase": value = value.lowercased()
            case "uppercase": value = value.uppercased()
            default: return nil
            }
        }
        return value
    }

    private static func value(of name: String, context: Context) -> String? {
        switch name {
        case "clipboard": return context.clipboard()
        case "date": return format("yyyy-MM-dd", context)
        case "time": return format("HH:mm", context)
        case "datetime":
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = context.timeZone
            return formatter.string(from: context.now)
        case "timestamp": return String(Int(context.now.timeIntervalSince1970))
        default:
            guard name.hasPrefix("date:") else { return nil }
            return format(String(name.dropFirst(5)), context)
        }
    }

    private static func format(_ pattern: String, _ context: Context) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = context.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: context.now)
    }
}

extension CharacterSet {
    /// RFC 3986 unreserved characters.
    static let urlUnreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}
