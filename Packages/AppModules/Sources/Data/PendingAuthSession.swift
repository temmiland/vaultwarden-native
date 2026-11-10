import BitwardenSDKAdapter
import Domain
import Foundation

/// Domain-visible pending capability. Resource/provider/keys remain private to Data; accepting
/// a handoff transfers their lifetime to SessionRuntime, not to a second SDK resource.
/// All fields are immutable except the single-use handoff flag, protected by handoffLock.
public final class PendingAuthSession: PendingAuthentication, CustomStringConvertible, CustomDebugStringConvertible, @unchecked Sendable {
    public let account: AccountSession
    public var id: UUID { provider.id }
    private let crypto: any AuthCredentialCryptography
    private let provider: AppAuthTokenProvider
    private let store: AuthCredentialStore
    private let handoffLock = NSLock()
    private var handoffStarted = false

    public init(
        account: AccountSession,
        cryptography: any AuthCredentialCryptography,
        provider: AppAuthTokenProvider,
        store: AuthCredentialStore
    ) {
        self.account = account
        crypto = cryptography
        self.provider = provider
        self.store = store
    }

    public func validateAuthorization() async throws {
        try Task.checkCancellation()
        guard crypto.resource.isActive else { throw CancellationError() }
        let scope = try await provider.validatedScope()
        guard scope.account.userID == account.accountID.rawValue,
              try ServerEnvironment(baseURL: scope.account.serverBaseURL).baseURL == account.environment.baseURL,
              crypto.resource.isActive else { throw CancellationError() }
        try Task.checkCancellation()
    }

    public func revoke() async {
        crypto.resource.revoke()
        await provider.revoke()
    }

    public func publishAutoFillUnlock() async {
        do {
            try await validateAuthorization()
            let scope = try await provider.validatedScope()
            let epoch = try await provider.validatedPublicationEpoch()
            let key = try await crypto.decryptedUserKey()
            try await validateAuthorization()
            guard let current = try store.loadSession(), current.scope == scope else { throw CancellationError() }
            try store.saveSharedAutofillUserKey(
                key,
                accountInfo: current.account.autoFillAccountInfo(),
                publicationEpoch: epoch,
                authenticationID: scope.authenticationID
            )
            AutoFillDiagnostics.record(.unlockPublication)
        } catch {
            AutoFillDiagnostics.record(.unlockPublication, error: error)
            // Existing best-effort policy: inability to publish does not undo a successful unlock.
        }
    }

    public func enableBiometricUnlock() async throws {
        try await validateAuthorization()
        let scope = try await provider.validatedScope()
        let epoch = try await provider.validatedPublicationEpoch()
        let key = try await crypto.decryptedUserKey()
        try await validateAuthorization()
        try store.enableBiometricUnlock(key: key, requiringScope: scope, publicationEpoch: epoch)
    }

    /// Data-owned single-use transfer. DefaultAuthFlowService exposes its result as a Domain
    /// capability; only app composition consumes the concrete assembly, never Auth presentation.
    public static func prepareHandoff(
        _ pending: any PendingAuthentication,
        onExpired: @escaping @Sendable (UUID) async -> Void
    ) async throws -> AuthenticatedSession {
        guard let candidate = pending as? PendingAuthSession else { throw CancellationError() }
        // A retained route capability cannot create two runtimes or replace the expiry handler
        // of an already prepared session. Failure is terminal; the caller starts a new attempt.
        try candidate.handoffLock.withLock {
            guard !candidate.handoffStarted else { throw AuthRepositoryError.invalidTransition }
            candidate.handoffStarted = true
        }
        var prepared: AuthenticatedSession?
        do {
            try await candidate.validateAuthorization()
            let scope = try await candidate.provider.validatedScope()
            let session = try AuthenticatedSession(
                account: candidate.account,
                resource: candidate.crypto.resource,
                tokenProvider: candidate.provider,
                scope: scope
            )
            prepared = session
            let runtime = session.runtime
            let sessionID = session.id
            await candidate.provider.setSessionExpiredHandler { [weak runtime] in
                Task {
                    guard let runtime else { return }
                    await runtime.revoke(.expired)
                    await onExpired(sessionID)
                }
            }
            try await candidate.validateAuthorization()
            return session
        } catch {
            if let prepared { await prepared.revoke(.lock) }
            else { await candidate.revoke() }
            throw error
        }
    }

    public var description: String { "PendingAuthSession(<redacted>)" }
    public var debugDescription: String { description }
}
