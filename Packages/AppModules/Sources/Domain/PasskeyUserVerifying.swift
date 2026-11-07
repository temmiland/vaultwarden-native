import Foundation

public enum PasskeyUserVerificationError: Error, Sendable, Equatable {
    case userCanceled
}

/// Existing passkey user verification may use device-owner authentication (including passcode).
/// This is not the biometric-only vault-unlock port or a master-password re-prompt grant.
public protocol PasskeyUserVerifying: Sendable {
    func isVerificationAvailable() -> Bool
    func verify(reason: String) async throws -> Bool
}
