import Foundation

/// Privacy-safe metadata shared by status failures and OAuth refresh. It never reads/retains a
/// response body. The clock is explicit for deterministic fixtures, not a scheduling mechanism.
public enum HTTPRetryAfter {
    public static func value(from headers: [String: String], now: Date = Date()) -> TimeInterval? {
        guard let value = headers.first(where: { $0.key.caseInsensitiveCompare("Retry-After") == .orderedSame })?.value
        else { return nil }
        if let seconds = TimeInterval(value), seconds.isFinite, seconds >= 0 { return seconds }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: value) else { return nil }
        let delay = date.timeIntervalSince(now)
        guard delay.isFinite else { return nil }
        return max(0, delay)
    }
}
