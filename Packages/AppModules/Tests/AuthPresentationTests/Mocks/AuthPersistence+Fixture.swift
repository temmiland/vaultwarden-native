@testable import AuthPresentation
import AutoFillContract
@testable import Data
import Foundation

extension StoredAuthAccount {
    static func fixture(userID: String = "user-1", server: String = "https://vault.example.com") -> Self {
        Self(
            userId: userID,
            email: "test@example.com",
            serverBaseURL: URL(string: server)!,
            kdfType: 0,
            kdfIterations: 600_000,
            kdfMemory: nil,
            kdfParallelism: nil,
            encryptedUserKey: "fake-wrapped-user-key",
            encryptedPrivateKey: "fake-test-wrapped-private-key",
            isBiometricUnlockEnabled: false
        )
    }
}

extension AuthCredentialStore {
    /// Setup/legacy assertions only. Production captures this epoch before suspension.
    func recordPinFailure(requiringScope scope: TokenScope) throws -> Int {
        try recordPinFailure(requiringScope: scope, publicationEpoch: autofillPublicationEpoch())
    }

    func resetPinFailureCount(requiringScope scope: TokenScope) throws {
        try resetPinFailureCount(requiringScope: scope, publicationEpoch: autofillPublicationEpoch())
    }

    func disableBiometricUnlock(requiringScope scope: TokenScope) throws {
        try disableBiometricUnlock(requiringScope: scope, publicationEpoch: autofillPublicationEpoch())
    }

    func disablePinUnlock(requiringScope scope: TokenScope) -> Bool {
        (try? disablePinUnlock(requiringScope: scope, publicationEpoch: autofillPublicationEpoch())) ?? false
    }

    /// Test setup commits immediately. Production must supply authority captured before the
    /// suspended login flow; there is no unchecked two-argument entrypoint in app sources.
    @discardableResult
    func saveSession(account: StoredAuthAccount, tokens: TokenPair) throws -> PersistedAuthSession {
        try saveSession(account: account, tokens: tokens, requiring: freshLoginCommitProof()).session
    }

    /// Fixture convenience; production has no token-only persistence entrypoint.
    @discardableResult
    func save(tokens: TokenPair) throws -> TokenPair {
        if let current = try loadSession() {
            return try saveRefreshedTokens(
                tokens,
                basedOnGeneration: current.tokens.generation,
                requiringScope: current.scope
            ) ?? current.tokens
        }
        return try saveSession(account: loadAccount() ?? .fixture(), tokens: tokens).tokens
    }

    func publishForTesting() throws {
        guard let account = try loadAccount() else { throw CancellationError() }
        try saveSharedAutofillUserKey(
            "fake-test-user-key",
            accountInfo: account.autoFillAccountInfo(),
            publicationEpoch: autofillPublicationEpoch()
        )
    }
}
