import Foundation
import SecurityStorage

/// In-memory stand-in for the real Keychain, so tests don't touch the actual macOS Keychain (which
/// would be slow, order-dependent, and require entitlements in a test bundle).
final class MockKeychainService: KeychainStoring, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    var accountsFailingWrites: Set<String> = []
    var accountsFailingReads: Set<String> = []
    var accountsCancellingReads: Set<String> = []
    var accountsFailingRemoval: Set<String> = []
    /// What protection level each item was written with, so tests can assert that key material
    /// actually asks for the OS-enforced biometric gate rather than merely claiming to.
    private(set) var protections: [String: KeychainProtection] = [:]

    func write(_ value: Data, for account: String, protection: KeychainProtection) throws {
        guard !accountsFailingWrites.contains(account) else { throw MockKeychainError.operationFailed }
        storage[account] = value
        protections[account] = protection
    }

    func read(_ account: String) throws -> Data {
        guard !accountsCancellingReads.contains(account) else { throw KeychainStoreError.interactionCancelled }
        guard !accountsFailingReads.contains(account) else { throw MockKeychainError.operationFailed }
        guard let value = storage[account] else { throw KeychainStoreError.notFound }
        return value
    }

    func remove(_ account: String) throws {
        guard !accountsFailingRemoval.contains(account) else { throw MockKeychainError.operationFailed }
        storage.removeValue(forKey: account)
    }
}

enum MockKeychainError: Error {
    case operationFailed
}
