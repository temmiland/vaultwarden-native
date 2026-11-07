import AutoFillContract
import Domain
import Foundation
import SecurityStorage

/// Existing private/shared credential keys. Data owns persistence; key names and schemas stay
/// unchanged so this module migration does not move or reinterpret the user's credentials.
private enum AuthKeychainKey {
    static let deviceIdentifier = "auth.deviceIdentifier"
    static let account = "auth.account"
    static let tokens = "auth.tokens"
    static let biometricUserKey = "auth.biometricUserKey"
    static let pinProtectedUserKey = "auth.pinProtectedUserKey"
    /// Consecutive failed PIN attempts. In the Keychain rather than UserDefaults specifically so it
    /// can't be reset by anyone who can write app preferences - the counter is a security control,
    /// not a preference.
    static let pinFailureCount = "auth.pinFailureCount"
    // Defined in AutoFillContract, not here - the AutoFill extension reads these same keys and
    // doesn't depend on AuthFeature.
    static let sharedAccountInfo = AutoFillStorageKeys.sharedAccountInfoAccount
}

public struct PinUnlockState: Equatable, Sendable {
    public let isEnabled: Bool
    public let failureCount: Int
}

/// Nonsecret compare-and-commit authority captured before a fresh password/2FA attempt suspends.
/// Refresh rotation within the same lineage is allowed; lock/logout or a new sign-in is not.
struct FreshLoginCommitProof: Sendable {
    let publicationEpoch: UUID
    let previousScope: TokenScope?
}

struct AuthSessionCommit: Sendable {
    let session: PersistedAuthSession
    let publicationEpoch: UUID
}

/// Data-owned credential persistence and compare-and-commit authority over injected stores: the
/// stable per-install device id, the signed-in account's public-ish metadata + wrapped keys, the
/// current token pair, and (optionally) the user's decrypted vault key for biometric unlock.
///
/// Security note: the decrypted vault key stored under `biometricUserKey` is written with
/// `SecurityStorage.KeychainProtection.biometryGated`, so the biometric check is enforced by the
/// OS at read time (and the item self-invalidates if the device's biometric enrollment changes)
/// rather than only by the `LAContext` evaluation the unlock/enrollment flows also
/// perform. Everything else uses `.whenUnlocked`, never `afterFirstUnlock` - on iOS the latter
/// stays readable while the device sits locked, which is exactly the window that matters for a
/// vault key.
public final class AuthCredentialStore: AuthSessionLifecycleStore {
    private let keychain: any SecurityStorage.KeychainStoring
    /// Scoped to `SharedAppGroup.keychainAccessGroup` - the AutoFill extension (a separate
    /// sandboxed process) reads the same key from here to unlock its own `Client` without
    /// prompting for the master password again.
    private let sharedKeychain: any SecurityStorage.KeychainStoring
    private let sharedLockPolicy: SharedStoreLockPolicy
    private let sharedContainerURL: URL?

    public init(
        keychain: any SecurityStorage.KeychainStoring,
        sharedKeychain: any SecurityStorage.KeychainStoring,
        sharedLockPolicy: SharedStoreLockPolicy = .appGroup,
        sharedContainerURL: URL? = nil
    ) {
        self.keychain = keychain
        self.sharedKeychain = sharedKeychain
        self.sharedLockPolicy = sharedLockPolicy
        self.sharedContainerURL = sharedContainerURL
    }

    // MARK: Device identifier

    public func deviceIdentifier() throws -> String {
        if let data = try keychain.get(AuthKeychainKey.deviceIdentifier) {
            if let value = String(data: data, encoding: .utf8), UUID(uuidString: value) != nil {
                return value
            }
        }
        // A missing or malformed value can be repaired safely, but the replacement must be
        // committed before callers use it. Actual Keychain read failures propagate above.
        let generated = UUID().uuidString
        try keychain.write(Data(generated.utf8), for: AuthKeychainKey.deviceIdentifier)
        return generated
    }

    private var sessions: PrivateAuthSessionStore { PrivateAuthSessionStore(keychain: keychain) }
    private var sharedTokens: SharedTokenStore {
        SharedTokenStore(keychain: sharedKeychain, containerURL: sharedContainerURL, lockPolicy: sharedLockPolicy)
    }

    func tokenPersistence(requiringEpoch epoch: UUID?) -> AppTokenPersistence {
        AppTokenPersistence(sessions: sessions, shared: sharedTokens, authorizationEpoch: epoch)
    }

    var tokenPersistence: AppTokenPersistence { AppTokenPersistence(sessions: sessions, shared: sharedTokens) }

    // MARK: Atomic account/token authority

    public func loadSession() throws -> PersistedAuthSession? {
        try sharedTokens.withTransaction { transaction in
            try transaction.requireNoCleanup()
            return try sessions.load()
        }
    }

    /// Lifecycle restore authorizes only the atomic record, never legacy split credentials.
    public func restoreAccount() throws -> AccountSession? {
        guard let session = try loadSession() else { return nil }
        return try AccountSession(storedAccount: session.account)
    }

    public func loadAccount() throws -> StoredAuthAccount? {
        if let session = try loadSession() { return session.account }
        // Legacy metadata is display/recovery-only. Its separately stored tokens are NOT imported.
        guard let data = try keychain.get(AuthKeychainKey.account) else { return nil }
        do { return try JSONDecoder().decode(StoredAuthAccount.self, from: data) }
        catch { throw SecurityStorage.KeychainStoreError.decodeFailed }
    }

    /// Enrollment/settings updates preserve the existing lineage and token pair. A stale screen
    /// cannot replace a different account or different wrapped keys.
    func save(account: StoredAuthAccount) throws {
        try sharedTokens.withTransaction { transaction in
            try transaction.requireNoCleanup()
            guard let session = try sessions.load() else {
                try keychain.write(JSONEncoder().encode(account), for: AuthKeychainKey.account)
                return
            }
            guard session.account.tokenIdentity == account.tokenIdentity,
                  session.account.encryptedUserKey == account.encryptedUserKey,
                  session.account.encryptedPrivateKey == account.encryptedPrivateKey
            else { throw CancellationError() }
            try sessions.save(PersistedAuthSession(account: account, scope: session.scope, tokens: session.tokens))
        }
    }

    func freshLoginCommitProof() throws -> FreshLoginCommitProof {
        try sharedTokens.withTransaction { transaction in
            FreshLoginCommitProof(
                publicationEpoch: try transaction.publicationEpoch(),
                previousScope: try sessions.load()?.scope
            )
        }
    }

    func validateFreshLoginAuthority(_ proof: FreshLoginCommitProof) throws {
        try sharedTokens.withTransaction { transaction in
            try Task.checkCancellation()
            guard try transaction.publicationEpoch() == proof.publicationEpoch,
                  try sessions.load()?.scope == proof.previousScope else { throw CancellationError() }
        }
    }

    /// Capture at returning-unlock start and compare after every suspended step. The sign-in
    /// scope alone survives lock; the epoch is what denies work from the preceding unlock.
    public func returningUnlockEpoch(requiringScope scope: TokenScope, expectedEpoch: UUID? = nil) throws -> UUID {
        try sharedTokens.withTransaction { transaction in
            try Task.checkCancellation()
            _ = try currentSession(requiringScope: scope)
            let epoch = try transaction.publicationEpoch()
            guard expectedEpoch == nil || epoch == expectedEpoch else { throw CancellationError() }
            return epoch
        }
    }

    /// Only the completed password/2FA flow calls this. Never merge a fresh login with old shared
    /// tokens, even for the same account. Revoke the old extension capability before committing.
    @discardableResult
    func saveSession(
        account: StoredAuthAccount,
        tokens: TokenPair,
        requiring proof: FreshLoginCommitProof
    ) throws -> AuthSessionCommit {
        try sharedTokens.withTransaction { transaction in
            try Task.checkCancellation()
            guard try transaction.publicationEpoch() == proof.publicationEpoch,
                  try sessions.load()?.scope == proof.previousScope else { throw CancellationError() }
            let record = PersistedAuthSession(
                account: account,
                scope: TokenScope(account: account.tokenIdentity),
                tokens: tokens.versioned(generation: 1)
            )
            try sessions.validate(record)
            try transaction.revokeCapabilities()
            let committedEpoch = try transaction.publicationEpoch()
            // Prevent an old biometric/PIN key from being used with the freshly signed-in account.
            var cleanupError: Error?
            for key in [AuthKeychainKey.biometricUserKey, AuthKeychainKey.pinProtectedUserKey,
                        AuthKeychainKey.pinFailureCount] {
                do { try keychain.remove(key) }
                catch { cleanupError = cleanupError ?? error }
            }
            if let cleanupError { throw cleanupError }
            try sessions.save(record)
            // Capture every potentially failing dependency before the commit. A confirmed atomic
            // write cannot become an apparent login failure due to a post-write epoch read.
            return AuthSessionCommit(session: record, publicationEpoch: committedEpoch)
        }
    }

    func loadTokens() throws -> TokenPair? { try sessions.load()?.tokens }

    /// Compare against both the sign-in lineage and generation used by the network request.
    /// Reconciliation, shared publication and private replacement are one synchronous transaction.
    /// A shared refresh is retained if it already won; no network work runs under the lock.
    @discardableResult
    func saveRefreshedTokens(
        _ tokens: TokenPair,
        basedOnGeneration generation: UInt64,
        requiringScope scope: TokenScope
    ) throws -> TokenPair? {
        guard generation < UInt64.max else { throw SecurityStorage.KeychainStoreError.decodeFailed }
        return try tokenPersistence.commitRefresh(
            tokens.versioned(generation: generation + 1),
            basedOnGeneration: generation,
            requiringScope: scope
        )
    }

    @discardableResult
    func reconcileSharedTokensIfNewer(requiringScope scope: TokenScope? = nil) throws -> TokenPair? {
        try tokenPersistence.reconcile(requiringScope: scope)?.tokens
    }

    // MARK: Biometric-gated vault key

    public func enableBiometricUnlock(
        key: String,
        requiringScope scope: TokenScope,
        publicationEpoch: UUID
    ) throws {
        try sharedTokens.withTransaction { transaction in
            guard let current = try sessions.load(), current.scope == scope else { throw CancellationError() }
            guard try transaction.publicationEpoch() == publicationEpoch else { throw CancellationError() }
            try Task.checkCancellation()
            try saveBiometricUserKey(key)
            do {
                var account = current.account
                account.isBiometricUnlockEnabled = true
                try sessions.save(PersistedAuthSession(account: account, scope: scope, tokens: current.tokens))
            } catch {
                do { try deleteBiometricUserKey() }
                catch { throw AuthPersistenceError.biometricRollbackFailed }
                throw error
            }
        }
    }

    /// Stores the decrypted user key so a later launch can skip master-password entry. Caller must
    /// have already obtained user consent (Touch ID enrollment prompt). Written `.biometryGated`,
    /// so reading it back is impossible without passing an OS-level biometric/passcode check.
    func saveBiometricUserKey(_ key: String) throws {
        try keychain.write(Data(key.utf8), for: AuthKeychainKey.biometricUserKey, protection: .biometryGated)
    }

    /// Read used by the unlock flow: absence permits password fallback, while every other
    /// Keychain/decoding failure remains distinguishable and must not clear biometric enrollment.
    func readBiometricUserKey() throws -> String? {
        try readString(for: AuthKeychainKey.biometricUserKey)
    }

    public func readBiometricUserKey(requiringScope scope: TokenScope) throws -> String? {
        try sharedTokens.withTransaction { _ in
            _ = try currentSession(requiringScope: scope)
            return try readString(for: AuthKeychainKey.biometricUserKey)
        }
    }

    func deleteBiometricUserKey() throws {
        try keychain.remove(AuthKeychainKey.biometricUserKey)
    }

    func disableBiometricUnlock(requiringScope scope: TokenScope, publicationEpoch: UUID) throws {
        try sharedTokens.withTransaction { transaction in
            let current = try currentSession(requiringScope: scope)
            try validateUnlockMutation(in: transaction, publicationEpoch: publicationEpoch)
            var firstError: Error?
            do { try deleteBiometricUserKey() }
            catch SecurityStorage.KeychainStoreError.notFound {}
            catch { firstError = error }
            var account = current.account
            account.isBiometricUnlockEnabled = false
            do {
                try sessions.save(PersistedAuthSession(account: account, scope: scope, tokens: current.tokens))
            } catch { firstError = firstError ?? error }
            if let firstError { throw firstError }
        }
    }

    // MARK: PIN-gated vault key

    /// Stores a PIN-protected copy of the user key (see `SessionPinUnlockSettings`). Unlike the biometric key,
    /// this isn't gated by an OS-level prompt on read - the PIN itself is the check, verified by
    /// `initializeUserCrypto` failing to decrypt with an incorrect PIN.
    func savePinProtectedUserKey(_ key: String) throws {
        try keychain.write(Data(key.utf8), for: AuthKeychainKey.pinProtectedUserKey)
    }

    /// Read used by UnlockModel so a Keychain outage is not shown as “PIN not configured.”
    func readPinProtectedUserKey() throws -> String? {
        try readString(for: AuthKeychainKey.pinProtectedUserKey)
    }

    public func readPinProtectedUserKey(requiringScope scope: TokenScope) throws -> String? {
        try sharedTokens.withTransaction { _ in
            _ = try currentSession(requiringScope: scope)
            return try readString(for: AuthKeychainKey.pinProtectedUserKey)
        }
    }

    public func pinUnlockState(requiringScope scope: TokenScope) throws -> PinUnlockState {
        try sharedTokens.withTransaction { _ in
            let current = try currentSession(requiringScope: scope)
            let hasKey = try readString(for: AuthKeychainKey.pinProtectedUserKey) != nil
            let enabled = current.account.isPinUnlockEnabled && hasKey
            return PinUnlockState(isEnabled: enabled, failureCount: try readPinFailureCount())
        }
    }

    public func enrollPinProtectedUserKey(
        _ key: String,
        requiringScope scope: TokenScope,
        publicationEpoch: UUID
    ) throws {
        try sharedTokens.withTransaction { transaction in
            let current = try currentSession(requiringScope: scope)
            guard try transaction.publicationEpoch() == publicationEpoch else { throw CancellationError() }
            try Task.checkCancellation()
            try savePinProtectedUserKey(key)
            do {
                try resetPinFailureCount()
                var account = current.account
                account.isPinUnlockEnabled = true
                try sessions.save(PersistedAuthSession(account: account, scope: scope, tokens: current.tokens))
            } catch {
                do { try deletePinProtectedUserKey() }
                catch { throw AuthPersistenceError.pinRollbackFailed }
                throw error
            }
        }
    }

    public func removePinUnlock(requiringScope scope: TokenScope, publicationEpoch: UUID) throws {
        try sharedTokens.withTransaction { transaction in
            let current = try currentSession(requiringScope: scope)
            guard try transaction.publicationEpoch() == publicationEpoch else { throw CancellationError() }
            try Task.checkCancellation()
            var firstError: Error?
            do { try deletePinProtectedUserKey() }
            catch SecurityStorage.KeychainStoreError.notFound {}
            catch { firstError = error }
            do { try resetPinFailureCount() }
            catch { firstError = firstError ?? error }
            var account = current.account
            account.isPinUnlockEnabled = false
            do {
                try sessions.save(PersistedAuthSession(account: account, scope: scope, tokens: current.tokens))
            } catch { firstError = firstError ?? error }
            if let firstError { throw firstError }
        }
    }

    /// Best-effort fail-closed cleanup used when the attempt counter cannot be trusted.
    /// It never falls back to a metadata-only or newly signed-in account.
    func disablePinUnlock(requiringScope scope: TokenScope, publicationEpoch: UUID) throws -> Bool {
        try sharedTokens.withTransaction { transaction in
            let current = try currentSession(requiringScope: scope)
            try validateUnlockMutation(in: transaction, publicationEpoch: publicationEpoch)
            var pinKeyRemoved = false
            do {
                try deletePinProtectedUserKey()
                pinKeyRemoved = true
            } catch SecurityStorage.KeychainStoreError.notFound {
                pinKeyRemoved = true
            } catch { pinKeyRemoved = false }
            var accountFlagSaved = false
            var account = current.account
            account.isPinUnlockEnabled = false
            do {
                try sessions.save(PersistedAuthSession(account: account, scope: scope, tokens: current.tokens))
                accountFlagSaved = true
            } catch { accountFlagSaved = false }
            return pinKeyRemoved || accountFlagSaved
        }
    }

    private func readString(for account: String) throws -> String? {
        guard let data = try keychain.get(account) else { return nil }
        guard let value = String(data: data, encoding: .utf8), !value.isEmpty else {
            throw SecurityStorage.KeychainStoreError.decodeFailed
        }
        return value
    }

    func deletePinProtectedUserKey() throws {
        do {
            try keychain.remove(AuthKeychainKey.pinProtectedUserKey)
        } catch SecurityStorage.KeychainStoreError.notFound {
            // Deleting an already absent key is an idempotent success.
        }
    }

    // MARK: PIN attempt limiting

    /// How many consecutive wrong PINs are tolerated before PIN unlock is torn down and the master
    /// password becomes the only way back in. A PIN is short by design, so without this an attacker
    /// holding the device can simply enumerate the whole keyspace offline - the SDK's decrypt
    /// failure is a fast, local, unlimited oracle otherwise.
    public static let maxPinAttempts = 5

    func pinFailureCount() throws -> Int {
        try readPinFailureCount()
    }

    private func readPinFailureCount() throws -> Int {
        guard let data = try keychain.get(AuthKeychainKey.pinFailureCount) else { return 0 }
        guard let value = String(data: data, encoding: .utf8).flatMap(Int.init), value >= 0 else {
            throw SecurityStorage.KeychainStoreError.decodeFailed
        }
        return value
    }

    /// Records one failed attempt and reports how many remain.
    @discardableResult
    func recordPinFailure() throws -> Int {
        let current = try readPinFailureCount()
        let count = min(current, Self.maxPinAttempts - 1) + 1
        try keychain.write(Data(String(count).utf8), for: AuthKeychainKey.pinFailureCount)
        return count
    }

    func resetPinFailureCount() throws {
        // Write an explicit zero instead of relying on a delete that can fail silently.
        try keychain.write(Data("0".utf8), for: AuthKeychainKey.pinFailureCount)
    }

    func recordPinFailure(requiringScope scope: TokenScope, publicationEpoch: UUID) throws -> Int {
        try sharedTokens.withTransaction { transaction in
            _ = try currentSession(requiringScope: scope)
            try validateUnlockMutation(in: transaction, publicationEpoch: publicationEpoch)
            let current = try readPinFailureCount()
            let count = min(current, Self.maxPinAttempts - 1) + 1
            try keychain.write(Data(String(count).utf8), for: AuthKeychainKey.pinFailureCount)
            return count
        }
    }

    func resetPinFailureCount(requiringScope scope: TokenScope, publicationEpoch: UUID) throws {
        try sharedTokens.withTransaction { transaction in
            _ = try currentSession(requiringScope: scope)
            try validateUnlockMutation(in: transaction, publicationEpoch: publicationEpoch)
            try resetPinFailureCount()
        }
    }

    private func currentSession(requiringScope scope: TokenScope) throws -> PersistedAuthSession {
        try AuthCleanupIntent.requireNone(in: sharedKeychain)
        guard let current = try sessions.load(), current.scope == scope else { throw CancellationError() }
        return current
    }

    private func validateUnlockMutation(in transaction: SharedTokenTransaction, publicationEpoch: UUID) throws {
        try Task.checkCancellation()
        guard try transaction.publicationEpoch() == publicationEpoch else { throw CancellationError() }
    }

    // MARK: Shared autofill key

    /// Written after *every* successful unlock (see `EnableBiometricsModel.appeared`), not
    /// gated behind any opt-in - unlike the biometric/PIN keys, this isn't a user-facing
    /// convenience feature, it's plumbing the AutoFill extension needs to function at all. Still
    /// only readable by this app + the extension (shared Keychain access group), and still
    /// requires the device to be currently unlocked
    /// (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, set in `SecurityStorage.DefaultKeychainStore`).
    public func autofillPublicationEpoch() throws -> UUID {
        try SharedAutoFillUnlockStore(
            keychain: sharedKeychain,
            containerURL: sharedContainerURL,
            lockPolicy: sharedLockPolicy
        ).publicationEpoch()
    }

    public func saveSharedAutofillUserKey(
        _ key: String,
        accountInfo: SharedAccountInfo,
        publicationEpoch: UUID,
        authenticationID: UUID? = nil
    ) throws {
        try sharedTokens.withTransaction { transaction in
            guard let current = try tokenPersistence.reconcile(in: transaction),
                  authenticationID == nil || authenticationID == current.scope.authenticationID
            else { throw CancellationError() }
            let expected = try current.account.autoFillAccountInfo()
            guard accountInfo.userId == expected.userId, accountInfo.email == expected.email,
                  accountInfo.serverBaseURL == expected.serverBaseURL,
                  accountInfo.encryptedPrivateKey == expected.encryptedPrivateKey,
                  accountInfo.kdfType == expected.kdfType,
                  accountInfo.kdfIterations == expected.kdfIterations,
                  accountInfo.kdfMemory == expected.kdfMemory,
                  accountInfo.kdfParallelism == expected.kdfParallelism else { throw CancellationError() }
            try transaction.saveUnlock(
                userKey: key,
                accountInfo: accountInfo,
                scope: current.scope,
                publicationEpoch: publicationEpoch
            )
            // Grant and tokens share the same lock and sign-in lineage. A failed token write
            // leaves an unusable token capability, not tokens implicitly owned by the new grant.
            try transaction.publish(current.tokens, scope: current.scope)
        }
    }

    /// Production code never reads this back (only the AutoFill extension does, via its own
    /// `SharedAppGroup`-scoped SecurityStorage store) - exists so tests can verify what got written.
    func loadSharedAutofillUserKeyForTesting() -> String? {
        try? SharedAutoFillUnlockStore(
            keychain: sharedKeychain,
            containerURL: sharedContainerURL,
            lockPolicy: sharedLockPolicy
        ).load()?.userKey
    }

    func loadSharedAccountInfoForTesting() -> SharedAccountInfo? {
        try? SharedAutoFillUnlockStore(
            keychain: sharedKeychain,
            containerURL: sharedContainerURL,
            lockPolicy: sharedLockPolicy
        ).load()?.accountInfo
    }

    // MARK: Lock / logout

    /// Revokes the AutoFill extension's ability to decrypt anything, without touching the stored
    /// account. This is what "locked" has to mean in practice: the extension runs in its own
    /// process off the shared Keychain key, so dropping the app's in-memory session alone would
    /// leave every password still fillable from any text field on the system.
    ///
    /// The key is re-shared automatically on the next successful unlock (see
    /// `PendingAuthSession.publishAutoFillUnlock`), so this costs nothing but a
    /// re-unlock. A nonsecret revocation epoch stays to reject late publication. The old standalone
    /// `sharedAccountInfo` key is legacy metadata only; new readers never authorize from it.
    public func lockSession() throws {
        // An extension may have rotated the refresh token shortly before the user locks. Persist
        // that newer generation before revoking shared access so the next unlock can continue the
        // same session rather than attempting a stale refresh token.
        try sharedTokens.withTransaction { try lockSession(in: $0) }
    }

    private func lockSession(in transaction: SharedTokenTransaction) throws {
        var firstError: Error?
        var pending: AuthCleanupIntent?
        do { pending = try transaction.cleanupIntent() }
        catch { firstError = error }
        guard pending?.kind != .logout else { throw AuthCleanupRecoveryError.pending }
        // Reconcile while the old grant is still eligible, before installing the deny marker.
        if pending == nil, firstError == nil {
            do { _ = try tokenPersistence.reconcile(in: transaction) }
            catch { firstError = error }
        }
        do { try transaction.beginCleanup(.lock) }
        catch { firstError = firstError ?? error }
        do { try transaction.revokeCapabilities() }
        catch { firstError = firstError ?? error }
        if let firstError { throw firstError }
        try transaction.finishCleanup()
    }

    /// Clears everything except the device identifier, which should stay stable across accounts.
    public func clearSession() throws {
        try sharedTokens.withTransaction { try clearSession(in: $0) }
    }

    private func clearSession(in transaction: SharedTokenTransaction) throws {
        // Logout discards tokens. Persist deny intent first, then attempt revocation and each
        // deletion independently. A failure never reports success or removes the deny marker.
        var firstError: Error?
        do { try transaction.beginCleanup(.logout) }
        catch { firstError = error }
        do { try transaction.revokeCapabilities() }
        catch { firstError = firstError ?? error }
        for account in [PrivateAuthSessionStore.key, AuthKeychainKey.account, AuthKeychainKey.tokens,
                        AuthKeychainKey.biometricUserKey, AuthKeychainKey.pinProtectedUserKey,
                        AuthKeychainKey.pinFailureCount] {
            do { try keychain.remove(account) }
            catch { firstError = firstError ?? error }
        }
        do { try sharedKeychain.remove(AuthKeychainKey.sharedAccountInfo) }
        catch { firstError = firstError ?? error }
        do { try transaction.clearRefreshIntent() }
        catch { firstError = firstError ?? error }
        if let firstError { throw firstError }
        try transaction.finishCleanup()
    }

    /// Called before restore on every launch/retry. The intent remains until ALL Keychain work
    /// succeeds; the same synchronous shared lock excludes successor login/unlock publication.
    public func recoverPendingCleanup() throws {
        try sharedTokens.withTransaction { transaction in
            // Read and replay in ONE transaction: otherwise another process could finish cleanup
            // and publish a successor between reading an old logout intent and replaying it.
            let intent: AuthCleanupIntent?
            do { intent = try transaction.cleanupIntent() }
            catch {
                // Unknown/corrupt intent is preserved, but independently try to deny an old
                // capability. This does not authorize deleting private data without intent.
                let intentError = error
                do { try transaction.revokeCapabilities() }
                catch { throw error }
                throw intentError
            }
            switch intent?.kind {
            case .lock: try lockSession(in: transaction)
            case .logout: try clearSession(in: transaction)
            case nil: break
            }
        }
    }
}

private enum AuthPersistenceError: LocalizedError {
    case biometricRollbackFailed
    case pinRollbackFailed
    var errorDescription: String? {
        switch self {
        case .biometricRollbackFailed: "Account setup failed and the saved biometric key could not be removed."
        case .pinRollbackFailed: "PIN setup failed and its saved key could not be removed."
        }
    }
}
