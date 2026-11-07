import AutoFillContract
@testable import Data
import Domain
import Foundation
import SecurityStorage
import Testing

@Suite
struct TokenRefreshRecoveryTests {
    private let expired = TokenPair(accessToken: "fake-expired", refreshToken: "fake-refresh", expiresAt: .distantPast)
    private let issued = TokenRefreshOutcome.success(RefreshedTokenPayload(
        accessToken: "fake-issued", refreshToken: "fake-rotated", expiresIn: 3600
    ))

    @Test
    func cancellationAtTheConfirmedFreshWriteDoesNotMisreportAnUncommittedLogin() async throws {
        let privateKeychain = CommitCancellingKeychain()
        let store = AuthCredentialStore(
            keychain: privateKeychain,
            sharedKeychain: AuthKeychainFixture(),
            sharedLockPolicy: .processOnly
        )
        let account = StoredAuthAccount.fixture()
        let provider = AppAuthTokenProvider(
            identityURL: account.serverBaseURL.appendingPathComponent("identity"), keychainStore: store,
            tokenService: AuthRefreshFixture(), freshLoginProof: try store.freshLoginCommitProof()
        )
        let operation = Task {
            try await provider.storeSession(account: account, tokens: expired)
            return "confirmed"
        }
        #expect(try await operation.value == "confirmed")
        #expect(operation.isCancelled)
        #expect(try store.loadSession()?.account == account)
        #expect(try await provider.validatedScope() == store.loadSession()?.scope)
        await provider.revoke()
        await #expect(throws: CancellationError.self) { _ = try await provider.validatedScope() }
    }

    private func setup(container: URL? = nil) throws -> (AuthCredentialStore, AuthKeychainFixture, AuthKeychainFixture) {
        let privateKeychain = AuthKeychainFixture(); let sharedKeychain = AuthKeychainFixture()
        let store = AuthCredentialStore(
            keychain: privateKeychain, sharedKeychain: sharedKeychain,
            sharedLockPolicy: container == nil ? .processOnly : .appGroup,
            sharedContainerURL: container
        )
        try store.saveSession(account: .fixture(), tokens: expired)
        return (store, privateKeychain, sharedKeychain)
    }

    private func coordinator(_ store: AuthCredentialStore, service: AuthRefreshFixture) throws -> TokenCoordinator {
        let scope = try #require(try store.loadSession()?.scope)
        return TokenCoordinator(
            scope: scope, identityURL: scope.account.serverBaseURL.appendingPathComponent("identity"),
            persistence: store.tokenPersistence, refreshService: service
        )
    }

    @Test
    func independentAppAndExtensionAdaptersOnlyConsumeOneRotatingToken() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (store, _, sharedKeychain) = try setup(container: directory)
        try store.publishForTesting()
        let grant = try #require(try SharedAutoFillUnlockStore(keychain: sharedKeychain, containerURL: directory).load())
        let service = AuthRefreshFixture(); service.refreshOutcome = issued
        let gate = AuthOperationTestGate()
        service.beforeRefreshReturns = { await gate.pause() }
        let app = try coordinator(store, service: service)
        let extensionStore = SharedTokenStore(keychain: sharedKeychain, containerURL: directory)
        let extensionProvider = TokenCoordinator(
            scope: app.scope, identityURL: app.scope.account.serverBaseURL.appendingPathComponent("identity"),
            persistence: ExtensionTokenPersistence(shared: extensionStore, proof: grant.proof), refreshService: service
        )
        let first = Task { await app.getAccessToken() }
        await gate.waitUntilPaused()
        let second = Task { await extensionProvider.getAccessToken() }
        await gate.release()
        #expect(await first.value == "fake-issued")
        #expect(await second.value == "fake-issued")
        #expect(service.refreshCallCount == 1)
        #expect(try store.loadTokens()?.generation == 2)
        #expect(try TokenRefreshIntent.read(from: sharedKeychain) == nil)
    }

    @Test
    func restartAfterAnUnconfirmedRequestRequiresSignInWithoutAnotherHTTPOrLogout() async throws {
        let (store, _, shared) = try setup()
        let scope = try #require(try store.loadSession()?.scope)
        _ = try store.tokenPersistence.beginRefresh(requiringScope: scope, generation: 1)
        let service = AuthRefreshFixture(); service.refreshOutcome = issued
        let restarted = try coordinator(store, service: service)
        await #expect(throws: SessionAuthorizationError.refreshRecoveryRequired) { _ = try await restarted.requireAccessToken(
        ) }
        #expect(service.refreshCallCount == 0)
        #expect(try await restarted.validatedScope() == scope)
        #expect(try store.loadTokens()?.generation == 1)
        #expect(try TokenRefreshIntent.read(from: shared) != nil)
    }

    @Test
    func transportAmbiguitySurvivesProviderReconstruction() async throws {
        let (store, _, _) = try setup()
        let service = AuthRefreshFixture()
        let first = try coordinator(store, service: service)
        await #expect(throws: SessionAuthorizationError.refreshRecoveryRequired) { _ = try await first.requireAccessToken(
        ) }
        let restarted = try coordinator(store, service: service)
        await #expect(throws: SessionAuthorizationError.refreshRecoveryRequired) { _ = try await restarted.requireAccessToken(
        ) }
        #expect(service.refreshCallCount == 1)
        #expect(try await first.validatedScope() == restarted.scope)
    }

    @Test
    func classifiedServerFailureAllowsRetryAndDoesNotExpireTheSession() async throws {
        let (store, _, shared) = try setup()
        let service = AuthRefreshFixture()
        service.refreshOutcome = .retryable(.http(statusCode: 429, retryAfter: nil))
        let subject = try coordinator(store, service: service)
        await #expect(throws: SessionAuthorizationError.temporarilyUnavailable) { _ = try await subject.requireAccessToken(
        ) }
        #expect(try TokenRefreshIntent.read(from: shared) == nil)
        service.refreshOutcome = issued
        #expect(try await subject.requireAccessToken() == "fake-issued")
        #expect(service.refreshCallCount == 2)
    }

    @Test(arguments: [408, 409, 500, 503])
    func ambiguousServerOrProxyFailuresDoNotLogoutOrRepeatARotatingRequest(_ status: Int) async throws {
        let (store, _, _) = try setup()
        let service = AuthRefreshFixture()
        service.refreshOutcome = .retryable(.http(statusCode: status, retryAfter: nil))
        let subject = try coordinator(store, service: service)
        await #expect(throws: SessionAuthorizationError.refreshRecoveryRequired) { _ = try await subject.requireAccessToken(
        ) }
        #expect(try await subject.validatedScope() == store.loadSession()?.scope)
        await #expect(throws: SessionAuthorizationError.refreshRecoveryRequired) { _ = try await subject.requireAccessToken(
        ) }
        #expect(service.refreshCallCount == 1)
    }

    @Test
    func lockEpochChangeRejectsTheResponseEvenWithoutAnExplicitCoordinatorRevoke() async throws {
        let (store, _, shared) = try setup()
        let service = AuthRefreshFixture(); service.refreshOutcome = issued
        let gate = AuthOperationTestGate(); service.beforeRefreshReturns = { await gate.pause() }
        let subject = try coordinator(store, service: service)
        let lookup = Task { await subject.getAccessToken() }
        await gate.waitUntilPaused()
        try store.lockSession()
        await gate.release()
        #expect(await lookup.value == nil)
        #expect(try store.loadTokens()?.accessToken == "fake-expired")
        #expect(try TokenRefreshIntent.read(from: shared) != nil)
    }

    @Test
    func failedPrivateWriteWithoutAGrantIsNotMisclassifiedAsRecoverableSharedPublication() async throws {
        let (store, privateKeychain, shared) = try setup()
        privateKeychain.accountsFailingWrites = [PrivateAuthSessionStore.key]
        let service = AuthRefreshFixture(); service.refreshOutcome = issued
        let first = try coordinator(store, service: service)
        #expect(await first.getAccessToken() == nil)
        privateKeychain.accountsFailingWrites = []
        let restarted = try coordinator(store, service: service)
        await #expect(throws: SessionAuthorizationError.refreshRecoveryRequired) { _ = try await restarted.requireAccessToken(
        ) }
        #expect(service.refreshCallCount == 1)
        #expect(try SharedTokenStore(keychain: shared, lockPolicy: .processOnly).load() == nil)
    }

    @Test
    func appProviderRetainsTheRecoveryMessageWhenFailedCommitRevokesItsObsoleteGrant() async throws {
        let (store, privateKeychain, _) = try setup()
        let scope = try #require(try store.loadSession()?.scope)
        let service = AuthRefreshFixture(); service.refreshOutcome = issued
        let provider = AppAuthTokenProvider(
            identityURL: scope.account.serverBaseURL.appendingPathComponent("identity"), keychainStore: store,
            tokenService: service, scope: scope
        )
        privateKeychain.accountsFailingWrites = [PrivateAuthSessionStore.key]
        await #expect(throws: SessionAuthorizationError.refreshRecoveryRequired) { _ = try await provider.requireAccessToken(
        ) }
        #expect(service.refreshCallCount == 1)
        privateKeychain.accountsFailingWrites = []
        #expect(try store.loadTokens()?.generation == 1)
        await provider.revoke()
        await #expect(throws: CancellationError.self) { _ = try await provider.requireAccessToken() }
    }

    @Test
    func retainedSharedRotationIsRecoveredBeforeAnyRepeatedRequest() async throws {
        let (store, privateKeychain, _) = try setup()
        try store.publishForTesting()
        privateKeychain.accountsFailingWrites = [PrivateAuthSessionStore.key]
        let service = AuthRefreshFixture(); service.refreshOutcome = issued
        let first = try coordinator(store, service: service)
        #expect(await first.getAccessToken() == nil)
        privateKeychain.accountsFailingWrites = []
        let restarted = try coordinator(store, service: service)
        #expect(try await restarted.requireAccessToken() == "fake-issued")
        #expect(try store.loadTokens()?.refreshToken == "fake-rotated")
        #expect(service.refreshCallCount == 1)
    }

    @Test
    func intentWriteFailurePreventsTransmissionAndCorruptIntentFailsClosed() async throws {
        let (store, _, shared) = try setup()
        let service = AuthRefreshFixture(); service.refreshOutcome = issued
        shared.accountsFailingWrites = [TokenRefreshIntent.key]
        let first = try coordinator(store, service: service)
        #expect(await first.getAccessToken() == nil)
        shared.accountsFailingWrites = []
        try shared.write(Foundation.Data("corrupt".utf8), for: TokenRefreshIntent.key)
        let second = try coordinator(store, service: service)
        #expect(await second.getAccessToken() == nil)
        #expect(service.refreshCallCount == 0)
    }

    @Test
    func logoutCleanupRetriesIntentRemovalAndFreshSignInUsesANewLineage() throws {
        let (store, _, shared) = try setup()
        let scope = try #require(try store.loadSession()?.scope)
        let intent = try #require(try store.tokenPersistence.beginRefresh(requiringScope: scope, generation: 1))
        #expect(String(describing: intent) == "TokenRefreshIntent(<redacted>)")
        shared.accountsFailingRemoval = [TokenRefreshIntent.key]
        #expect(throws: AuthFixtureError.self) { try store.clearSession() }
        shared.accountsFailingRemoval = []
        try store.recoverPendingCleanup()
        #expect(try TokenRefreshIntent.read(from: shared) == nil)
        let new = try store.saveSession(account: .fixture(), tokens: expired)
        #expect(new.scope != scope)
        #expect(try store.tokenPersistence.beginRefresh(requiringScope: new.scope, generation: 1) != nil)
    }
}

private final class CommitCancellingKeychain: KeychainStoring, @unchecked Sendable {
    private let backing = AuthKeychainFixture()
    func read(_ account: String) throws -> Foundation.Data { try backing.read(account) }
    func remove(_ account: String) throws { try backing.remove(account) }
    func write(_ value: Foundation.Data, for account: String, protection: KeychainProtection) throws {
        try backing.write(value, for: account, protection: protection)
        if account == PrivateAuthSessionStore.key { withUnsafeCurrentTask { $0?.cancel() } }
    }
}
