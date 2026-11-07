import Foundation

/// Parses server ISO-8601 timestamps with an explicit timezone. If the platform formatter rejects
/// overlong fractional precision (e.g. `2024-01-01T12:00:00.1234567Z`), trim to milliseconds.
///
/// Single date-format policy shared by the SDK-bound wire codecs.
public enum ServerDateParsing {
    private static let withFractional = LockedServerDateFormatter(
        options: [.withInternetDateTime, .withFractionalSeconds]
    )
    private static let withoutFractional = LockedServerDateFormatter(options: [.withInternetDateTime])

    public static func parse(_ string: String) -> Date? {
        // Do not let lenient formatter parsing, or fractional trimming, turn a malformed marker
        // into a valid date. In particular an invalid deleted/archive date must never become nil
        // merely to make the item appear active at a mapping boundary.
        let timestampPattern = #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"#
        guard string.range(of: timestampPattern, options: .regularExpression) != nil else { return nil }
        if let date = withFractional.date(from: string) {
            return date
        }
        if let date = withoutFractional.date(from: string) {
            return date
        }
        // Trim overlong fractional-second precision (server sometimes emits 7 digits) to 3.
        if let dotIndex = string.firstIndex(of: "."), let zIndex = string.lastIndex(of: "Z"), dotIndex < zIndex {
            let fractionalRange = string.index(after: dotIndex) ..< zIndex
            let fractional = String(string[fractionalRange].prefix(3))
            let trimmed = string[..<dotIndex] + "." + fractional + "Z"
            return withFractional.date(from: String(trimmed))
        }
        return nil
    }

    public static func format(_ date: Date) -> String {
        withFractional.string(from: date)
    }
}

/// ISO8601DateFormatter is not Sendable. Its immutable configuration and every parse/format
/// call stay behind this lock; no formatter escapes. Concurrent codec regression tests cover
/// this shared cache, preserving existing parsing/output instead of suppressing diagnostics.
private final class LockedServerDateFormatter: @unchecked Sendable {
    private let lock = NSLock()
    private let formatter: ISO8601DateFormatter
    init(options: ISO8601DateFormatter.Options) {
        formatter = ISO8601DateFormatter()
        formatter.formatOptions = options
    }

    func date(from string: String) -> Date? { lock.withLock { formatter.date(from: string) } }
    func string(from date: Date) -> String { lock.withLock { formatter.string(from: date) } }
}
