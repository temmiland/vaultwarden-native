import AutoFillContract
@testable import Data
import Domain
import Foundation
import SecurityStorage
import Testing

/// Pure store fixtures. No SDK initialization, real Keychain or signed app-group access.
@Suite
struct SharedAutoFillUnlockTests {
    @Test
    func grantContainsOneCoherentAccountAndIsRenewedOnEveryUnlock() throws {
        let keychain = UnlockKeychain()
        let store = SharedAutoFillUnlockStore(keychain: keychain, lockPolicy: .processOnly)
        let epoch = try store.publicationEpoch()
        try store.save(
            userKey: "fake-test-key",
            accountInfo: account(),
            authenticationID: UUID(),
            ifRevocationEpochIs: epoch
        )
        let first = try #require(try store.load())
        #expect(first.accountInfo.userId == first.proof.account.userID)
        #expect(first.userKey == "fake-test-key")
        #expect(!String(describing: first).contains("fake-test-key"))
        #expect(!String(reflecting: first).contains("fake-test-key"))
        #expect(!String(reflecting: first.accountInfo).contains("test@example.com"))
        try store.save(
            userKey: "fake-test-key",
            accountInfo: account(),
            authenticationID: UUID(),
            ifRevocationEpochIs: epoch
        )
        let next = try #require(try store.load())
        #expect(next.proof.unlockID != first.proof.unlockID)
    }

    @Test
    func aPreLockPublicationCannotRestoreTheGrantAfterReunlock() throws {
        let store = SharedAutoFillUnlockStore(keychain: UnlockKeychain(), lockPolicy: .processOnly)
        let oldEpoch = try store.publicationEpoch()
        try store.revoke()
        let newEpoch = try store.publicationEpoch()
        #expect(oldEpoch != newEpoch)
        try store.save(
            userKey: "fake-new-key",
            accountInfo: account(),
            authenticationID: UUID(),
            ifRevocationEpochIs: newEpoch
        )
        #expect(throws: CancellationError.self) {
            try store.save(
                userKey: "fake-old-key",
                accountInfo: account(),
                authenticationID: UUID(),
                ifRevocationEpochIs: oldEpoch
            )
        }
        #expect(try store.load()?.userKey == "fake-new-key")
    }

    @Test
    func epochRevocationDeniesAnOldGrantEvenWhenKeyDeletionFails() throws {
        let keychain = UnlockKeychain()
        let store = SharedAutoFillUnlockStore(keychain: keychain, lockPolicy: .processOnly)
        try store.save(
            userKey: "fake-test-key",
            accountInfo: account(),
            authenticationID: UUID(),
            ifRevocationEpochIs: store.publicationEpoch()
        )
        keychain.failDeletion = true
        #expect(throws: UnlockKeychain.Failure.self) { try store.revoke() }
        #expect(try store.load() == nil)
        #expect(try keychain.read(AutoFillStorageKeys.sharedUserKeyAccount).isEmpty == false)
    }

    @Test
    func failedEpochRotationStillAttemptsKeyRemoval() throws {
        let keychain = UnlockKeychain()
        let store = SharedAutoFillUnlockStore(keychain: keychain, lockPolicy: .processOnly)
        try store.save(
            userKey: "fake-test-key",
            accountInfo: account(),
            authenticationID: UUID(),
            ifRevocationEpochIs: store.publicationEpoch()
        )
        keychain.failEpochWrites = true
        #expect(throws: UnlockKeychain.Failure.self) { try store.revoke() }
        #expect(try store.load() == nil)
    }

    @Test
    func systemBootIdentityIsStableAcrossIndependentReads() throws {
        #expect(try SystemBootSession.currentID() == SystemBootSession.currentID())
    }

    @Test(arguments: [UInt64(1), 20_000_000_000, 80_000_000_000])
    func differentBootDeniesEvenOverlappingUptime(now: UInt64) throws {
        let keychain = UnlockKeychain()
        let oldBoot = UUID(), newBoot = UUID()
        let original = SharedAutoFillUnlockStore(
            keychain: keychain, lockPolicy: .processOnly,
            nowNanoseconds: { 10_000_000_000 }, bootSessionID: { oldBoot }
        )
        try original.save(
            userKey: "fake-test-key",
            accountInfo: account(),
            authenticationID: UUID(),
            ifRevocationEpochIs: original.publicationEpoch()
        )
        try original.setInactiveTimeout(.init(duration: .oneMinute, action: .logOut))
        let recorded = try keychain.read(AutoFillStorageKeys.sharedUserKeyAccount)
        let restarted = SharedAutoFillUnlockStore(
            keychain: keychain, lockPolicy: .processOnly,
            nowNanoseconds: { now }, bootSessionID: { newBoot }
        )
        #expect(try restarted.load() == nil)
        #expect(try restarted.expiredTimeoutAction() == .logOut)
        try restarted.setInactiveTimeout(nil)
        #expect(try keychain.read(AutoFillStorageKeys.sharedUserKeyAccount) == recorded)
    }

    @Test
    func sameBootProcessRestartPreservesUnexpiredLeaseButNeverStillRequiresUnlockAfterReboot() throws {
        let keychain = UnlockKeychain()
        let boot = UUID(), anotherBoot = UUID()
        let original = SharedAutoFillUnlockStore(
            keychain: keychain, lockPolicy: .processOnly,
            nowNanoseconds: { 10_000_000_000 }, bootSessionID: { boot }
        )
        try original.save(
            userKey: "fake-test-key",
            accountInfo: account(),
            authenticationID: UUID(),
            ifRevocationEpochIs: original.publicationEpoch()
        )
        try original.setInactiveTimeout(.init(duration: .oneMinute))
        let restarted = SharedAutoFillUnlockStore(
            keychain: keychain, lockPolicy: .processOnly,
            nowNanoseconds: { 20_000_000_000 }, bootSessionID: { boot }
        )
        #expect(try restarted.load() != nil)
        try restarted.setInactiveTimeout(.init(duration: .never))
        #expect(try restarted.expiredTimeoutAction() == nil)
        let afterReboot = SharedAutoFillUnlockStore(
            keychain: keychain, lockPolicy: .processOnly,
            nowNanoseconds: { 20_000_000_000 }, bootSessionID: { anotherBoot }
        )
        #expect(try afterReboot.load() == nil)
        #expect(try afterReboot.expiredTimeoutAction() == .lock)
    }

    @Test
    func unavailableBootIdentityDeniesAccessAndPublicationWithoutDeletingData() throws {
        let keychain = UnlockKeychain()
        let good = SharedAutoFillUnlockStore(keychain: keychain, lockPolicy: .processOnly)
        let epoch = try good.publicationEpoch()
        try good.save(
            userKey: "fake-test-key",
            accountInfo: account(),
            authenticationID: UUID(),
            ifRevocationEpochIs: epoch
        )
        let recorded = try keychain.read(AutoFillStorageKeys.sharedUserKeyAccount)
        let unavailable = SharedAutoFillUnlockStore(
            keychain: keychain, lockPolicy: .processOnly,
            bootSessionID: { throw SystemBootSessionError.unavailable }
        )
        #expect(throws: SystemBootSessionError.unavailable) { try unavailable.load() }
        #expect(throws: SystemBootSessionError.unavailable) { try unavailable.setInactiveTimeout(nil) }
        #expect(throws: SystemBootSessionError.unavailable) { try unavailable.expiredTimeoutAction() }
        #expect(throws: SystemBootSessionError.unavailable) {
            try unavailable.save(
                userKey: "replacement-fake-key",
                accountInfo: account(),
                authenticationID: UUID(),
                ifRevocationEpochIs: epoch
            )
        }
        #expect(try keychain.read(AutoFillStorageKeys.sharedUserKeyAccount) == recorded)
    }

    @Test
    func preBootBindingSchemaIsRefusedWithoutDeletingTheEnvelope() throws {
        let keychain = UnlockKeychain()
        let store = SharedAutoFillUnlockStore(keychain: keychain, lockPolicy: .processOnly)
        try store.save(
            userKey: "fake-test-key",
            accountInfo: account(),
            authenticationID: UUID(),
            ifRevocationEpochIs: store.publicationEpoch()
        )
        var old = try #require(try JSONSerialization.jsonObject(with: keychain.read(
            AutoFillStorageKeys.sharedUserKeyAccount
        )) as? [String: Any])
        old["schemaVersion"] = 3
        old.removeValue(forKey: "bootSessionID")
        let data = try JSONSerialization.data(withJSONObject: old)
        try keychain.write(data, for: AutoFillStorageKeys.sharedUserKeyAccount)
        #expect(throws: KeychainStoreError.decodeFailed) { try store.load() }
        #expect(try keychain.read(AutoFillStorageKeys.sharedUserKeyAccount) == data)
    }

    @Test
    func extensionGrantExpiresOnTheSharedMonotonicClockAndPreservesItsAction() throws {
        let keychain = UnlockKeychain()
        let clock = TestMonotonicClock(now: 10_000_000_000)
        let store = SharedAutoFillUnlockStore(
            keychain: keychain,
            lockPolicy: .processOnly,
            nowNanoseconds: { clock.now }
        )
        try store.save(
            userKey: "fake-test-key",
            accountInfo: account(),
            authenticationID: UUID(),
            ifRevocationEpochIs: store.publicationEpoch()
        )

        try store.setInactiveTimeout(VaultTimeoutPreference(duration: .oneMinute, action: .logOut))
        #expect(try store.load()?.userKey == "fake-test-key")
        clock.advance(60_000_000_000)

        #expect(try store.load() == nil)
        #expect(try store.expiredTimeoutAction() == .logOut)
    }

    @Test
    func continuousClockRollbackFailsClosedAndExpiredLeaseCannotBeCleared() throws {
        let keychain = UnlockKeychain()
        let clock = TestMonotonicClock(now: 50_000_000_000)
        let store = SharedAutoFillUnlockStore(
            keychain: keychain,
            lockPolicy: .processOnly,
            nowNanoseconds: { clock.now }
        )
        try store.save(
            userKey: "fake-test-key",
            accountInfo: account(),
            authenticationID: UUID(),
            ifRevocationEpochIs: store.publicationEpoch()
        )
        try store.setInactiveTimeout(VaultTimeoutPreference(duration: .fiveMinutes, action: .lock))
        clock.now = 1

        #expect(try store.load() == nil)
        try store.setInactiveTimeout(nil)
        #expect(try store.expiredTimeoutAction() == .lock)
    }

    @Test
    func activeAppAndNeverPreferenceClearAnUnexpiredLease() throws {
        let keychain = UnlockKeychain()
        let clock = TestMonotonicClock(now: 100_000_000_000)
        let store = SharedAutoFillUnlockStore(
            keychain: keychain,
            lockPolicy: .processOnly,
            nowNanoseconds: { clock.now }
        )
        try store.save(
            userKey: "fake-test-key",
            accountInfo: account(),
            authenticationID: UUID(),
            ifRevocationEpochIs: store.publicationEpoch()
        )
        try store.setInactiveTimeout(VaultTimeoutPreference(duration: .oneMinute))
        try store.setInactiveTimeout(VaultTimeoutPreference(duration: .never))

        #expect(try store.load()?.userKey == "fake-test-key")
        #expect(try store.expiredTimeoutAction() == nil)
    }

    @Test
    func repeatedInactiveNotificationsDoNotExtendTheSharedDeadline() throws {
        let keychain = UnlockKeychain()
        let clock = TestMonotonicClock(now: 200_000_000_000)
        let store = SharedAutoFillUnlockStore(
            keychain: keychain,
            lockPolicy: .processOnly,
            nowNanoseconds: { clock.now }
        )
        try store.save(
            userKey: "fake-test-key",
            accountInfo: account(),
            authenticationID: UUID(),
            ifRevocationEpochIs: store.publicationEpoch()
        )
        let preference = VaultTimeoutPreference(duration: .oneMinute, action: .lock)
        try store.setInactiveTimeout(preference)
        clock.advance(30_000_000_000)
        try store.setInactiveTimeout(preference)
        clock.advance(30_000_000_000)

        #expect(try store.load() == nil)
        #expect(try store.expiredTimeoutAction() == .lock)
    }

    @Test
    func legacyKeysFutureSchemasAndMismatchedAccountMetadataFailClosed() throws {
        let keychain = UnlockKeychain()
        let store = SharedAutoFillUnlockStore(keychain: keychain, lockPolicy: .processOnly)
        try keychain.write(Data("fake-legacy-raw-key".utf8), for: AutoFillStorageKeys.sharedUserKeyAccount)
        #expect(throws: KeychainStoreError.self) { try store.load() }
        let epoch = try store.publicationEpoch()
        try store.save(
            userKey: "fake-test-key",
            accountInfo: account(),
            authenticationID: UUID(),
            ifRevocationEpochIs: epoch
        )
        let valid = try keychain.read(AutoFillStorageKeys.sharedUserKeyAccount)
        var object = try #require(try JSONSerialization.jsonObject(with: valid) as? [String: Any])
        object["schemaVersion"] = 99
        try keychain.write(JSONSerialization.data(withJSONObject: object), for: AutoFillStorageKeys.sharedUserKeyAccount)
        #expect(throws: KeychainStoreError.self) { try store.load() }
        object["schemaVersion"] = SharedAutoFillUnlock.currentSchemaVersion
        var metadata = try #require(object["accountInfo"] as? [String: Any])
        metadata["userId"] = "different-account"
        object["accountInfo"] = metadata
        try keychain.write(JSONSerialization.data(withJSONObject: object), for: AutoFillStorageKeys.sharedUserKeyAccount)
        #expect(throws: KeychainStoreError.self) { try store.load() }
    }

    @Test
    func malformedKDFCannotReachATrappingSDKIntegerConversion() throws {
        let store = SharedAutoFillUnlockStore(keychain: UnlockKeychain(), lockPolicy: .processOnly)
        let invalid = SharedAccountInfo(
            userId: "account-1",
            email: "test@example.com",
            kdfType: 1,
            kdfIterations: -1,
            kdfMemory: 64,
            kdfParallelism: 4,
            encryptedPrivateKey: "fake-wrapped-key",
            serverBaseURL: URL(string: "https://vault.example.com")!
        )
        #expect(throws: KeychainStoreError.self) {
            try store.save(
                userKey: "fake-test-key",
                accountInfo: invalid,
                authenticationID: UUID(),
                ifRevocationEpochIs: store.publicationEpoch()
            )
        }
    }

    @Test
    func storesWithoutAnInjectedContainerFailBeforeTouchingKeychain() throws {
        let keychain = UnlockKeychain()
        let grants = SharedAutoFillUnlockStore(keychain: keychain)
        let tokens = SharedTokenStore(keychain: keychain)

        #expect(throws: CrossProcessFileLockError.missingContainer) { _ = try grants.publicationEpoch() }
        #expect(throws: CrossProcessFileLockError.missingContainer) { _ = try grants.load() }
        #expect(throws: CrossProcessFileLockError.missingContainer) { _ = try tokens.load() }
        #expect(throws: CrossProcessFileLockError.missingContainer) {
            try tokens.save(
                SharedTokens(accessToken: "fake-access", refreshToken: "fake-refresh", expiresAt: .distantFuture)
            )
        }
        #expect(keychain.readCount == 0)
        #expect(keychain.writeCount == 0)
    }

    @Test
    func injectedContainerUsesTheExistingLockAndWireNamesForBothStores() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("shared-auth-storage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let keychain = UnlockKeychain()
        let grants = SharedAutoFillUnlockStore(keychain: keychain, containerURL: directory)
        let tokens = SharedTokenStore(keychain: keychain, containerURL: directory)
        let info = account()
        let scope = TokenScope(account: TokenAccountIdentity(userID: info.userId, serverBaseURL: info.serverBaseURL!))
        try grants.save(
            userKey: "fake-test-key",
            accountInfo: info,
            authenticationID: scope.authenticationID,
            ifRevocationEpochIs: grants.publicationEpoch()
        )
        let proof = try #require(try grants.load()?.proof)
        try tokens.save(SharedTokens(
            accessToken: "fake-access",
            refreshToken: "fake-refresh",
            expiresAt: .distantFuture,
            scope: scope,
            unlockID: proof.unlockID
        ))
        #expect(try tokens.load(requiringUnlockProof: proof)?.accessToken == "fake-access")
        let lockURL = directory.appendingPathComponent(".vaultwarden-token-store.lock")
        let attributes = try FileManager.default.attributesOfItem(atPath: lockURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [lockURL.lastPathComponent])
        let envelope = try #require(try JSONSerialization.jsonObject(with:
            keychain.read("auth.sharedAutofillUnlock.v2")) as? [String: Any])
        #expect(envelope["schemaVersion"] as? Int == SharedAutoFillUnlock.currentSchemaVersion)
        #expect(envelope["accountInfo"] != nil)
        #expect(envelope["userKey"] as? String == "fake-test-key")
        #expect(envelope["proof"] != nil)
        #expect(try keychain.read("auth.sharedTokens.v2").isEmpty == false)

        try grants.revoke()
        #expect(try tokens.load(requiringUnlockProof: proof) == nil)
        #expect(throws: CancellationError.self) {
            try tokens.withAuthorizedCacheMutation(requiring: proof) { Issue.record("Revoked proof authorized a write") }
        }
    }

    private func account() -> SharedAccountInfo {
        SharedAccountInfo(
            userId: "account-1",
            email: "test@example.com",
            kdfType: 0,
            kdfIterations: 600_000,
            kdfMemory: nil,
            kdfParallelism: nil,
            encryptedPrivateKey: "fake-wrapped-key",
            serverBaseURL: URL(string: "https://vault.example.com")!
        )
    }
}

private final class TestMonotonicClock: @unchecked Sendable {
    var now: UInt64
    init(now: UInt64) { self.now = now }
    func advance(_ nanoseconds: UInt64) { now += nanoseconds }
}

private final class UnlockKeychain: KeychainStoring, @unchecked Sendable {
    struct Failure: Error {}
    private var values: [String: Data] = [:]
    private(set) var readCount = 0
    private(set) var writeCount = 0
    var failEpochWrites = false
    var failDeletion = false
    func write(_ value: Data, for account: String, protection: SecurityStorage.KeychainProtection) throws {
        writeCount += 1
        if failEpochWrites && account == AutoFillStorageKeys.sharedUnlockEpochAccount { throw Failure() }
        values[account] = value
    }

    func read(_ account: String) throws -> Data {
        readCount += 1
        guard let value = values[account] else { throw KeychainStoreError.notFound }
        return value
    }

    func remove(_ account: String) throws {
        if failDeletion { throw Failure() }
        values.removeValue(forKey: account)
    }
}
