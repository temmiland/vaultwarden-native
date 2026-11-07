import BitwardenSdk
import Domain
import Foundation

/// Wraps the vendored SDK's `CryptoClient` crypto-init calls. Every cryptographic operation here
/// goes through `BitwardenSdk` - this type only shapes the request objects, it never touches key
/// material directly.
public protocol VaultUnlockService: Sendable {
    /// Unlocks the vault using the master password, given the wrapped keys the server returned at
    /// login (or that were cached locally in a `StoredAccount` from a previous login).
    func unlockWithMasterPassword(
        client: Client,
        userId: String,
        email: String,
        kdf: KeyDerivationParameters,
        masterPassword: String,
        encryptedUserKey: String,
        encryptedPrivateKey: String
    ) async throws

    /// Unlocks the vault using a previously-decrypted user key (the Touch ID path - the key was
    /// obtained once via `decryptedUserKey(client:)` right after a master-password unlock and is
    /// retrieved from the Keychain only after a successful biometric check).
    func unlockWithDecryptedKey(
        client: Client,
        userId: String,
        email: String,
        kdf: KeyDerivationParameters,
        encryptedPrivateKey: String,
        decryptedUserKey: String
    ) async throws

    /// Unlocks the vault using a PIN (the PIN unlock path - `pinProtectedUserKey` was produced once
    /// by `SessionPinUnlockSettings.enroll` via `CryptoClient.derivePinKey` and cached in the Keychain; it's
    /// retrieved and passed back here on every subsequent PIN unlock).
    func unlockWithPin(
        client: Client,
        userId: String,
        email: String,
        kdf: KeyDerivationParameters,
        encryptedPrivateKey: String,
        pin: String,
        pinProtectedUserKey: String
    ) async throws

    /// Reads back the current session's decrypted user key so it can be cached for biometric
    /// unlock. Only call this after a successful unlock, and only when the user has opted in.
    func decryptedUserKey(client: Client) async throws -> String
}

public struct SDKVaultUnlockService: VaultUnlockService {
    public init() {}

    public func unlockWithMasterPassword(
        client: Client,
        userId: String,
        email: String,
        kdf: KeyDerivationParameters,
        masterPassword: String,
        encryptedUserKey: String,
        encryptedPrivateKey: String
    ) async throws {
        let sdkKDF = try SDKKeyDerivationMapper.kdf(for: kdf)
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let request = InitUserCryptoRequest(
            userId: userId,
            kdfParams: sdkKDF,
            email: normalizedEmail,
            accountCryptographicState: .v1(privateKey: encryptedPrivateKey),
            method: .masterPasswordUnlock(
                password: masterPassword,
                masterPasswordUnlock: MasterPasswordUnlockData(
                    kdf: sdkKDF,
                    masterKeyWrappedUserKey: encryptedUserKey,
                    salt: normalizedEmail
                )
            ),
            upgradeToken: nil
        )
        try await client.crypto().initializeUserCrypto(req: request)
    }

    public func unlockWithDecryptedKey(
        client: Client,
        userId: String,
        email: String,
        kdf: KeyDerivationParameters,
        encryptedPrivateKey: String,
        decryptedUserKey: String
    ) async throws {
        let sdkKDF = try SDKKeyDerivationMapper.kdf(for: kdf)
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let request = InitUserCryptoRequest(
            userId: userId,
            kdfParams: sdkKDF,
            email: normalizedEmail,
            accountCryptographicState: .v1(privateKey: encryptedPrivateKey),
            method: .decryptedKey(decryptedUserKey: decryptedUserKey),
            upgradeToken: nil
        )
        try await client.crypto().initializeUserCrypto(req: request)
    }

    public func unlockWithPin(
        client: Client,
        userId: String,
        email: String,
        kdf: KeyDerivationParameters,
        encryptedPrivateKey: String,
        pin: String,
        pinProtectedUserKey: String
    ) async throws {
        let sdkKDF = try SDKKeyDerivationMapper.kdf(for: kdf)
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let request = InitUserCryptoRequest(
            userId: userId,
            kdfParams: sdkKDF,
            email: normalizedEmail,
            accountCryptographicState: .v1(privateKey: encryptedPrivateKey),
            method: .pin(pin: pin, pinProtectedUserKey: pinProtectedUserKey),
            upgradeToken: nil
        )
        try await client.crypto().initializeUserCrypto(req: request)
    }

    public func decryptedUserKey(client: Client) async throws -> String {
        try await client.crypto().getUserEncryptionKey()
    }
}
