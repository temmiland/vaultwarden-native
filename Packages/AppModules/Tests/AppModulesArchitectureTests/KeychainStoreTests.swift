import Foundation
import Security
@testable import SecurityStorage
import Testing

@Suite
struct KeychainStoreTests {
    @Test
    func existingItemsAreUpdatedWithoutUsingAdd() throws {
        let access = RecordingKeychainAccess(initialValue: Data("old".utf8), updateStatus: errSecSuccess)
        let store = DefaultKeychainStore(service: "tests", systemAccess: access)

        try store.write(Data("new".utf8), for: "token")

        #expect(access.value == Data("new".utf8))
        #expect(access.updateCalls == 1)
        #expect(access.addCalls == 0)
        #expect(access.removeCalls == 0)
    }

    @Test
    func failedUpdatePreservesTheExistingValue() {
        let access = RecordingKeychainAccess(initialValue: Data("old".utf8), updateStatus: errSecAuthFailed)
        let store = DefaultKeychainStore(service: "tests", systemAccess: access)

        #expect(throws: KeychainStoreError.authenticationFailed) {
            try store.write(Data("new".utf8), for: "token")
        }
        #expect(access.value == Data("old".utf8))
        #expect(access.addCalls == 0)
        #expect(access.removeCalls == 0)
    }

    @Test
    func missingItemsAreAddedAfterTheUpdateMiss() throws {
        let access = RecordingKeychainAccess(initialValue: nil, updateStatus: errSecItemNotFound)
        let store = DefaultKeychainStore(service: "tests", systemAccess: access)

        try store.write(Data("new".utf8), for: "token", protection: .biometryGated)

        #expect(access.value == Data("new".utf8))
        #expect(access.updateCalls == 1)
        #expect(access.addCalls == 1)
        #expect(access.lastProtection == .biometryGated)
    }

    @Test(arguments: [
        (errSecItemNotFound, KeychainStoreError.notFound),
        (errSecUserCanceled, .interactionCancelled),
        (errSecAuthFailed, .authenticationFailed),
        (errSecMissingEntitlement, .missingEntitlement),
        (errSecDecode, .decodeFailed),
    ])
    func readsClassifyRecoverableSecurityErrors(status: OSStatus, expected: KeychainStoreError) {
        let access = RecordingKeychainAccess(initialValue: nil, readStatus: status)
        let store = DefaultKeychainStore(service: "tests", systemAccess: access)

        #expect(throws: expected) { _ = try store.read("token") }
    }

    @Test
    func successfulReadWithoutDataIsClassifiedAsDecodeFailure() {
        let access = RecordingKeychainAccess(initialValue: nil, readStatus: errSecSuccess)
        let store = DefaultKeychainStore(service: "tests", systemAccess: access)

        #expect(throws: KeychainStoreError.decodeFailed) { _ = try store.read("token") }
    }

    @Test
    func inMemoryStoreMatchesMissingAndRoundTripSemantics() throws {
        let store = InMemoryKeychainStore()
        #expect(throws: KeychainStoreError.notFound) { _ = try store.read("token") }

        try store.write(Data("secret".utf8), for: "token")
        #expect(try store.read("token") == Data("secret".utf8))

        try store.remove("token")
        #expect(throws: KeychainStoreError.notFound) { _ = try store.read("token") }
    }
}

private final class RecordingKeychainAccess: KeychainSystemAccess, @unchecked Sendable {
    private let lock = NSLock()
    private let configuredUpdateStatus: OSStatus
    private let configuredReadStatus: OSStatus?
    private(set) var value: Data?
    private(set) var updateCalls = 0
    private(set) var addCalls = 0
    private(set) var removeCalls = 0
    private(set) var lastProtection: KeychainProtection?

    init(initialValue: Data?, updateStatus: OSStatus = errSecSuccess, readStatus: OSStatus? = nil) {
        value = initialValue
        configuredUpdateStatus = updateStatus
        configuredReadStatus = readStatus
    }

    func update(_: KeychainItem, value: Data, protection: KeychainProtection) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        updateCalls += 1
        lastProtection = protection
        guard configuredUpdateStatus == errSecSuccess else { return configuredUpdateStatus }
        self.value = value
        return errSecSuccess
    }

    func add(_: KeychainItem, value: Data, protection: KeychainProtection) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        addCalls += 1
        lastProtection = protection
        self.value = value
        return errSecSuccess
    }

    func read(_: KeychainItem, authenticationContext _: KeychainAuthenticationContext?) -> KeychainReadResponse {
        lock.lock()
        defer { lock.unlock() }
        return KeychainReadResponse(
            status: configuredReadStatus ?? (value == nil ? errSecItemNotFound : errSecSuccess),
            data: value
        )
    }

    func remove(_: KeychainItem) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        removeCalls += 1
        value = nil
        return errSecSuccess
    }
}
