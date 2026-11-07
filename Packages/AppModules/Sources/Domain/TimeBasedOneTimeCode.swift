import Foundation

public enum TimeBasedOneTimeCodeError: Error, Sendable, Equatable {
    case invalidMetadata, expired
}

/// Transient result, not picker state. Generation uses this exact date in the SDK; validity
/// is the same epoch-aligned period, never generation time plus an entire period.
public struct TimeBasedOneTimeCode: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let code: String
    public let period: UInt32
    public let generatedAt: Date
    public init(code: String, period: UInt32, generatedAt: Date) {
        self.code = code; self.period = period; self.generatedAt = generatedAt
    }

    public var description: String { "TimeBasedOneTimeCode(<redacted>)" }
    public var debugDescription: String { description }

    public func validate(at date: Date) throws {
        let generated = generatedAt.timeIntervalSince1970, current = date.timeIntervalSince1970
        guard !code.isEmpty, period > 0, generated.isFinite, generated >= 0,
              current.isFinite, current >= 0 else { throw TimeBasedOneTimeCodeError.invalidMetadata }
        let interval = Double(period)
        guard current >= generated, floor(current / interval) == floor(generated / interval) else {
            throw TimeBasedOneTimeCodeError.expired
        }
    }
}
