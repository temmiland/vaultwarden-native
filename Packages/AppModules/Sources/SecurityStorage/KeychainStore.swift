import Foundation
import Security

/// The two protection levels used by the app. `afterFirstUnlock` is deliberately absent: vault
/// keys and tokens must not remain readable while an iPhone or iPad is locked.
public enum KeychainProtection: Sendable, Equatable {
    case whenUnlocked
    case biometryGated
}

/// A classified Keychain failure. Consumers must distinguish a missing value from a cancelled
/// biometric prompt or a broken entitlement; treating all of them as `nil` loses recovery paths.
public enum KeychainStoreError: Error, Sendable, Equatable {
    case notFound
    case interactionCancelled
    case authenticationFailed
    case missingEntitlement
    case decodeFailed
    case operationFailed(status: Int32)
}

public protocol KeychainStoring: Sendable {
    /// Replaces an existing item in place, or adds it if it does not exist. It never deletes a
    /// previous value before the replacement has been accepted by the Keychain.
    func write(_ value: Data, for account: String, protection: KeychainProtection) throws
    func read(_ account: String) throws -> Data
    func remove(_ account: String) throws
}

public extension KeychainStoring {
    func write(_ value: Data, for account: String) throws {
        try write(value, for: account, protection: .whenUnlocked)
    }
}

struct KeychainItem: Sendable, Equatable {
    let service: String
    let account: String
    let accessGroup: String?
}

struct KeychainReadResponse: Sendable {
    let status: OSStatus
    let data: Data?
}

/// Kept internal so the production store can be verified without placing test-only switches in
/// Keychain queries. Implementations must return the OS status verbatim; classification happens in
/// one place, above the Security framework boundary.
protocol KeychainSystemAccess: Sendable {
    func update(_ item: KeychainItem, value: Data, protection: KeychainProtection) -> OSStatus
    func add(_ item: KeychainItem, value: Data, protection: KeychainProtection) -> OSStatus
    func read(_ item: KeychainItem) -> KeychainReadResponse
    func remove(_ item: KeychainItem) -> OSStatus
}

private struct SystemKeychainAccess: KeychainSystemAccess {
    func update(_ item: KeychainItem, value: Data, protection: KeychainProtection) -> OSStatus {
        guard let attributes = attributes(value: value, protection: protection) else { return errSecParam }
        return SecItemUpdate(query(for: item) as CFDictionary, attributes as CFDictionary)
    }

    func add(_ item: KeychainItem, value: Data, protection: KeychainProtection) -> OSStatus {
        guard let attributes = attributes(value: value, protection: protection) else { return errSecParam }
        var addQuery = query(for: item)
        for (key, value) in attributes {
            addQuery[key] = value
        }
        return SecItemAdd(addQuery as CFDictionary, nil)
    }

    func read(_ item: KeychainItem) -> KeychainReadResponse {
        var readQuery = query(for: item)
        readQuery[kSecReturnData as String] = true
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(readQuery as CFDictionary, &result)
        return KeychainReadResponse(status: status, data: result as? Data)
    }

    func remove(_ item: KeychainItem) -> OSStatus {
        SecItemDelete(query(for: item) as CFDictionary)
    }

    private func query(for item: KeychainItem) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: item.service,
            kSecAttrAccount as String: item.account,
        ]
        if let accessGroup = item.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    private func attributes(value: Data, protection: KeychainProtection) -> [String: Any]? {
        var attributes: [String: Any] = [kSecValueData as String: value]
        switch protection {
        case .whenUnlocked:
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        case .biometryGated:
            var creationError: Unmanaged<CFError>?
            guard let accessControl = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                [.biometryCurrentSet, .or, .devicePasscode],
                &creationError
            ) else {
                return nil
            }
            attributes[kSecAttrAccessControl as String] = accessControl
        }
        return attributes
    }
}

/// The production Keychain adapter for a single service/access group. It has no `Data?` read API:
/// callers must intentionally decide how to recover from every classified failure.
public struct DefaultKeychainStore: KeychainStoring {
    private let itemPrefix: KeychainItem
    private let systemAccess: any KeychainSystemAccess

    public init(service: String, accessGroup: String? = nil) {
        itemPrefix = KeychainItem(service: service, account: "", accessGroup: accessGroup)
        systemAccess = SystemKeychainAccess()
    }

    init(service: String, accessGroup: String? = nil, systemAccess: any KeychainSystemAccess) {
        itemPrefix = KeychainItem(service: service, account: "", accessGroup: accessGroup)
        self.systemAccess = systemAccess
    }

    public func write(_ value: Data, for account: String, protection: KeychainProtection) throws {
        let item = item(for: account)
        let updateStatus = systemAccess.update(item, value: value, protection: protection)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            let addStatus = systemAccess.add(item, value: value, protection: protection)
            guard addStatus == errSecSuccess else { throw error(for: addStatus) }
        default:
            // Deliberately do not fall back to delete-then-add. If the update fails, the previous
            // token/key remains intact, which is safer than an attempted replacement that loses it.
            throw error(for: updateStatus)
        }
    }

    public func read(_ account: String) throws -> Data {
        let response = systemAccess.read(item(for: account))
        guard response.status == errSecSuccess else { throw error(for: response.status) }
        guard let data = response.data else { throw KeychainStoreError.decodeFailed }
        return data
    }

    public func remove(_ account: String) throws {
        let status = systemAccess.remove(item(for: account))
        guard status == errSecSuccess || status == errSecItemNotFound else { throw error(for: status) }
    }

    private func item(for account: String) -> KeychainItem {
        KeychainItem(service: itemPrefix.service, account: account, accessGroup: itemPrefix.accessGroup)
    }

    private func error(for status: OSStatus) -> KeychainStoreError {
        switch status {
        case errSecItemNotFound:
            .notFound
        case errSecUserCanceled:
            .interactionCancelled
        case errSecAuthFailed:
            .authenticationFailed
        case errSecMissingEntitlement:
            .missingEntitlement
        case errSecDecode:
            .decodeFailed
        default:
            .operationFailed(status: Int32(status))
        }
    }
}

/// A locked, deterministic implementation for feature and repository tests. It provides the same
/// missing-item semantics as the real store but intentionally does not emulate OS biometric UI.
public final class InMemoryKeychainStore: KeychainStoring, @unchecked Sendable {
    private struct Entry {
        let value: Data
        let protection: KeychainProtection
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    public init() {}

    public func write(_ value: Data, for account: String, protection: KeychainProtection) throws {
        lock.lock()
        entries[account] = Entry(value: value, protection: protection)
        lock.unlock()
    }

    public func read(_ account: String) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[account] else { throw KeychainStoreError.notFound }
        return entry.value
    }

    public func remove(_ account: String) throws {
        lock.lock()
        entries.removeValue(forKey: account)
        lock.unlock()
    }
}
