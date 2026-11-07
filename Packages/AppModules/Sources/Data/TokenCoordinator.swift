import Domain
import Foundation

/// The persistence adapter MUST check the exact sign-in scope (and extension proof where
/// relevant), serialize compare-and-write, and return a newer winner rather than overwrite it.
/// Short storage transactions must not perform SDK/network work or suspend. Only the separate
/// asynchronous refresh lease spans network work; lock/logout never acquire that lease.
public protocol TokenPersistence: Sendable {
    func withRefreshLease<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T
    func beginRefresh(requiringScope scope: TokenScope, generation: UInt64) throws -> TokenRefreshIntent?
    func finishRefresh(_ intent: TokenRefreshIntent) throws
    func isCurrentScope(_ scope: TokenScope) throws -> Bool
    func load(requiringScope scope: TokenScope) throws -> TokenPair?
    func commitRefresh(
        _ tokens: TokenPair,
        basedOnGeneration generation: UInt64,
        requiringScope scope: TokenScope
    ) throws -> TokenPair?
}

/// One refresh algorithm for app and extension, instantiated per sign-in/invocation resource.
/// Actor-local single flight joins consumers; live persistence also serializes the complete
/// server request across processes and records uncertain requests durably before transmission.
/// It never rebinds; permanent revocation prevents late network responses from reaching storage.
public actor TokenCoordinator: SessionTokenProviding {
    public nonisolated let scope: TokenScope
    private let identityURL: URL
    private let persistence: any TokenPersistence
    private let refreshService: any TokenRefreshing
    private let now: @Sendable () -> Date
    private var isRevoked = false
    private var onSessionExpired: (@Sendable () -> Void)?
    private var retryWindow: (generation: UInt64, notBefore: Date)?
    private var inFlight: RefreshJob?
    public private(set) var refreshRecoveryRequired = false

    private enum RefreshDisposition: Sendable { case committed, unavailable }
    private struct RefreshJob {
        let id: UUID
        let generation: UInt64
        let task: Task<RefreshDisposition, Never>
    }

    public init(
        scope: TokenScope,
        identityURL: URL,
        persistence: any TokenPersistence,
        refreshService: any TokenRefreshing,
        onSessionExpired: (@Sendable () -> Void)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.scope = scope
        self.identityURL = identityURL
        self.persistence = persistence
        self.refreshService = refreshService
        self.onSessionExpired = onSessionExpired
        self.now = now
    }

    public func setSessionExpiredHandler(_ handler: @escaping @Sendable () -> Void) {
        guard !isRevoked else { return }
        onSessionExpired = handler
    }

    public func validatedScope() throws -> TokenScope {
        try Task.checkCancellation()
        guard !isRevoked, identityURL == scope.account.serverBaseURL.appendingPathComponent("identity")
        else { throw CancellationError() }
        // A classified missing/different authority is a permanent ownership change. A throwing
        // Keychain outage, in contrast, denies this lookup without inventing that transition.
        guard try persistence.isCurrentScope(scope) else { revoke(); throw CancellationError() }
        return scope
    }

    public func revoke() {
        isRevoked = true
        inFlight?.task.cancel()
        inFlight = nil
        retryWindow = nil
        onSessionExpired = nil
    }

    public func getAccessToken() async -> String? {
        let current: TokenPair
        do {
            _ = try validatedScope()
            guard let stored = try persistence.load(requiringScope: scope), isValid(stored) else { return nil }
            current = stored
        } catch { return nil }
        if !current.isExpired(at: now()) { return current.accessToken }
        // Do not consume a rotating server token when its next generation cannot be persisted.
        guard current.generation < UInt64.max else { return nil }
        if let retryWindow, retryWindow.generation == current.generation, now() < retryWindow.notBefore { return nil }
        if retryWindow?.generation != current.generation { retryWindow = nil }

        let job: RefreshJob
        if let running = inFlight, running.generation == current.generation { job = running }
        else {
            // A changed generation invalidates the old response, not the ownership of this actor.
            inFlight?.task.cancel()
            let id = UUID()
            let task = Task<RefreshDisposition, Never> { [weak self] in
                guard let self else { return .unavailable }
                return await performRefresh(id: id, basedOn: current)
            }
            job = RefreshJob(id: id, generation: current.generation, task: task)
            inFlight = job
        }
        let result = await job.task.value
        // An old/cancelled waiter must never erase a newer job started while it was suspended.
        if inFlight?.id == job.id { inFlight = nil }
        guard case .committed = result else { return nil }
        do {
            _ = try validatedScope()
            guard let latest = try persistence.load(requiringScope: scope), isValid(latest),
                  latest.generation > current.generation,
                  !latest.isExpired(at: now()) else { return nil }
            return latest.accessToken
        } catch { return nil }
    }

    public func requireAccessToken() async throws -> String {
        if let token = await getAccessToken() { return token }
        try Task.checkCancellation()
        guard !isRevoked else { throw CancellationError() }
        // A failed commit may itself revoke obsolete extension capabilities (and rotate their
        // epoch). Preserve that typed recovery result instead of turning it into silent UI
        // cancellation. Runtime/explicit coordinator revocation still wins above; no token leaks.
        if refreshRecoveryRequired { throw SessionAuthorizationError.refreshRecoveryRequired }
        _ = try validatedScope()
        throw SessionAuthorizationError.temporarilyUnavailable
    }

    private func performRefresh(id: UUID, basedOn original: TokenPair) async -> RefreshDisposition {
        do {
            return try await persistence.withRefreshLease { [self] in
                try await refreshUnderLease(id: id, basedOn: original)
            }
        } catch TokenRefreshRecoveryError.unconfirmedRotation {
            refreshRecoveryRequired = true
            return .unavailable
        } catch { return .unavailable }
    }

    private func refreshUnderLease(id: UUID, basedOn original: TokenPair) async throws -> RefreshDisposition {
        _ = try validatedScope()
        guard inFlight?.id == id,
              let latest = try persistence.load(requiringScope: scope), isValid(latest),
              latest.generation >= original.generation else { return .unavailable }
        // Another process may have rotated while this job waited for the network lease.
        if latest.generation > original.generation {
            return latest.isExpired(at: now()) ? .unavailable : .committed
        }
        guard let intent = try persistence.beginRefresh(requiringScope: scope, generation: original.generation)
        else { return .unavailable }
        let outcome: TokenRefreshOutcome
        do { outcome = try await refreshService.refreshToken(
            identityURL: identityURL,
            refreshToken: original.refreshToken
        ) } catch is CancellationError { outcome = .retryable(.cancelled) }
        catch { outcome = .retryable(.transport) }
        let disposition = completeRefresh(id: id, outcome: outcome, basedOn: original)
        // Only a retained rotation or a classified rejection proves a safe terminal outcome.
        // Ambiguous transport/cancellation/2xx decoding keeps the marker across process death.
        let knownOutcome: Bool
        switch outcome {
        case .rejected: knownOutcome = true
        case let .retryable(.http(status, _)):
            // A proxy timeout or 5xx can lose an already issued rotating pair. Preserve the
            // session (never automatic logout), but don't silently consume the old token again.
            knownOutcome = (400 ... 499).contains(status) && ![408, 409].contains(status)
        case .retryable(.oauthFailure): knownOutcome = true
        case .success: knownOutcome = disposition == .committed
        default: knownOutcome = false
        }
        if knownOutcome { try persistence.finishRefresh(intent) }
        else { refreshRecoveryRequired = true }
        return disposition
    }

    private func completeRefresh(id: UUID, outcome: TokenRefreshOutcome, basedOn original: TokenPair) -> RefreshDisposition {
        guard !isRevoked, !Task.isCancelled, inFlight?.id == id else { return .unavailable }
        do {
            _ = try validatedScope()
            guard let current = try persistence.load(requiringScope: scope), isValid(current),
                  current.generation >= original.generation else { return .unavailable }
            // Even a stale rejection must not expire a newer rotation that another process won.
            if current.generation > original.generation {
                return current.isExpired(at: now()) ? .unavailable : .committed
            }
            switch outcome {
            case .rejected:
                // Deny further lookups immediately, not only when the app's async expiry handler
                // eventually revokes its runtime. No SDK/server cleanup runs on this actor.
                isRevoked = true
                retryWindow = nil
                let handler = onSessionExpired
                onSessionExpired = nil
                handler?()
                return .unavailable
            case let .retryable(reason):
                if case let .http(_, delay?) = reason, delay.isFinite, delay > 0 {
                    let deadline = now().addingTimeInterval(delay)
                    if deadline.timeIntervalSinceReferenceDate.isFinite {
                        retryWindow = (current.generation, deadline)
                    }
                }
                return .unavailable
            case let .success(payload):
                guard payload.isValid, original.generation < UInt64.max else { return .unavailable }
                let date = now()
                let candidate = TokenPair(
                    accessToken: payload.accessToken,
                    refreshToken: payload.refreshToken ?? original.refreshToken,
                    expiresAt: date.addingTimeInterval(TimeInterval(payload.expiresIn)),
                    generation: original.generation + 1,
                    updatedAt: date
                )
                guard isValid(candidate), let committed = try persistence.commitRefresh(
                    candidate,
                    basedOnGeneration: original.generation,
                    requiringScope: scope
                ), isValid(committed),
                committed.generation > original.generation,
                !committed.isExpired(at: now()) else { return .unavailable }
                return .committed
            }
        } catch { return .unavailable }
    }

    private func isValid(_ tokens: TokenPair) -> Bool {
        !tokens.accessToken.isEmpty && !tokens.refreshToken.isEmpty && tokens.generation > 0 &&
            tokens.expiresAt.timeIntervalSinceReferenceDate.isFinite && tokens.updatedAt.timeIntervalSinceReferenceDate.isFinite
    }
}
