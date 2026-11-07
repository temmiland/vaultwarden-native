import Foundation

/// Privacy-safe failures for owned transports. The SDK's optional callback remains an SDK
/// compatibility boundary, not the error contract used by our repositories and presentation.
public enum SessionAuthorizationError: Error, Sendable, Equatable, LocalizedError {
    case temporarilyUnavailable
    case refreshRecoveryRequired

    public var errorDescription: String? {
        switch self {
        case .temporarilyUnavailable:
            "Session authorization is temporarily unavailable. Check the connection and try again."
        case .refreshRecoveryRequired:
            "A token refresh could not be confirmed. Sign out and sign in again before retrying; your vault data has not been deleted."
        }
    }
}
