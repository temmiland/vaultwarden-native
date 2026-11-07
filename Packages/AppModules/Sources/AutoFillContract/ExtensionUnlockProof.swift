import Foundation

/// Nonsecret ownership metadata. An account ID alone is not unique across different servers.
public struct AutoFillAccountIdentity: Codable, Sendable, Equatable {
    public let userID: String
    public let serverBaseURL: URL

    public init(userID: String, serverBaseURL: URL) {
        self.userID = userID
        self.serverBaseURL = serverBaseURL
    }
}

/// Renewed on every successful app unlock, including re-unlocking the same account/key.
/// Possession of this metadata alone never authorizes decryption; the Keychain record does.
public struct ExtensionUnlockProof: Codable, Sendable, Equatable {
    public let unlockID: UUID
    public let revocationEpoch: UUID
    public let account: AutoFillAccountIdentity
    /// Nil is valid for pure lifecycle fixtures, but never authorizes token access.
    public let authenticationID: UUID?

    public init(
        unlockID: UUID = UUID(),
        revocationEpoch: UUID = UUID(),
        account: AutoFillAccountIdentity,
        authenticationID: UUID? = nil
    ) {
        self.unlockID = unlockID
        self.revocationEpoch = revocationEpoch
        self.account = account
        self.authenticationID = authenticationID
    }
}
