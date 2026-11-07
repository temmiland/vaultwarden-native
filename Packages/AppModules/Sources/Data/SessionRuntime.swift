import Domain
import Foundation

/// Persistence needed by the auth state machine. Platform/legacy Keychain composition stays in
/// its adapter; the repository never receives SDK types or secrets.
public protocol AuthSessionLifecycleStore: Sendable {
    func restoreAccount() throws -> AccountSession?
    func recoverPendingCleanup() throws
    func lockSession() throws
    func clearSession() throws
}

public extension AuthSessionLifecycleStore {
    /// Explicit fixture/default policy. Production AuthCredentialStore persists/replays intent.
    func recoverPendingCleanup() throws {}
}

/// Scoped capability used by SessionRuntime and the live Data.TokenCoordinator/SDK bridges.
/// Revocation must deny new lookups and prevent an in-flight refresh from persisting afterwards.
public protocol SessionTokenProviding: Sendable {
    func getAccessToken() async -> String?
    func requireAccessToken() async throws -> String
    func validatedSessionScope() async throws -> TokenScope
    func revoke() async
}

public extension SessionTokenProviding {
    func requireAccessToken() async throws -> String {
        try Task.checkCancellation()
        guard let token = await getAccessToken() else { throw SessionAuthorizationError.temporarilyUnavailable }
        try Task.checkCancellation()
        return token
    }

    func validatedSessionScope() async throws -> TokenScope { throw CancellationError() }
}

/// Live lifetime owner for an already authenticated session. `DefaultAuthRepository` owns the
/// cross-screen auth state machine; this actor owns the revocable resource and its operations.
public actor SessionRuntime {
    public nonisolated let id: UUID
    public nonisolated let account: AccountSession
    private nonisolated let resource: any SessionResource
    private let tokens: any SessionTokenProviding
    private var state: SessionState
    private var observers: [UUID: AsyncStream<SessionState>.Continuation] = [:]
    private var revocationTask: Task<Void, Never>?
    private var revocationReason: SessionRevocationReason?
    private var operations: [UUID: @Sendable () -> Void] = [:]

    public init(account: AccountSession, resource: any SessionResource, tokens: any SessionTokenProviding) {
        id = UUID()
        self.account = account
        self.resource = resource
        self.tokens = tokens
        state = .unlocked(account)
    }

    public nonisolated func checkAccess() throws {
        try Task.checkCancellation()
        try checkSessionActive()
    }

    /// Revalidates revocation lineage without treating cancellation of a UI waiter as revocation.
    /// Repository-owned mutation tasks use this after a server acknowledgement so caller
    /// cancellation cannot skip local projection or the result confirmation.
    public nonisolated func checkSessionActive() throws {
        guard resource.isActive else { throw CancellationError() }
    }

    public func getAccessToken() async -> String? {
        guard (try? checkAccess()) != nil else { return nil }
        let token = await tokens.getAccessToken()
        guard (try? checkAccess()) != nil else { return nil }
        return token
    }

    public func requireAccessToken() async throws -> String {
        try checkAccess()
        let token = try await tokens.requireAccessToken()
        try checkAccess()
        return token
    }

    public func validatedTokenScope() async throws -> TokenScope {
        try checkAccess()
        let scope = try await tokens.validatedSessionScope()
        try checkAccess()
        let scopedServer = try? Domain.ServerEnvironment(baseURL: scope.account.serverBaseURL).baseURL
        guard scope.account.userID == account.accountID.rawValue,
              scopedServer == account.environment.baseURL
        else { throw CancellationError() }
        return scope
    }

    /// Per-request child tasks allow lock/logout to cancel transport work, even when its feature
    /// view still retains the calling task. A non-cooperative dependency's late value is rejected.
    /// Cancellation cannot undo a mutation that the server has already accepted.
    public func perform<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try checkAccess()
        let id = UUID()
        let task = Task { try await operation() }
        operations[id] = { task.cancel() }
        defer { operations.removeValue(forKey: id) }
        do {
            let value = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            try checkAccess()
            return value
        } catch {
            try checkAccess()
            throw error
        }
    }

    /// Resource invalidation happens before the first suspension. All callers await the same
    /// token shutdown before persistent lock/logout cleanup may run. Logout/expiry can upgrade a
    /// previous lock, but no transition can reopen this runtime.
    public func revoke(_ reason: SessionRevocationReason) async {
        resource.revoke()
        for cancel in operations.values { cancel() }
        if revocationReason == nil || (revocationReason == .lock && reason != .lock) {
            revocationReason = reason
            state = reason == .lock ? .locked(account) : .signedOut
            publish()
        }
        let task: Task<Void, Never>
        if let revocationTask { task = revocationTask }
        else {
            let tokens = tokens
            task = Task { await tokens.revoke() }
            revocationTask = task
        }
        await task.value
    }

    public func sessionStates() -> AsyncStream<SessionState> {
        let id = UUID()
        return AsyncStream { continuation in
            observers[id] = continuation
            continuation.yield(state)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeObserver(id) }
            }
        }
    }

    public func currentState() -> SessionState { state }

    private func publish() {
        for continuation in observers.values { continuation.yield(state) }
    }

    private func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }
}
