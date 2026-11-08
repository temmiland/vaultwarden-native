import Domain
import Foundation
import Observation
import os

private let sessionSecurityLogger = Logger(subsystem: "Vaultwarden", category: "SessionSecurity")

private func reportSecurityFailure(_ operation: String, error: Error) {
    let failure = error as NSError
    sessionSecurityLogger.error(
        "\(operation, privacy: .public): domain=\(failure.domain, privacy: .public) code=\(failure.code, privacy: .public)"
    )
}

public enum AppScenePhase: Sendable { case active, inactive, background }
public enum AppTimeoutAction: Sendable, Equatable { case lock, logOut }
public enum AppModelSecurityAction: Sendable, Equatable { case lock, logout }

@MainActor
public protocol AppTimeoutDriving: AnyObject {
    func noteBecameActive() throws
    func noteBecameInactive() throws
    func pendingAppAction() throws -> AppTimeoutAction?
}

/// One Domain runtime contract shared with Auth handoff. The app shell may wrap it with its
/// repository assembly; no SDK type or token enters AppFeature.
public typealias AppSessionResource = AuthenticatedSessionCapability

public enum AppModelState<Session: AppSessionResource> {
    case restoring
    case signedOut
    case locked(AccountSession)
    case unlocking(AccountSession)
    case preparingSession(Session)
    case unlocked(Session)
    case securityRecovery(AppModelSecurityAction)
}

/// One observable authority for app-visible session state, timeout and secure cleanup. The
/// credential-entry coordinator owns its routes; it hands an authenticated capability here once.
@MainActor
@Observable
public final class AppModel<Session: AppSessionResource> {
    public private(set) var state: AppModelState<Session> = .restoring
    public var securityErrorMessage: String?
    public private(set) var pendingSecurityAction: AppModelSecurityAction?
    public private(set) var isPerformingSecurityAction = false

    @ObservationIgnored private let authRepository: any AuthRepository
    @ObservationIgnored private let timeoutDriver: any AppTimeoutDriving
    @ObservationIgnored private let prepareAuthenticatedSession: @Sendable () async throws -> Void
    @ObservationIgnored private let cleanUpTemporaryFiles: @Sendable () async throws -> Void
    @ObservationIgnored private var preparingSession: Session?
    @ObservationIgnored private var preparationTask: Task<Void, Error>?
    @ObservationIgnored private var repositoryEventsTask: Task<Void, Never>?
    @ObservationIgnored private var observationStarted = false
    @ObservationIgnored private var lastRepositoryRevision: UInt64?
    @ObservationIgnored private var authenticationEpoch: UInt64 = 0
    @ObservationIgnored private var recoveryAccount: AccountSession?

    public init(
        authRepository: any AuthRepository,
        timeoutDriver: any AppTimeoutDriving,
        prepareAuthenticatedSession: @escaping @Sendable () async throws -> Void,
        cleanUpTemporaryFiles: @escaping @Sendable () async throws -> Void
    ) {
        self.authRepository = authRepository
        self.timeoutDriver = timeoutDriver
        self.prepareAuthenticatedSession = prepareAuthenticatedSession
        self.cleanUpTemporaryFiles = cleanUpTemporaryFiles
    }

    deinit {
        repositoryEventsTask?.cancel()
        preparationTask?.cancel()
    }

    public var session: Session? {
        if case let .unlocked(session) = state { return session }
        return nil
    }

    public func start() async {
        guard !observationStarted else { return }
        observationStarted = true
        let stream = await authRepository.sessionStates()
        repositoryEventsTask = Task { @MainActor [weak self] in
            for await snapshot in stream {
                guard !Task.isCancelled else { return }
                await self?.acceptRepositoryState(snapshot)
            }
        }
    }

    public func didAuthenticate(_ session: Session) async {
        if self.session?.id == session.id || preparingSession?.id == session.id { return }
        guard self.session == nil, pendingSecurityAction == nil, preparingSession == nil else {
            await session.revoke(.lock)
            return
        }

        let epoch = authenticationEpoch
        preparingSession = session
        state = .preparingSession(session)
        defer {
            if preparingSession?.id == session.id {
                preparingSession = nil
                preparationTask = nil
            }
        }

        let prepare = prepareAuthenticatedSession
        let task = Task { try await prepare() }
        preparationTask = task
        var preparationError: String?
        do {
            try await withTaskCancellationHandler {
                try await task.value
            } onCancel: { task.cancel() }
        } catch {
            preparationError = "Couldn't prepare secure attachment storage. Attachment files will stay unavailable until cleanup succeeds."
        }

        guard ownsHandoff(session, epoch: epoch) else {
            await session.revoke(.lock)
            return
        }
        do {
            try session.checkAccess()
            try await session.validateAuthorization()
            guard ownsHandoff(session, epoch: epoch) else {
                await session.revoke(.lock)
                return
            }
            let completed = try await authRepository.completeUnlock(session.account, sessionID: session.id)
            try await session.validateAuthorization()
            let current = await authRepository.currentSnapshot()
            guard ownsHandoff(session, epoch: epoch) else {
                await session.revoke(.lock)
                return
            }
            if current.sessionID == session.id, case .expiring = current.state {
                await secureSession(.logout)
                return
            }
            guard current.sessionID == session.id, current.state == .unlocked(session.account),
                  current.revision >= completed.revision else {
                throw AuthRepositoryError.staleSession
            }
            try session.checkAccess()
            rememberRevision(current.revision)
        } catch {
            guard ownsHandoff(session, epoch: epoch) else {
                await session.revoke(.lock)
                return
            }
            let failed = await authRepository.currentSnapshot()
            guard ownsHandoff(session, epoch: epoch) else {
                await session.revoke(.lock)
                return
            }
            if failed.sessionID == session.id, case .expiring = failed.state {
                await secureSession(.logout)
            } else {
                await secureSession(.lock)
            }
            if pendingSecurityAction == nil {
                securityErrorMessage = "Couldn't prepare the unlocked session. Authenticate again."
            }
            return
        }

        // No suspension between the final epoch/access checks and publication.
        securityErrorMessage = preparationError
        state = .unlocked(session)
    }

    public func lockNow() async { await secureSession(.lock) }
    public func logOut() async { await secureSession(.logout) }

    public func sessionExpired(_ id: UUID) async {
        guard session?.id == id || preparingSession?.id == id else { return }
        await secureSession(.logout)
    }

    public func retrySecurityAction() async {
        guard let pendingSecurityAction else { return }
        await secureSession(pendingSecurityAction)
    }

    private func ownsHandoff(_ session: Session, epoch: UInt64) -> Bool {
        epoch == authenticationEpoch && pendingSecurityAction == nil
            && preparingSession?.id == session.id
    }

    private func secureSession(_ requestedAction: AppModelSecurityAction) async {
        if isPerformingSecurityAction {
            // A logout requested during lock cleanup must not disappear behind the in-flight gate.
            if requestedAction == .logout {
                pendingSecurityAction = .logout
                state = .securityRecovery(.logout)
            }
            return
        }
        let oldSession = session ?? preparingSession
        recoveryAccount = oldSession?.account ?? currentAccount
        let preparing = preparationTask
        preparing?.cancel()
        preparingSession = nil
        preparationTask = nil
        authenticationEpoch += 1
        pendingSecurityAction = pendingSecurityAction == .logout ? .logout : requestedAction
        isPerformingSecurityAction = true
        defer { isPerformingSecurityAction = false }

        while let action = pendingSecurityAction {
            securityErrorMessage = nil
            state = .securityRecovery(action)
            // Runtime revocation cancels secret tasks before persistent capability cleanup.
            await oldSession?.revoke(action == .lock ? .lock : .logout)
            var failures: [String] = []
            do {
                switch action {
                case .lock: try await authRepository.lock()
                case .logout: try await authRepository.logout()
                }
            } catch {
                reportSecurityFailure("Persistent session cleanup failed", error: error)
                failures.append("Saved session or AutoFill access couldn't be securely cleared.")
            }
            let snapshot = await authRepository.currentSnapshot()
            rememberRevision(snapshot.revision)
            // Even noncooperative preparation must finish before final cleanup closes temp access.
            _ = try? await preparing?.value
            do { try await cleanUpTemporaryFiles() }
            catch { failures.append("Sensitive attachment files couldn't be removed.") }

            if action == .lock, pendingSecurityAction == .logout { continue }
            guard failures.isEmpty else {
                securityErrorMessage = failures.joined(separator: " ") + " Retry secure cleanup before unlocking again."
                return
            }
            pendingSecurityAction = nil
            if action == .lock, let account = recoveryAccount { state = .locked(account) }
            else { state = .signedOut }
            recoveryAccount = nil
        }
    }

    public func scenePhaseChanged(to phase: AppScenePhase) async {
        switch phase {
        case .active:
            await applyPendingTimeoutAction()
            do { try timeoutDriver.noteBecameActive() }
            catch {
                reportSecurityFailure("Shared timeout activation failed", error: error)
                await lockNow()
                let lockError = securityErrorMessage
                securityErrorMessage = "Couldn't update the shared AutoFill timeout, so a safety lock was requested. "
                    + (lockError ?? "Retry secure cleanup before unlocking again.")
            }
        case .inactive, .background:
            do { try timeoutDriver.noteBecameInactive() }
            catch {
                reportSecurityFailure("Shared timeout deactivation failed", error: error)
                await lockNow()
                let lockError = securityErrorMessage
                securityErrorMessage = "Couldn't persist the AutoFill timeout, so a safety lock was requested. "
                    + (lockError ?? "Retry secure cleanup before unlocking again.")
                return
            }
            await applyPendingTimeoutAction()
        }
    }

    public func applyPendingTimeoutAction() async {
        guard session != nil else { return }
        let action: AppTimeoutAction
        do {
            guard let pending = try timeoutDriver.pendingAppAction() else { return }
            action = pending
        } catch {
            await lockNow()
            let lockError = securityErrorMessage
            securityErrorMessage = "Couldn't read the vault timeout setting, so a safety lock was requested. "
                + (lockError ?? "Review the setting in Settings before unlocking again.")
            return
        }
        switch action {
        case .lock: await lockNow()
        case .logOut: await logOut()
        }
    }

    private var currentAccount: AccountSession? {
        switch state {
        case let .locked(account), let .unlocking(account): account
        case let .preparingSession(session), let .unlocked(session): session.account
        case .securityRecovery: recoveryAccount
        case .restoring, .signedOut: nil
        }
    }

    private func rememberRevision(_ revision: UInt64) {
        lastRepositoryRevision = max(lastRepositoryRevision ?? 0, revision)
    }

    private func acceptRepositoryState(_ snapshot: AuthSessionSnapshot) async {
        if let lastRepositoryRevision, snapshot.revision <= lastRepositoryRevision { return }
        rememberRevision(snapshot.revision)
        guard pendingSecurityAction == nil else { return }
        switch snapshot.state {
        case .signedOut:
            if snapshot.transition == .loggedOut, session != nil || preparingSession != nil {
                await secureSession(.logout)
            } else if session == nil, preparingSession == nil { state = .signedOut }
        case let .locked(account):
            if snapshot.transition == .locked, session != nil || preparingSession != nil {
                await secureSession(.lock)
            } else if session == nil, preparingSession == nil { state = .locked(account) }
        case let .unlocking(account):
            if session == nil, preparingSession == nil { state = .unlocking(account) }
        case let .unlocked(account):
            if let session, session.id == snapshot.sessionID, session.account == account {
                state = .unlocked(session)
            } else if preparingSession == nil, session == nil {
                // Metadata alone never authorizes main content. Close an orphaned capability.
                state = .locked(account)
                await secureSession(.lock)
            }
        case .expiring:
            if let id = snapshot.sessionID, id == session?.id || id == preparingSession?.id {
                await secureSession(.logout)
            }
        }
    }
}
