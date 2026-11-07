@testable import AuthPresentation
import BitwardenSdk
import BitwardenSDKAdapter
import Domain
import Foundation

/// Records which unlock method was invoked and with what arguments, and either succeeds or throws
/// a pre-programmed error - lets `UnlockModelTests` exercise the PIN/password/biometric paths
/// without ever touching the real SDK crypto FFI.
final class MockVaultUnlockService: VaultUnlockService, @unchecked Sendable {
    enum Call: Equatable {
        case masterPassword(masterPassword: String, encryptedUserKey: String)
        case decryptedKey(decryptedUserKey: String)
        case pin(pin: String, pinProtectedUserKey: String)
    }

    private(set) var calls: [Call] = []
    var errorToThrow: Error?
    var decryptedUserKeyToReturn = "decrypted-user-key"
    var beforePinUnlock: (@Sendable () async -> Void)?

    func unlockWithMasterPassword(
        client: Client,
        userId: String,
        email: String,
        kdf: KeyDerivationParameters,
        masterPassword: String,
        encryptedUserKey: String,
        encryptedPrivateKey: String
    ) async throws {
        calls.append(.masterPassword(masterPassword: masterPassword, encryptedUserKey: encryptedUserKey))
        if let errorToThrow { throw errorToThrow }
    }

    func unlockWithDecryptedKey(
        client: Client,
        userId: String,
        email: String,
        kdf: KeyDerivationParameters,
        encryptedPrivateKey: String,
        decryptedUserKey: String
    ) async throws {
        calls.append(.decryptedKey(decryptedUserKey: decryptedUserKey))
        if let errorToThrow { throw errorToThrow }
    }

    func unlockWithPin(
        client: Client,
        userId: String,
        email: String,
        kdf: KeyDerivationParameters,
        encryptedPrivateKey: String,
        pin: String,
        pinProtectedUserKey: String
    ) async throws {
        calls.append(.pin(pin: pin, pinProtectedUserKey: pinProtectedUserKey))
        await beforePinUnlock?()
        if let errorToThrow { throw errorToThrow }
    }

    func decryptedUserKey(client: Client) async throws -> String {
        if let errorToThrow { throw errorToThrow }
        return decryptedUserKeyToReturn
    }
}

struct MockUnlockServiceError: Error {}
