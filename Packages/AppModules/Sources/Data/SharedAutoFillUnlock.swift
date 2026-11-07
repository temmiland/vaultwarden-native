import AutoFillContract
import Darwin
import Domain
import Foundation
import SecurityStorage

/// A system-wide monotonic clock shared by the app and AutoFill processes. Unlike wall time it
/// cannot be extended by changing the device clock, and it advances while the system sleeps.
public enum SharedSystemContinuousClock {
    public static var nowNanoseconds: UInt64 { clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) }
}

/// Key material, account metadata and an unlock epoch in ONE atomic Keychain value. Raw legacy
/// user-key records are deliberately not accepted; opening the app and unlocking replaces them.
public struct SharedAutoFillUnlock: Codable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public static let currentSchemaVersion = 4
    public let schemaVersion: Int
    public let proof: ExtensionUnlockProof
    public let accountInfo: SharedAccountInfo
    public let userKey: String
    fileprivate let bootSessionID: UUID
    fileprivate let timeoutLease: SharedAutoFillTimeoutLease?

    public init(
        userKey: String,
        accountInfo: SharedAccountInfo,
        revocationEpoch: UUID,
        authenticationID: UUID,
        bootSessionID: UUID? = nil
    ) throws {
        try Self.validate(accountInfo)
        guard !userKey.isEmpty, !accountInfo.userId.isEmpty, let base = accountInfo.serverBaseURL,
              base.host != nil, ["http", "https"].contains(base.scheme?.lowercased() ?? "")
        else { throw KeychainStoreError.decodeFailed }
        schemaVersion = Self.currentSchemaVersion
        self.accountInfo = accountInfo
        self.userKey = userKey
        self.bootSessionID = try bootSessionID ?? SystemBootSession.currentID()
        timeoutLease = nil
        proof = ExtensionUnlockProof(revocationEpoch: revocationEpoch, account: AutoFillAccountIdentity(
            userID: accountInfo.userId, serverBaseURL: base
        ), authenticationID: authenticationID)
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        proof = try values.decode(ExtensionUnlockProof.self, forKey: .proof)
        accountInfo = try values.decode(SharedAccountInfo.self, forKey: .accountInfo)
        userKey = try values.decode(String.self, forKey: .userKey)
        bootSessionID = try values.decode(UUID.self, forKey: .bootSessionID)
        timeoutLease = try values.decodeIfPresent(SharedAutoFillTimeoutLease.self, forKey: .timeoutLease)
        try Self.validate(accountInfo)
        guard schemaVersion == Self.currentSchemaVersion, proof.authenticationID != nil, !userKey.isEmpty,
              timeoutLease?.isWellFormed != false,
              !accountInfo.userId.isEmpty, let base = accountInfo.serverBaseURL, base.host != nil,
              ["http", "https"].contains(base.scheme?.lowercased() ?? ""),
              proof.account == AutoFillAccountIdentity(
                  userID: accountInfo.userId,
                  serverBaseURL: base
              )
        else { throw KeychainStoreError.decodeFailed }
    }

    fileprivate func applyingTimeoutPreference(
        _ preference: VaultTimeoutPreference?, at nowNanoseconds: UInt64
    ) throws -> SharedAutoFillUnlock {
        let lease: SharedAutoFillTimeoutLease?
        if let preference, preference.duration != .never {
            lease = try SharedAutoFillTimeoutLease(preference: preference, startedAtNanoseconds: nowNanoseconds)
        } else {
            lease = nil
        }
        return SharedAutoFillUnlock(
            proof: proof,
            accountInfo: accountInfo,
            userKey: userKey,
            bootSessionID: bootSessionID,
            timeoutLease: lease
        )
    }

    private init(
        proof: ExtensionUnlockProof,
        accountInfo: SharedAccountInfo,
        userKey: String,
        bootSessionID: UUID,
        timeoutLease: SharedAutoFillTimeoutLease?
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.proof = proof
        self.accountInfo = accountInfo
        self.userKey = userKey
        self.bootSessionID = bootSessionID
        self.timeoutLease = timeoutLease
    }

    public var description: String { "SharedAutoFillUnlock([REDACTED])" }
    public var debugDescription: String { description }

    private static func validate(_ info: SharedAccountInfo) throws {
        guard [0, 1].contains(info.kdfType), info.kdfIterations > 0,
              UInt64(info.kdfIterations) <= UInt64(UInt32.max) else { throw KeychainStoreError.decodeFailed }
        if info.kdfType == 1 {
            let memory = info.kdfMemory ?? 64
            let parallelism = info.kdfParallelism ?? 4
            guard memory > 0, parallelism > 0, UInt64(memory) <= UInt64(UInt32.max),
                  UInt64(parallelism) <= UInt64(UInt32.max) else { throw KeychainStoreError.decodeFailed }
        }
    }
}

fileprivate struct SharedAutoFillTimeoutLease: Codable, Sendable {
    let duration: VaultTimeoutPreference.Duration
    let action: VaultTimeoutPreference.Action
    let startedAtNanoseconds: UInt64
    let deadlineNanoseconds: UInt64

    init(preference: VaultTimeoutPreference, startedAtNanoseconds: UInt64) throws {
        guard let seconds = preference.duration.seconds, seconds >= 0 else { throw KeychainStoreError.decodeFailed }
        let durationNanoseconds = UInt64(seconds * 1_000_000_000)
        let (deadline, overflow) = startedAtNanoseconds.addingReportingOverflow(durationNanoseconds)
        guard !overflow else { throw KeychainStoreError.decodeFailed }
        duration = preference.duration
        action = preference.action
        self.startedAtNanoseconds = startedAtNanoseconds
        deadlineNanoseconds = deadline
    }

    var isWellFormed: Bool {
        guard let seconds = duration.seconds, seconds >= 0 else { return false }
        let durationNanoseconds = UInt64(seconds * 1_000_000_000)
        let (expectedDeadline, overflow) = startedAtNanoseconds.addingReportingOverflow(durationNanoseconds)
        return !overflow && expectedDeadline == deadlineNanoseconds
    }

    func isExpired(at nowNanoseconds: UInt64) -> Bool {
        nowNanoseconds < startedAtNanoseconds || nowNanoseconds >= deadlineNanoseconds
    }
}

public struct SharedAutoFillUnlockStore: Sendable {
    private let keychain: any KeychainStoring
    private let lockPolicy: SharedStoreLockPolicy
    private let containerURL: URL?
    private let nowNanoseconds: @Sendable () -> UInt64
    private let bootSessionID: @Sendable () throws -> UUID

    public init(
        keychain: any KeychainStoring,
        containerURL: URL? = nil,
        lockPolicy: SharedStoreLockPolicy = .appGroup,
        nowNanoseconds: @escaping @Sendable () -> UInt64 = { SharedSystemContinuousClock.nowNanoseconds },
        bootSessionID: @escaping @Sendable () throws -> UUID = { try SystemBootSession.currentID() }
    ) {
        self.keychain = keychain
        self.lockPolicy = lockPolicy
        self.containerURL = containerURL
        self.nowNanoseconds = nowNanoseconds
        self.bootSessionID = bootSessionID
    }

    public func load() throws -> SharedAutoFillUnlock? {
        try SharedTokenStoreLock.withExclusiveLock(containerURL: containerURL, policy: lockPolicy) { try loadUnderExistingLock(
        ) }
    }

    // Token compare-and-write uses this under the SAME process lock. Never recursively flock.
    func loadUnderExistingLock() throws -> SharedAutoFillUnlock? {
        guard let unlock = try loadCurrentUnlockUnderExistingLock() else { return nil }
        guard try unlock.bootSessionID == bootSessionID() else { return nil }
        guard unlock.timeoutLease?.isExpired(at: nowNanoseconds()) != true else { return nil }
        return unlock
    }

    private func loadCurrentUnlockUnderExistingLock() throws -> SharedAutoFillUnlock? {
        guard try AuthCleanupIntent.read(from: keychain) == nil else { return nil }
        let data: Foundation.Data
        do { data = try keychain.read(AutoFillStorageKeys.sharedUserKeyAccount) }
        catch KeychainStoreError.notFound { return nil }
        let unlock: SharedAutoFillUnlock
        do { unlock = try JSONDecoder().decode(SharedAutoFillUnlock.self, from: data) }
        catch { throw KeychainStoreError.decodeFailed }
        guard try readEpoch() == unlock.proof.revocationEpoch else { return nil }
        return unlock
    }

    /// Persists the selected policy when the app becomes inactive, or clears it when the app
    /// becomes active. An expired lease cannot be renewed without another unlock.
    public func setInactiveTimeout(_ preference: VaultTimeoutPreference?) throws {
        try SharedTokenStoreLock.withExclusiveLock(containerURL: containerURL, policy: lockPolicy) {
            guard let current = try loadCurrentUnlockUnderExistingLock() else { return }
            guard try current.bootSessionID == bootSessionID() else { return }
            let now = nowNanoseconds()
            guard current.timeoutLease?.isExpired(at: now) != true else { return }
            if let preference, preference.duration != .never, current.timeoutLease != nil { return }
            let updated = try current.applyingTimeoutPreference(preference, at: now)
            try keychain.write(JSONEncoder().encode(updated), for: AutoFillStorageKeys.sharedUserKeyAccount)
        }
    }

    /// Lets the main app apply the configured Lock or Log Out action after a process restart.
    /// AutoFill itself simply sees `load() == nil` when the deadline has expired.
    public func expiredTimeoutAction() throws -> VaultTimeoutPreference.Action? {
        try SharedTokenStoreLock.withExclusiveLock(containerURL: containerURL, policy: lockPolicy) {
            guard let unlock = try loadCurrentUnlockUnderExistingLock() else { return nil }
            // Even "never" only preserves an unlock within this system boot. Reboot requires
            // another app unlock; a configured logout action is retained when one was recorded.
            guard try unlock.bootSessionID == bootSessionID() else { return unlock.timeoutLease?.action ?? .lock }
            guard
                let lease = unlock.timeoutLease, lease.isExpired(at: nowNanoseconds()) else { return nil }
            return lease.action
        }
    }

    /// Capture BEFORE suspended derivation. Lock/logout rotates this version under the same
    /// process lock as publication; an old auth task cannot restore the revoked key afterwards.
    public func publicationEpoch() throws -> UUID {
        try SharedTokenStoreLock.withExclusiveLock(containerURL: containerURL, policy: lockPolicy) { try publicationEpochUnderExistingLock(
        ) }
    }

    func publicationEpochUnderExistingLock() throws -> UUID {
        try AuthCleanupIntent.requireNone(in: keychain)
        return try ensureEpoch()
    }

    public func save(
        userKey: String,
        accountInfo: SharedAccountInfo,
        authenticationID: UUID,
        ifRevocationEpochIs expected: UUID
    ) throws {
        try SharedTokenStoreLock.withExclusiveLock(containerURL: containerURL, policy: lockPolicy) {
            try saveUnderExistingLock(
                userKey: userKey,
                accountInfo: accountInfo,
                authenticationID: authenticationID,
                ifRevocationEpochIs: expected
            )
        }
    }

    func saveUnderExistingLock(
        userKey: String,
        accountInfo: SharedAccountInfo,
        authenticationID: UUID,
        ifRevocationEpochIs expected: UUID
    ) throws {
        try AuthCleanupIntent.requireNone(in: keychain)
        guard try readEpoch() == expected else { throw CancellationError() }
        let unlock = try SharedAutoFillUnlock(
            userKey: userKey,
            accountInfo: accountInfo,
            revocationEpoch: expected,
            authenticationID: authenticationID,
            bootSessionID: bootSessionID()
        )
        try keychain.write(JSONEncoder().encode(unlock), for: AutoFillStorageKeys.sharedUserKeyAccount)
    }

    public func revoke() throws {
        try SharedTokenStoreLock.withExclusiveLock(containerURL: containerURL, policy: lockPolicy) {
            try revokeUnderExistingLock()
        }
    }

    func revokeUnderExistingLock() throws {
        var firstError: Error?
        do { try keychain.write(
            Foundation.Data(UUID().uuidString.utf8),
            for: AutoFillStorageKeys.sharedUnlockEpochAccount
        ) } catch { firstError = error }
        for account in [AutoFillStorageKeys.sharedUserKeyAccount, AutoFillStorageKeys.legacySharedUserKeyAccount] {
            do { try keychain.remove(account) }
            catch { firstError = firstError ?? error }
        }
        if let firstError { throw firstError }
    }

    private func readEpoch() throws -> UUID? {
        let data: Foundation.Data
        do { data = try keychain.read(AutoFillStorageKeys.sharedUnlockEpochAccount) }
        catch KeychainStoreError.notFound { return nil }
        guard let raw = String(data: data, encoding: .utf8), let epoch = UUID(uuidString: raw) else {
            throw KeychainStoreError.decodeFailed
        }
        return epoch
    }

    private func ensureEpoch() throws -> UUID {
        if let epoch = try readEpoch() { return epoch }
        let epoch = UUID()
        try keychain.write(Foundation.Data(epoch.uuidString.utf8), for: AutoFillStorageKeys.sharedUnlockEpochAccount)
        return epoch
    }
}
