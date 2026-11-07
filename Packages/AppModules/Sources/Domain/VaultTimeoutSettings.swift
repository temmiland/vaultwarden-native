import Foundation

/// User-configurable policy for what the app does after it has been away for a period of time.
/// It is preference data, not authentication or vault content.
public struct VaultTimeoutPreference: Codable, Equatable, Sendable {
    public enum Duration: String, Codable, Sendable, CaseIterable {
        case immediately, oneMinute, fiveMinutes, fifteenMinutes, thirtyMinutes, oneHour, never

        public var displayName: String {
            switch self {
            case .immediately: "Immediately"
            case .oneMinute: "1 minute"
            case .fiveMinutes: "5 minutes"
            case .fifteenMinutes: "15 minutes"
            case .thirtyMinutes: "30 minutes"
            case .oneHour: "1 hour"
            case .never: "Never"
            }
        }

        /// Idle seconds before the timeout action should fire, or `nil` for `.never`.
        public var seconds: TimeInterval? {
            switch self {
            case .immediately: 0
            case .oneMinute: 60
            case .fiveMinutes: 300
            case .fifteenMinutes: 900
            case .thirtyMinutes: 1_800
            case .oneHour: 3_600
            case .never: nil
            }
        }
    }

    public enum Action: String, Codable, Sendable, CaseIterable {
        case lock, logOut

        public var displayName: String {
            switch self {
            case .lock: "Lock"
            case .logOut: "Log Out"
            }
        }
    }

    public var duration: Duration
    public var action: Action

    public init(duration: Duration = .fifteenMinutes, action: Action = .lock) {
        self.duration = duration
        self.action = action
    }

    public static let `default` = VaultTimeoutPreference()
}

/// Injectable persistence boundary so Settings can report failed reads/writes and tests can
/// exercise failures without touching a user's defaults database.
public protocol VaultTimeoutSettingsRepository: Sendable {
    func load() throws -> VaultTimeoutPreference
    func save(_ preference: VaultTimeoutPreference) throws
}
