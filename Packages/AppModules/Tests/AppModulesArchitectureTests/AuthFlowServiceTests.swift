@testable import Data
import Domain
import Foundation
import Testing

@MainActor
@Suite
struct AuthFlowServiceTests {
    private func commands(store: AuthCredentialStore, repository: any AuthRepository) -> DefaultAuthFlowService {
        let probe = PasswordFlowProbe()
        return DefaultAuthFlowService(
            store: store,
            repository: repository,
            prelogin: PasswordPreloginFixture(probe: probe, gate: nil),
            tokens: PasswordTokenFixture(probe: probe, outcomes: []),
            biometric: ReturningBiometricFixture(),
            deviceName: PasswordDeviceNameFixture(),
            applicationVersion: "fixture"
        )
    }

    @Test
    func firstRunReturnsServerSetupWithoutStartingUnlock() async throws {
        let store = AuthCredentialStore(
            keychain: AuthKeychainFixture(),
            sharedKeychain: AuthKeychainFixture(),
            sharedLockPolicy: .processOnly
        )
        let repository = DefaultAuthRepository(persistence: store)
        guard case .serverSetup = try await commands(store: store, repository: repository).restore() else {
            Issue.record("Expected first-run setup"); return
        }
        #expect(await repository.currentSnapshot().state == .signedOut)
        #expect(try store.loadSession() == nil)
    }

    @Test
    func returningRestorePreservesExactStorageIdentityAndDoesNotBeginUnlock() async throws {
        let store = AuthCredentialStore(
            keychain: AuthKeychainFixture(),
            sharedKeychain: AuthKeychainFixture(),
            sharedLockPolicy: .processOnly
        )
        let account = StoredAuthAccount.fixture(server: "https://vault.example.com/proxy/")
        let saved = try store.saveSession(
            account: account,
            tokens: TokenPair(accessToken: "fixture-access", refreshToken: "fixture-refresh", expiresAt: .distantFuture)
        )
        let repository = DefaultAuthRepository(persistence: store)
        guard case let .returningUnlock(unlock) = try await commands(store: store, repository: repository).restore() else {
            Issue.record("Expected returning commands"); return
        }
        #expect(unlock.account.session == (try AccountSession(storedAccount: account)))
        #expect(unlock.account.session.environment.baseURL.absoluteString == "https://vault.example.com/proxy")
        #expect(await repository.currentSnapshot().state == .locked(unlock.account.session))
        #expect(await repository.currentSnapshot().transition == .restored)
        try store.expectPersistedSession(saved)
        await unlock.revoke()
    }

    @Test
    func splitLegacyMetadataRequiresPasswordSignInWithoutImportingTokens() async throws {
        let store = AuthCredentialStore(
            keychain: AuthKeychainFixture(),
            sharedKeychain: AuthKeychainFixture(),
            sharedLockPolicy: .processOnly
        )
        let account = StoredAuthAccount.fixture()
        try store.save(account: account)
        let repository = DefaultAuthRepository(persistence: store)
        guard case let .passwordSignIn(environment, migration) = try await commands(store: store, repository: repository).restore(
        ) else {
            Issue.record("Legacy metadata must not authorize returning unlock"); return
        }
        #expect(environment == (try AccountSession(storedAccount: account)).environment && migration)
        #expect(try store.loadSession() == nil)
        #expect(try store.loadAccount() == account)
        #expect(await repository.currentSnapshot().state == .signedOut)
    }

    @Test
    func unsafeLegacyServerIsRetainedButNeverOfferedForUnlock() async throws {
        let store = AuthCredentialStore(
            keychain: AuthKeychainFixture(),
            sharedKeychain: AuthKeychainFixture(),
            sharedLockPolicy: .processOnly
        )
        let account = StoredAuthAccount.fixture(server: "http://vault.example.com")
        let saved = try store.saveSession(
            account: account,
            tokens: TokenPair(accessToken: "fixture-access", refreshToken: "fixture-refresh", expiresAt: .distantFuture)
        )
        let repository = DefaultAuthRepository(persistence: store)
        guard case .serverSetup = try await commands(store: store, repository: repository).restore() else {
            Issue.record("Unsafe transport was offered as an unlock route"); return
        }
        try store.expectPersistedSession(saved)
    }

    @Test(arguments: [false, true])
    func unreadableOrMalformedRecordsAreErrorsNotFirstRun(_ corrupt: Bool) async throws {
        let keychain = AuthKeychainFixture()
        let store = AuthCredentialStore(
            keychain: keychain,
            sharedKeychain: AuthKeychainFixture(),
            sharedLockPolicy: .processOnly
        )
        if corrupt { try keychain.write(
            Foundation.Data("invalid-json".utf8),
            for: PrivateAuthSessionStore.key,
            protection: .whenUnlocked
        ) } else { keychain.accountsFailingReads = [PrivateAuthSessionStore.key] }
        let repository = DefaultAuthRepository(persistence: store)
        await #expect(throws: (any Error).self) { _ = try await commands(store: store, repository: repository).restore() }
        #expect(await repository.currentSnapshot().state == .signedOut)
    }

    @Test
    func accountDisagreementBetweenRepositoryAndStorageCannotCreateReturningCommands() async throws {
        let store = AuthCredentialStore(
            keychain: AuthKeychainFixture(),
            sharedKeychain: AuthKeychainFixture(),
            sharedLockPolicy: .processOnly
        )
        _ = try store.saveSession(
            account: .fixture(),
            tokens: TokenPair(accessToken: "fixture-access", refreshToken: "fixture-refresh", expiresAt: .distantFuture)
        )
        let unrelated = AuthCredentialStore(
            keychain: AuthKeychainFixture(),
            sharedKeychain: AuthKeychainFixture(),
            sharedLockPolicy: .processOnly
        )
        let repository = DefaultAuthRepository(persistence: unrelated)
        await #expect(throws: AuthRepositoryError.accountChanged) { _ = try await commands(
            store: store,
            repository: repository
        ).restore() }
    }

    @Test(arguments: [FlowRestoreHop.restore, .snapshot])
    func cancellationAfterNoncooperativeRepositoryHopDoesNotStartUnlock(_ hop: FlowRestoreHop) async throws {
        let fixture = try ReturningFlowFixture()
        let repository = DefaultAuthRepository(persistence: fixture.store)
        let gate = AuthOperationTestGate()
        let service = commands(
            store: fixture.store,
            repository: FlowRestoreRepository(base: repository, gate: gate, hop: hop)
        )
        let task = Task { try await service.restore() }
        await gate.waitUntilPaused()
        task.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(await repository.currentSnapshot().state == .locked(try AccountSession(storedAccount: fixture.stored)))
        #expect(await repository.currentSnapshot().transition == .restored)
    }

    @Test(arguments: ["lock", "logout", "replace"])
    func persistentFenceRejectsRestoreThatResumesAfterSecurityAction(_ action: String) async throws {
        let fixture = try ReturningFlowFixture()
        let repository = DefaultAuthRepository(persistence: fixture.store)
        let gate = AuthOperationTestGate()
        let service = commands(
            store: fixture.store,
            repository: FlowRestoreRepository(base: repository, gate: gate, hop: .snapshot)
        )
        let task = Task { try await service.restore() }
        await gate.waitUntilPaused()
        switch action {
        case "lock": try await repository.lock()
        case "logout": try await repository.logout()
        default:
            _ = try fixture.store.saveSession(
                account: .fixture(userID: "replacement"),
                tokens: TokenPair(
                    accessToken: "replacement-access",
                    refreshToken: "replacement-refresh",
                    expiresAt: .distantFuture
                )
            )
        }
        await gate.release()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        if action == "replace" { #expect(try fixture.store.loadAccount()?.userId == "replacement") }
        if action == "logout" { #expect(try fixture.store.loadAccount() == nil) }
    }

    @Test
    func domainHandoffIsSingleUseAndRetainsTheSameRevocableResource() async throws {
        let fixture = PasswordFlowFixture(outcomes: [.success(try passwordTokenResponse())])
        guard case let .unlocked(pending) = try await fixture.signIn() else { Issue.record("Expected pending"); return }
        let repository = DefaultAuthRepository(persistence: fixture.store)
        let flow = commands(store: fixture.store, repository: repository)
        let capability: any AuthenticatedSessionCapability = try await flow.prepareHandoff(pending, onExpired: { _ in })
        #expect(capability.account == pending.account)
        try capability.checkAccess()
        try await capability.validateAuthorization()
        await #expect(throws: AuthRepositoryError.invalidTransition) { _ = try await flow.prepareHandoff(
            pending,
            onExpired: { _ in }
        ) }
        try capability.checkAccess()
        await capability.revoke(.lock)
        #expect(!fixture.crypto.resource.isActive)
        #expect(throws: CancellationError.self) { try capability.checkAccess() }
    }

    @Test
    func expiryRevokesRuntimeAndMarksRepositoryBeforeNotifyingAppOwner() async throws {
        let fixture = PasswordFlowFixture(outcomes: [.success(try passwordTokenResponse())])
        guard case let .unlocked(pending) = try await fixture.signIn() else { Issue.record("Expected pending"); return }
        let repository = DefaultAuthRepository(persistence: fixture.store)
        let flow = commands(store: fixture.store, repository: repository)
        let notification = FlowExpiryNotification()
        let capability = try await flow.prepareHandoff(pending, onExpired: { notification.receive($0) })
        let session = try #require(capability as? AuthenticatedSession)
        try await repository.completeUnlock(session.account, sessionID: session.id)
        _ = try fixture.store.save(
            tokens: TokenPair(accessToken: "expired", refreshToken: "fixture-refresh", expiresAt: .distantPast)
        )
        #expect(await session.runtime.getAccessToken() == nil)
        #expect(await notification.wait() == session.id)
        #expect(await repository.currentSnapshot().state == .expiring(session.account))
        #expect(!fixture.crypto.resource.isActive)
    }
}

enum FlowRestoreHop: Sendable { case restore, snapshot }

private actor FlowRestoreRepository: AuthRepository {
    let base: DefaultAuthRepository
    let gate: AuthOperationTestGate
    let hop: FlowRestoreHop
    init(base: DefaultAuthRepository, gate: AuthOperationTestGate, hop: FlowRestoreHop) {
        self.base = base; self.gate = gate; self.hop = hop
    }

    func sessionStates() async -> AsyncStream<AuthSessionSnapshot> { await base.sessionStates() }
    func currentSnapshot() async -> AuthSessionSnapshot {
        let snapshot = await base.currentSnapshot()
        if hop == .snapshot { await gate.pause() }
        return snapshot
    }

    func restore() async throws -> SessionState {
        let state = try await base.restore()
        if hop == .restore { await gate.pause() }
        return state
    }

    func beginUnlock(account: AccountSession) async throws { try await base.beginUnlock(account: account) }
    func completeUnlock(_ account: AccountSession, sessionID: UUID) async throws -> AuthSessionSnapshot { try await base.completeUnlock(
        account,
        sessionID: sessionID
    ) }
    func unlockFailed(account: AccountSession) async { await base.unlockFailed(account: account) }
    func markExpiring(sessionID: UUID) async { await base.markExpiring(sessionID: sessionID) }
    func lock() async throws { try await base.lock() }
    func logout() async throws { try await base.logout() }
}

@MainActor
private final class FlowExpiryNotification {
    private var id: UUID?
    private var waiter: CheckedContinuation<UUID, Never>?
    func receive(_ id: UUID) { self.id = id; waiter?.resume(returning: id); waiter = nil }
    func wait() async -> UUID {
        if let id { return id }
        return await withCheckedContinuation { waiter = $0 }
    }
}
