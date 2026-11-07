import Data
import Foundation
import Testing

/// Pure fixtures: no SDK, real Keychain, signed container, network or wall-clock sleeps.
@Suite
struct TokenCoordinatorTests {
    private let time = Date(timeIntervalSince1970: 1_800_000_000)
    private var scope: TokenScope {
        TokenScope(
            account: TokenAccountIdentity(userID: "test-user", serverBaseURL: URL(string: "https://vault.example.com")!)
        )
    }

    private func tokens(generation: UInt64 = 1, expired: Bool = true) -> TokenPair {
        TokenPair(
            accessToken: "test-access-\(generation)",
            refreshToken: "test-refresh-\(generation)",
            expiresAt: expired ? time.addingTimeInterval(-60) : time.addingTimeInterval(3600),
            generation: generation
        )
    }

    private var success: TokenRefreshOutcome {
        .success(
            RefreshedTokenPayload(
                accessToken: "test-rotated-access",
                refreshToken: "test-rotated-refresh",
                expiresIn: 3600
            )
        )
    }

    private func coordinator(
        _ store: CoordinatorStore,
        _ service: any TokenRefreshing,
        clock: CoordinatorClock? = nil
    ) -> TokenCoordinator {
        let date = time
        return TokenCoordinator(
            scope: store.currentScope,
            identityURL: URL(string: "https://vault.example.com/identity")!,
            persistence: store,
            refreshService: service,
            now: { clock?.now ?? date }
        )
    }

    @Test
    func validCachedTokensDoNotRefresh() async {
        let store = CoordinatorStore(scope: scope, tokens: tokens(expired: false))
        let service = ImmediateRefreshService(outcomes: [success])
        let subject = coordinator(store, service)
        #expect(await subject.getAccessToken() == "test-access-1")
        #expect(await service.callCount == 0)
        #expect(store.commitCount == 0)
    }

    @Test
    func concurrentLookupsShareOneRefreshAndOneCommit() async {
        let store = CoordinatorStore(scope: scope, tokens: tokens())
        let service = PausedRefreshService(outcome: success)
        let subject = coordinator(store, service)
        let lookups = (0 ..< 16).map { _ in Task { await subject.getAccessToken() } }
        await store.waitForLoads(16)
        await service.waitForCalls(1)
        await service.releaseAll()
        for lookup in lookups { #expect(await lookup.value == "test-rotated-access") }
        #expect(await service.callCount == 1)
        #expect(store.commitCount == 1)
        #expect(store.currentTokens.generation == 2)
    }

    @Test
    func cancellingOneWaiterDoesNotCancelAnotherWaitersRefresh() async {
        let store = CoordinatorStore(scope: scope, tokens: tokens())
        let service = PausedRefreshService(outcome: success)
        let subject = coordinator(store, service)
        let cancelled = Task { await subject.getAccessToken() }
        let retained = Task { await subject.getAccessToken() }
        await store.waitForLoads(2)
        await service.waitForCalls(1)
        cancelled.cancel()
        await service.releaseAll()
        #expect(await cancelled.value == nil)
        #expect(await retained.value == "test-rotated-access")
        #expect(await service.callCount == 1)
        #expect(store.commitCount == 1)
    }

    @Test
    func revocationDeniesANoncooperativeLateResponseAndNeverReopens() async {
        let store = CoordinatorStore(scope: scope, tokens: tokens())
        let service = PausedRefreshService(outcome: success)
        let subject = coordinator(store, service)
        let pending = Task { await subject.getAccessToken() }
        await service.waitForCalls(1)
        await subject.revoke()
        await service.releaseAll()
        #expect(await pending.value == nil)
        #expect(await subject.getAccessToken() == nil)
        #expect(store.commitCount == 0)
        #expect(store.currentTokens.generation == 1)
    }

    @Test
    func aLineageChangeCannotBeAdoptedOrReopenedByRestoringAnOlderRecord() async {
        let originalScope = scope
        let store = CoordinatorStore(scope: originalScope, tokens: tokens())
        let service = PausedRefreshService(outcome: success)
        let subject = coordinator(store, service)
        let pending = Task { await subject.getAccessToken() }
        await service.waitForCalls(1)
        store.replace(scope: scope, tokens: tokens(generation: 20, expired: false))
        await service.releaseAll()
        #expect(await pending.value == nil)
        #expect(store.commitCount == 0)
        store.replace(scope: originalScope, tokens: tokens(expired: false))
        #expect(await subject.getAccessToken() == nil)
    }

    @Test
    func anOldRejectionDoesNotExpireANewerWinningRotation() async throws {
        let store = CoordinatorStore(scope: scope, tokens: tokens())
        let service = PausedRefreshService(outcome: .rejected)
        let subject = coordinator(store, service)
        let expiry = CoordinatorExpiryProbe()
        await subject.setSessionExpiredHandler { expiry.record() }
        let pending = Task { await subject.getAccessToken() }
        await service.waitForCalls(1)
        store.replace(tokens: tokens(generation: 2, expired: false))
        await service.releaseAll()
        #expect(await pending.value == "test-access-2")
        #expect(expiry.count == 0)
        #expect(try await subject.validatedScope() == store.currentScope)
    }

    @Test
    func explicitRejectionExpiresOnceAndDeniesFurtherRefreshes() async {
        let store = CoordinatorStore(scope: scope, tokens: tokens())
        let service = ImmediateRefreshService(outcomes: [.rejected])
        let subject = coordinator(store, service)
        let expiry = CoordinatorExpiryProbe()
        await subject.setSessionExpiredHandler { expiry.record() }
        #expect(await subject.getAccessToken() == nil)
        #expect(await subject.getAccessToken() == nil)
        #expect(await service.callCount == 1)
        #expect(expiry.count == 1)
        #expect(store.commitCount == 0)
    }

    @Test
    func retryAfterSuppressesRequestsWithoutExpiringOrSleeping() async throws {
        let clock = CoordinatorClock(time)
        let store = CoordinatorStore(scope: scope, tokens: tokens())
        let service = ImmediateRefreshService(outcomes: [.retryable(.http(statusCode: 429, retryAfter: 60)), success])
        let subject = coordinator(store, service, clock: clock)
        let expiry = CoordinatorExpiryProbe()
        await subject.setSessionExpiredHandler { expiry.record() }
        #expect(await subject.getAccessToken() == nil)
        clock.advance(59)
        #expect(await subject.getAccessToken() == nil)
        #expect(await service.callCount == 1)
        #expect(try await subject.validatedScope() == store.currentScope)
        clock.advance(2)
        #expect(await subject.getAccessToken() == "test-rotated-access")
        #expect(await service.callCount == 2)
        #expect(expiry.count == 0)
    }

    @Test
    func anOldWaiterCannotEraseAJobForANewerGeneration() async {
        let store = CoordinatorStore(scope: scope, tokens: tokens())
        let service = PausedRefreshService(outcome: success)
        let subject = coordinator(store, service)
        let old = Task { await subject.getAccessToken() }
        await service.waitForCalls(1)
        store.replace(tokens: tokens(generation: 2))
        let next = Task { await subject.getAccessToken() }
        await service.waitForCalls(2)
        await service.release(1)
        #expect(await old.value == nil)
        let joining = Task { await subject.getAccessToken() }
        await store.waitForLoads(3)
        await service.releaseAll()
        #expect(await next.value == "test-rotated-access")
        #expect(await joining.value == "test-rotated-access")
        #expect(await service.callCount == 2)
        #expect(store.commitCount == 1)
        #expect(store.currentTokens.generation == 3)
    }

    @Test
    func missingRefreshRotationRetainsTheOriginalRefreshToken() async {
        let store = CoordinatorStore(scope: scope, tokens: tokens())
        let service = ImmediateRefreshService(outcomes: [.success(RefreshedTokenPayload(
            accessToken: "test-access-next", refreshToken: nil, expiresIn: 3600
        ))])
        let subject = coordinator(store, service)
        #expect(await subject.getAccessToken() == "test-access-next")
        #expect(store.currentTokens.refreshToken == "test-refresh-1")
    }

    @Test
    func anUncommittableGenerationNeverConsumesAServerRefreshToken() async {
        let store = CoordinatorStore(scope: scope, tokens: tokens(generation: .max))
        let service = ImmediateRefreshService(outcomes: [success])
        let subject = coordinator(store, service)
        #expect(await subject.getAccessToken() == nil)
        #expect(await service.callCount == 0)
        #expect(store.commitCount == 0)
    }

    @Test
    func anUnexpectedIdentityEndpointCannotReceiveCredentials() async {
        let store = CoordinatorStore(scope: scope, tokens: tokens())
        let service = ImmediateRefreshService(outcomes: [success])
        let subject = TokenCoordinator(
            scope: store.currentScope,
            identityURL: URL(string: "https://foreign.example.com/identity")!,
            persistence: store,
            refreshService: service
        )
        #expect(await subject.getAccessToken() == nil)
        #expect(await service.callCount == 0)
    }

    @Test
    func aReadOutageDoesNotInventAScopeChangeOrExpireTheSession() async {
        let store = CoordinatorStore(scope: scope, tokens: tokens(expired: false))
        let service = ImmediateRefreshService(outcomes: [success])
        let subject = coordinator(store, service)
        store.setReadFailure(true)
        #expect(await subject.getAccessToken() == nil)
        store.setReadFailure(false)
        #expect(await subject.getAccessToken() == "test-access-1")
        #expect(await service.callCount == 0)
    }

    @Test
    func aTransportFailureDoesNotExpireOrPermanentlyRevokeTheCoordinator() async throws {
        let store = CoordinatorStore(scope: scope, tokens: tokens())
        let subject = coordinator(store, ThrowingRefreshService())
        let expiry = CoordinatorExpiryProbe()
        await subject.setSessionExpiredHandler { expiry.record() }
        #expect(await subject.getAccessToken() == nil)
        #expect(try await subject.validatedScope() == store.currentScope)
        #expect(expiry.count == 0)
        #expect(store.commitCount == 0)
    }
}

private final class CoordinatorStore: TokenPersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var scope: TokenScope
    private var tokens: TokenPair
    private var commits = 0
    private var loads = 0
    private var readFailure = false
    private var loadWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    init(scope: TokenScope, tokens: TokenPair) { self.scope = scope; self.tokens = tokens }
    var currentScope: TokenScope { lock.withLock { scope } }
    var currentTokens: TokenPair { lock.withLock { tokens } }
    var commitCount: Int { lock.withLock { commits } }
    // This fixture exercises actor job replacement, not process serialization. Live adapters
    // require a file lease; integration tests use real independent SharedTokenStore instances.
    func withRefreshLease<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        try await operation()
    }

    func beginRefresh(requiringScope scope: TokenScope, generation: UInt64) throws -> TokenRefreshIntent? {
        guard currentScope == scope, currentTokens.generation == generation else { return nil }
        return TokenRefreshIntent(scope: scope, generation: generation, publicationEpoch: UUID())
    }

    func finishRefresh(_ intent: TokenRefreshIntent) throws {}
    func isCurrentScope(_ scope: TokenScope) throws -> Bool {
        try lock.withLock {
            if readFailure { throw CoordinatorFixtureError.unavailable }
            return self.scope == scope
        }
    }

    func load(requiringScope scope: TokenScope) throws -> TokenPair? {
        lock.withLock {
            loads += 1
            let ready = loadWaiters.filter { $0.0 <= loads }
            loadWaiters.removeAll { $0.0 <= loads }
            for (_, continuation) in ready { continuation.resume() }
            return self.scope == scope ? tokens : nil
        }
    }

    func commitRefresh(_ tokens: TokenPair, basedOnGeneration generation: UInt64, requiringScope scope: TokenScope) throws -> TokenPair? {
        lock.withLock {
            guard self.scope == scope else { return nil }
            if self.tokens.generation > generation { return self.tokens }
            guard self.tokens.generation == generation, generation < UInt64.max, tokens.generation == generation + 1 else { return nil }
            commits += 1
            self.tokens = tokens
            return tokens
        }
    }

    func replace(scope: TokenScope? = nil, tokens: TokenPair) {
        lock.withLock { if let scope { self.scope = scope }; self.tokens = tokens }
    }

    func setReadFailure(_ value: Bool) { lock.withLock { readFailure = value } }
    func waitForLoads(_ count: Int) async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if loads >= count { continuation.resume() }
                else { loadWaiters.append((count, continuation)) }
            }
        }
    }
}

private actor ImmediateRefreshService: TokenRefreshing {
    private var outcomes: [TokenRefreshOutcome]
    private(set) var callCount = 0
    init(outcomes: [TokenRefreshOutcome]) { self.outcomes = outcomes }
    func refreshToken(identityURL: URL, refreshToken: String) async throws -> TokenRefreshOutcome {
        callCount += 1
        return outcomes.isEmpty ? .retryable(.transport) : outcomes.removeFirst()
    }
}

private enum CoordinatorFixtureError: Error { case unavailable }
private struct ThrowingRefreshService: TokenRefreshing {
    func refreshToken(identityURL: URL, refreshToken: String) async throws -> TokenRefreshOutcome {
        throw CoordinatorFixtureError.unavailable
    }
}

private actor PausedRefreshService: TokenRefreshing {
    let outcome: TokenRefreshOutcome
    private(set) var callCount = 0
    private var paused: [Int: CheckedContinuation<Void, Never>] = [:]
    private var startWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var allReleased = false
    init(outcome: TokenRefreshOutcome) { self.outcome = outcome }
    func refreshToken(identityURL: URL, refreshToken: String) async throws -> TokenRefreshOutcome {
        callCount += 1
        let call = callCount
        if !allReleased {
            await withCheckedContinuation { continuation in
                paused[call] = continuation
                let ready = startWaiters.filter { $0.0 <= callCount }
                startWaiters.removeAll { $0.0 <= callCount }
                for (_, waiter) in ready { waiter.resume() }
            }
        }
        return outcome // intentionally ignores cancellation, as a noncooperative transport might
    }

    func waitForCalls(_ count: Int) async {
        if callCount >= count { return }
        await withCheckedContinuation { startWaiters.append((count, $0)) }
    }

    func release(_ call: Int) { paused.removeValue(forKey: call)?.resume() }
    func releaseAll() {
        allReleased = true
        let waiters = paused.values
        paused = [:]
        for waiter in waiters { waiter.resume() }
    }
}

private final class CoordinatorClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    var now: Date { lock.withLock { date } }
    func advance(_ interval: TimeInterval) { lock.withLock { date.addTimeInterval(interval) } }
}

private final class CoordinatorExpiryProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func record() { lock.withLock { value += 1 } }
}
