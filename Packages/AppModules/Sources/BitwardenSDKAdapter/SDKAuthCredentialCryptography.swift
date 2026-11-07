import Domain

/// Data's credential-crypto port contains no raw SDK Client. One opaque resource is shared
/// through hashing, initialization and handoff; revoking it denies late SDK results.
public protocol AuthCredentialCryptography: Sendable {
    var resource: SDKSessionClient { get }
    func hashPassword(email: String, password: String, kdf: KeyDerivationParameters) async throws -> String
    func unlockPassword(
        userID: String,
        email: String,
        kdf: KeyDerivationParameters,
        password: String,
        wrappedUserKey: String,
        wrappedPrivateKey: String
    ) async throws
    func decryptedUserKey() async throws -> String
    func unlockBiometric(
        userID: String,
        email: String,
        kdf: KeyDerivationParameters,
        wrappedPrivateKey: String,
        decryptedUserKey: String
    ) async throws
    func unlockPIN(
        userID: String,
        email: String,
        kdf: KeyDerivationParameters,
        wrappedPrivateKey: String,
        pin: String,
        protectedUserKey: String
    ) async throws
}

public struct SDKAuthCredentialCryptography: AuthCredentialCryptography {
    public let resource: SDKSessionClient
    private let unlockService: any VaultUnlockService

    public init(resource: SDKSessionClient, unlockService: any VaultUnlockService = SDKVaultUnlockService()) {
        self.resource = resource
        self.unlockService = unlockService
    }

    public func hashPassword(email: String, password: String, kdf: KeyDerivationParameters) async throws -> String {
        try await SDKAuthenticationService(sessionClient: resource).hashPassword(
            email: email,
            password: password,
            kdf: kdf
        )
    }

    public func unlockPassword(
        userID: String,
        email: String,
        kdf: KeyDerivationParameters,
        password: String,
        wrappedUserKey: String,
        wrappedPrivateKey: String
    ) async throws {
        try await resource.withClient {
            try await unlockService.unlockWithMasterPassword(
                client: $0,
                userId: userID,
                email: email,
                kdf: kdf,
                masterPassword: password,
                encryptedUserKey: wrappedUserKey,
                encryptedPrivateKey: wrappedPrivateKey
            )
        }
    }

    public func decryptedUserKey() async throws -> String {
        try await resource.withClient { try await unlockService.decryptedUserKey(client: $0) }
    }

    public func unlockBiometric(
        userID: String,
        email: String,
        kdf: KeyDerivationParameters,
        wrappedPrivateKey: String,
        decryptedUserKey: String
    ) async throws {
        try await resource.withClient {
            try await unlockService.unlockWithDecryptedKey(
                client: $0,
                userId: userID,
                email: email,
                kdf: kdf,
                encryptedPrivateKey: wrappedPrivateKey,
                decryptedUserKey: decryptedUserKey
            )
        }
    }

    public func unlockPIN(
        userID: String,
        email: String,
        kdf: KeyDerivationParameters,
        wrappedPrivateKey: String,
        pin: String,
        protectedUserKey: String
    ) async throws {
        try await resource.withClient {
            try await unlockService.unlockWithPin(
                client: $0,
                userId: userID,
                email: email,
                kdf: kdf,
                encryptedPrivateKey: wrappedPrivateKey,
                pin: pin,
                pinProtectedUserKey: protectedUserKey
            )
        }
    }
}
