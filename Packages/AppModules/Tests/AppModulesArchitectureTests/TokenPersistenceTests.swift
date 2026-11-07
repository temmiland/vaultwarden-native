import AutoFillContract
import Data
import Foundation
import SecurityStorage
import Testing

/// Pure port/merge fixtures. No real Keychain, SDK, App Group, file lock or network.
@Suite
struct TokenPersistenceTests {
    @Test
    func aProviderWaitingToRefreshCannotRebindToANewerPublicationEpoch() throws {
        let fixture = try fixture()
        let bound = AppTokenPersistence(
            sessions: fixture.sessions, shared: fixture.shared, authorizationEpoch: fixture.shared.snapshot.epoch
        )
        #expect(try bound.isCurrentScope(fixture.session.scope))
        fixture.shared.update { $0.epoch = UUID() }
        #expect(try bound.isCurrentScope(fixture.session.scope) == false)
        #expect(try bound.beginRefresh(requiringScope: fixture.session.scope, generation: 1) == nil)
        #expect(
            try bound.commitRefresh(
                pair("late", generation: 2),
                basedOnGeneration: 1,
                requiringScope: fixture.session.scope
            ) == nil
        )
        #expect(fixture.shared.snapshot.publishAttempts == 0 && fixture.shared.snapshot.refreshIntent == nil)
    }

    private func pair(_ label: String, generation: UInt64) -> TokenPair {
        TokenPair(
            accessToken: "test-access-\(label)",
            refreshToken: "test-refresh-\(label)",
            expiresAt: .distantFuture,
            generation: generation
        )
    }

    private func fixture(granted: Bool = true) throws -> PersistenceFixture {
        let account = StoredAuthAccount(
            userId: "test-user",
            email: "test@example.com",
            serverBaseURL: URL(string: "https://vault.example.com")!,
            kdfType: 0,
            kdfIterations: 600_000,
            kdfMemory: nil,
            kdfParallelism: nil,
            encryptedUserKey: "fake-wrapped-user-key",
            encryptedPrivateKey: "fake-wrapped-private-key",
            isBiometricUnlockEnabled: false
        )
        let session = PersistedAuthSession(
            account: account,
            scope: TokenScope(account: account.tokenIdentity),
            tokens: pair("original", generation: 1)
        )
        let keychain = PersistenceKeychainFixture()
        let sessions = PrivateAuthSessionStore(keychain: keychain)
        try sessions.save(session)
        let proof = ExtensionUnlockProof(
            account: AutoFillAccountIdentity(
                userID: account.userId,
                serverBaseURL: account.serverBaseURL
            ),
            authenticationID: session.scope.authenticationID
        )
        let shared = SharedTransactionFixture(
            scope: session.scope,
            proof: granted ? proof : nil,
            tokens: granted ? session.tokens : nil
        )
        return PersistenceFixture(
            session: session,
            proof: proof,
            keychain: keychain,
            sessions: sessions,
            shared: shared,
            app: AppTokenPersistence(sessions: sessions, shared: shared)
        )
    }

    @Test
    func onlyAStrictlyNewerEligibleSharedPairIsAdopted() throws {
        let f = try fixture()
        let winner = pair("shared", generation: 2)
        f.shared.update { $0.tokens = winner }
        #expect(try f.app.load(requiringScope: f.session.scope) == winner)
        let adopted = try #require(try f.sessions.load())
        #expect(adopted.scope == f.session.scope)
        #expect(adopted.account == f.session.account)
        #expect(adopted.tokens == winner)
        #expect(f.shared.snapshot.publishAttempts == 0)
    }

    @Test(arguments: [0, 1])
    func equalOrOlderGenerationsDoNotReplacePrivateTokens(_ generation: Int) throws {
        let f = try fixture()
        f.shared.update { $0.tokens = pair("different", generation: UInt64(generation)) }
        #expect(try f.app.load(requiringScope: f.session.scope) == f.session.tokens)
        #expect(try f.sessions.load()?.tokens == f.session.tokens)
        #expect(f.keychain.writeCount == 1)
    }

    @Test
    func aForeignSignInScopeIsDeniedBeforeSharedReads() throws {
        let f = try fixture()
        let foreign = TokenScope(account: f.session.scope.account)
        #expect(try f.app.load(requiringScope: foreign) == nil)
        #expect(try f.app.commitRefresh(
            pair("late", generation: 2),
            basedOnGeneration: 1,
            requiringScope: foreign
        ) == nil)
        #expect(f.shared.snapshot.readAttempts == 0)
        #expect(f.keychain.writeCount == 1)
    }

    @Test(arguments: [false, true])
    func successfulRefreshRetainsThePairAndOnlyPublishesUnderAMatchingGrant(_ granted: Bool) throws {
        let f = try fixture(granted: granted)
        let issued = pair("issued", generation: 2)
        #expect(try f.app.commitRefresh(issued, basedOnGeneration: 1, requiringScope: f.session.scope) == issued)
        #expect(try f.sessions.load()?.tokens == issued)
        #expect(f.shared.snapshot.tokens == (granted ? issued : nil))
        #expect(f.shared.snapshot.publishAttempts == (granted ? 1 : 0))
    }

    @Test
    func aNewerWinnerIsNeverOverwrittenByAnOldRefresh() throws {
        let f = try fixture()
        let winner = pair("winner", generation: 9)
        f.shared.update { $0.tokens = winner }
        #expect(try f.app.commitRefresh(
            pair("obsolete", generation: 2),
            basedOnGeneration: 1,
            requiringScope: f.session.scope
        ) == winner)
        #expect(try f.sessions.load()?.tokens == winner)
        #expect(f.shared.snapshot.publishAttempts == 0)
    }

    @Test
    func aLowerStoredGenerationIsNotAWinningCommit() throws {
        let f = try fixture()
        #expect(try f.app.commitRefresh(
            pair("future", generation: 10),
            basedOnGeneration: 9,
            requiringScope: f.session.scope
        ) == nil)
        #expect(f.shared.snapshot.publishAttempts == 0)
        #expect(try f.sessions.load()?.tokens == f.session.tokens)
    }

    @Test
    func invalidIssuedTokensAreRejectedBeforeSharedPublication() throws {
        let f = try fixture()
        let invalid = TokenPair(accessToken: "", refreshToken: "test-refresh", expiresAt: .distantFuture, generation: 2)
        #expect(throws: KeychainStoreError.decodeFailed) {
            try f.app.commitRefresh(invalid, basedOnGeneration: 1, requiringScope: f.session.scope)
        }
        #expect(f.shared.snapshot.publishAttempts == 0)
        #expect(f.keychain.writeCount == 1)
    }

    @Test
    func aNonSuccessorCandidateCannotAdvanceTheGeneration() throws {
        let f = try fixture()
        #expect(throws: KeychainStoreError.decodeFailed) {
            try f.app.commitRefresh(pair("wrong", generation: 7), basedOnGeneration: 1, requiringScope: f.session.scope)
        }
        #expect(f.shared.snapshot.publishAttempts == 0)
        #expect(f.keychain.writeCount == 1)
    }

    @Test
    func failedPrivateWriteLeavesThePublishedRotationRecoverable() throws {
        let f = try fixture()
        let issued = pair("issued", generation: 2)
        f.keychain.setFailures(write: true)
        #expect(throws: PersistenceFixtureError.write) {
            try f.app.commitRefresh(issued, basedOnGeneration: 1, requiringScope: f.session.scope)
        }
        #expect(f.shared.snapshot.tokens == issued)
        #expect(f.shared.snapshot.revocationAttempts == 0)
        f.keychain.setFailures(write: false)
        #expect(try f.app.load(requiringScope: f.session.scope) == issued)
        #expect(try f.sessions.load()?.tokens == issued)
    }

    @Test
    func failedSharedWriteStillRetainsPrivateRotationAndRevokes() throws {
        let f = try fixture()
        let issued = pair("issued", generation: 2)
        f.shared.update { $0.failPublication = true }
        #expect(throws: PersistenceFixtureError.write) {
            try f.app.commitRefresh(issued, basedOnGeneration: 1, requiringScope: f.session.scope)
        }
        #expect(try f.sessions.load()?.tokens == issued)
        #expect(f.shared.snapshot.proof == nil)
        #expect(f.shared.snapshot.tokens == nil)
        #expect(f.shared.snapshot.revocationAttempts == 1)
    }

    @Test(arguments: [false, true])
    func dualWriteFailureReportsWhetherCapabilityRevocationAlsoFailed(_ revocationFails: Bool) throws {
        let f = try fixture()
        f.shared.update { $0.failPublication = true; $0.failRevocation = revocationFails }
        f.keychain.setFailures(write: true)
        #expect(throws: TokenCommitRecoveryError.rotationNotDurable(capabilityRevocationFailed: revocationFails)) {
            try f.app.commitRefresh(pair("lost", generation: 2), basedOnGeneration: 1, requiringScope: f.session.scope)
        }
        #expect(f.shared.snapshot.revocationAttempts == 1)
        #expect(try f.sessions.load()?.tokens == f.session.tokens)
        #expect(f.shared.snapshot.tokens == (revocationFails ? f.session.tokens : nil))
    }

    @Test
    func lockStillRevokesWhenPrivateReadsFail() throws {
        let f = try fixture()
        f.keychain.setFailures(read: true)
        #expect(throws: PersistenceFixtureError.read) { try f.app.reconcileAndRevoke() }
        #expect(f.shared.snapshot.revocationAttempts == 1)
        #expect(f.shared.snapshot.proof == nil)
        #expect(f.shared.snapshot.tokens == nil)
    }

    @Test
    func extensionCannotCommitIntoALaterUnlockWithTheSameGeneration() throws {
        let f = try fixture()
        let extensionStore = ExtensionTokenPersistence(shared: f.shared, proof: f.proof)
        #expect(try extensionStore.load(requiringScope: f.session.scope) == f.session.tokens)
        let replacementProof = ExtensionUnlockProof(
            account: f.proof.account,
            authenticationID: f.session.scope.authenticationID
        )
        f.shared.update { $0.proof = replacementProof; $0.tokenUnlockID = replacementProof.unlockID }
        #expect(try extensionStore.isCurrentScope(f.session.scope) == false)
        #expect(try extensionStore.load(requiringScope: f.session.scope) == nil)
        #expect(try extensionStore.commitRefresh(
            pair("late", generation: 2),
            basedOnGeneration: 1,
            requiringScope: f.session.scope
        ) == nil)
        #expect(f.shared.snapshot.tokens == f.session.tokens)
        #expect(f.shared.snapshot.replaceAttempts == 0)
    }

    @Test
    func extensionCommitAdoptsANewerWinnerOrCommitsExactlyOneSuccessor() throws {
        let f = try fixture()
        let extensionStore = ExtensionTokenPersistence(shared: f.shared, proof: f.proof)
        let issued = pair("issued", generation: 2)
        #expect(
            try extensionStore.commitRefresh(issued, basedOnGeneration: 1, requiringScope: f.session.scope) == issued
        )
        #expect(f.shared.snapshot.replaceAttempts == 1)
        #expect(try extensionStore.commitRefresh(
            pair("obsolete", generation: 2),
            basedOnGeneration: 1,
            requiringScope: f.session.scope
        ) == issued)
        #expect(f.shared.snapshot.replaceAttempts == 1)
        #expect(try f.sessions.load()?.tokens == f.session.tokens)
        #expect(try f.app.load(requiringScope: f.session.scope) == issued)
    }
}

private struct PersistenceFixture {
    let session: PersistedAuthSession
    let proof: ExtensionUnlockProof
    let keychain: PersistenceKeychainFixture
    let sessions: PrivateAuthSessionStore
    let shared: SharedTransactionFixture
    let app: AppTokenPersistence
}

private enum PersistenceFixtureError: Error, Equatable { case read, write, revocation }

private final class PersistenceKeychainFixture: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Foundation.Data] = [:]
    private var failRead = false
    private var failWrite = false
    private var writes = 0
    var writeCount: Int { lock.withLock { writes } }
    func setFailures(read: Bool = false, write: Bool = false) {
        lock.withLock { failRead = read; failWrite = write }
    }

    func read(_ account: String) throws -> Foundation.Data {
        try lock.withLock {
            if failRead { throw PersistenceFixtureError.read }
            guard let data = values[account] else { throw KeychainStoreError.notFound }
            return data
        }
    }

    func write(_ value: Foundation.Data, for account: String, protection: KeychainProtection) throws {
        try lock.withLock {
            if failWrite { throw PersistenceFixtureError.write }
            writes += 1
            values[account] = value
        }
    }

    func remove(_ account: String) throws { _ = lock.withLock { values.removeValue(forKey: account) } }
}

private struct SharedTransactionState {
    var scope: TokenScope
    var proof: ExtensionUnlockProof?
    var tokens: TokenPair?
    var tokenUnlockID: UUID?
    var failPublication = false
    var failRevocation = false
    var readAttempts = 0
    var publishAttempts = 0
    var replaceAttempts = 0
    var revocationAttempts = 0
    var epoch = UUID()
    var refreshIntent: TokenRefreshIntent?
}

private final class SharedTransactionFixture: SharedTokenTransacting, @unchecked Sendable {
    private let lock = NSLock()
    private var state: SharedTransactionState
    init(scope: TokenScope, proof: ExtensionUnlockProof?, tokens: TokenPair?) {
        state = SharedTransactionState(scope: scope, proof: proof, tokens: tokens, tokenUnlockID: proof?.unlockID)
    }

    var snapshot: SharedTransactionState { lock.withLock { state } }
    func withRefreshLease<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        try await operation()
    }

    func update(_ operation: (inout SharedTransactionState) -> Void) { lock.withLock { operation(&state) } }
    func withTokenTransaction<T>(_ operation: (any SharedTokenTransactionPort) throws -> T) throws -> T {
        try lock.withLock {
            let lease = SharedTransactionLease(state: state)
            defer { state = lease.state; lease.invalidate() }
            return try operation(lease)
        }
    }
}

private final class SharedTransactionLease: SharedTokenTransactionPort {
    var state: SharedTransactionState
    private var active = true
    init(state: SharedTransactionState) { self.state = state }
    func invalidate() { active = false }
    private func checkActive() throws { guard active else { throw CancellationError() } }
    func requireNoPendingCleanup() throws { try checkActive() }
    func publicationEpoch() throws -> UUID { try checkActive(); return state.epoch }
    func beginRefresh(scope: TokenScope, generation: UInt64) throws -> TokenRefreshIntent {
        try checkActive()
        if let previous = state.refreshIntent, previous.scope == scope, previous.generation >= generation {
            throw TokenRefreshRecoveryError.unconfirmedRotation
        }
        let intent = TokenRefreshIntent(scope: scope, generation: generation, publicationEpoch: state.epoch)
        state.refreshIntent = intent
        return intent
    }

    func finishRefresh(_ intent: TokenRefreshIntent) throws {
        try checkActive()
        if state.refreshIntent == intent { state.refreshIntent = nil }
    }

    func validateRefreshCommit(scope: TokenScope, generation: UInt64) throws {
        try checkActive()
        if let intent = state.refreshIntent, intent.scope == scope, intent.generation == generation,
           intent.publicationEpoch != state.epoch { throw CancellationError() }
    }

    func unlockProof() throws -> ExtensionUnlockProof? {
        try checkActive()
        state.readAttempts += 1
        return state.proof
    }

    func eligibleTokens(requiringScope scope: TokenScope) throws -> TokenPair? {
        guard let proof = try unlockProof(), scope == state.scope else { return nil }
        return try tokens(requiringProof: proof)
    }

    func tokens(requiringProof proof: ExtensionUnlockProof) throws -> TokenPair? {
        guard try unlockProof() == proof, state.tokenUnlockID == proof.unlockID,
              state.scope.authenticationID == proof.authenticationID,
              state.scope.account.userID == proof.account.userID,
              state.scope.account.serverBaseURL == proof.account.serverBaseURL else { return nil }
        return state.tokens
    }

    func publish(_ tokens: TokenPair, scope: TokenScope) throws {
        guard let proof = try unlockProof(), state.scope == scope else { throw CancellationError() }
        state.publishAttempts += 1
        if state.failPublication { throw PersistenceFixtureError.write }
        state.tokens = tokens
        state.tokenUnlockID = proof.unlockID
    }

    func replace(
        _ tokens: TokenPair,
        basedOnGeneration generation: UInt64,
        requiringScope scope: TokenScope,
        requiringProof proof: ExtensionUnlockProof
    ) throws -> Bool {
        guard scope == state.scope, let current = try self.tokens(requiringProof: proof),
              current.generation == generation, tokens.generation > generation else { return false }
        state.replaceAttempts += 1
        if state.failPublication { throw PersistenceFixtureError.write }
        state.tokens = tokens
        return true
    }

    func revokeCapabilities() throws {
        try checkActive()
        state.revocationAttempts += 1
        if state.failRevocation { throw PersistenceFixtureError.revocation }
        state.proof = nil
        state.tokens = nil
        state.tokenUnlockID = nil
    }
}
