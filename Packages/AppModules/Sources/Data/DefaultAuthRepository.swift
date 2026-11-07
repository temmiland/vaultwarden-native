import Domain
import Foundation

/// App-wide auth/session state authority. Credential entry and cryptography stay behind the
/// existing feature/SDK adapters; only typed account state crosses this boundary.
public actor DefaultAuthRepository: AuthRepository {
    private let persistence: any AuthSessionLifecycleStore
    private var state: SessionState = .signedOut
    private var currentSessionID: UUID?
    private var revision: UInt64 = 0
    private var transition: AuthSessionTransition = .initial
    private enum Cleanup { case lock, logout }
    private var pendingCleanup: Cleanup?
    private var observers: [UUID: AsyncStream<AuthSessionSnapshot>.Continuation] = [:]

    public init(persistence: any AuthSessionLifecycleStore) { self.persistence = persistence }

    public func sessionStates() -> AsyncStream<AuthSessionSnapshot> {
        let id = UUID()
        return AsyncStream { continuation in
            observers[id] = continuation
            continuation.yield(currentSnapshot())
            continuation.onTermination = { [weak self] _ in Task { await self?.removeObserver(id) } }
        }
    }

    public func currentSnapshot() -> AuthSessionSnapshot {
        AuthSessionSnapshot(
            state: state,
            sessionID: currentSessionID,
            revision: revision,
            transition: transition
        )
    }

    public func restore() throws -> SessionState {
        // A failed logout may leave the private account on disk. Do not reinterpret that
        // remainder as a new locked account or accept it until explicit cleanup succeeds.
        guard pendingCleanup == nil else { return state }
        guard case .signedOut = state else { return state }
        try persistence.recoverPendingCleanup()
        if let account = try persistence.restoreAccount() { state = .locked(account) }
        else { state = .signedOut }
        publish(.restored)
        return state
    }

    public func beginUnlock(account expected: AccountSession) throws {
        guard pendingCleanup == nil else { throw AuthRepositoryError.invalidTransition }
        guard case let .locked(account) = state else {
            if case let .unlocking(account) = state, account == expected { return }
            throw AuthRepositoryError.invalidTransition
        }
        guard account == expected else { throw AuthRepositoryError.accountChanged }
        state = .unlocking(account)
        publish(.unlockStarted)
    }

    /// Fresh login may complete from signedOut; a returning login must match the exact account
    /// currently unlocking. Session IDs make delayed expiration events harmless after re-unlock.
    @discardableResult
    public func completeUnlock(_ account: AccountSession, sessionID: UUID) throws -> AuthSessionSnapshot {
        guard pendingCleanup == nil else { throw AuthRepositoryError.staleSession }
        guard try persistence.restoreAccount() == account else { throw AuthRepositoryError.staleSession }
        switch state {
        case let .unlocking(expected) where expected == account:
            break
        case .signedOut, .locked:
            break
        case let .unlocked(current) where current == account && currentSessionID == sessionID:
            return currentSnapshot()
        default:
            throw AuthRepositoryError.accountChanged
        }
        state = .unlocked(account)
        currentSessionID = sessionID
        publish(.unlockCompleted)
        return currentSnapshot()
    }

    public func unlockFailed(account expected: AccountSession) {
        guard case let .unlocking(account) = state, account == expected else { return }
        state = .locked(account)
        currentSessionID = nil
        publish(.unlockFailed)
    }

    public func markExpiring(sessionID: UUID) {
        guard currentSessionID == sessionID, case let .unlocked(account) = state else { return }
        state = .expiring(account)
        publish(.expiring)
    }

    public func lock() throws {
        guard pendingCleanup != .logout else { throw AuthRepositoryError.invalidTransition }
        let account: AccountSession
        switch state {
        case let .unlocked(value), let .expiring(value), let .unlocking(value), let .locked(value): account = value
        case .signedOut:
            pendingCleanup = .lock
            try persistence.lockSession()
            pendingCleanup = nil
            return
        }
        // State becomes locked before cleanup so observers immediately stop presenting unlocked UI.
        state = .locked(account)
        currentSessionID = nil
        publish(.locked)
        pendingCleanup = .lock
        try persistence.lockSession()
        pendingCleanup = nil
    }

    public func logout() throws {
        pendingCleanup = .logout
        state = .signedOut
        currentSessionID = nil
        publish(.loggedOut)
        try persistence.clearSession()
        pendingCleanup = nil
    }

    private func publish(_ transition: AuthSessionTransition) {
        revision += 1
        self.transition = transition
        let snapshot = currentSnapshot()
        for continuation in observers.values { continuation.yield(snapshot) }
    }

    private func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }
}
