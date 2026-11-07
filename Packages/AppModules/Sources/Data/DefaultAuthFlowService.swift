import BitwardenSDKAdapter
import Domain
import Foundation
import Networking

/// App-injected credential flow assembly. Restore, stored-account mapping, command construction
/// and single-use session preparation stay out of presentation. This creates no credential store.
@MainActor
public final class DefaultAuthFlowService: AuthFlowCommands {
    public let passwordSignIn: any PasswordSignInCommands
    private let store: AuthCredentialStore
    private let repository: any AuthRepository
    private let tokens: any IdentityTokenService
    private let biometric: any BiometricClient
    private let deviceName: any DeviceNameClient
    private let applicationVersion: String
    private let unlockService: any VaultUnlockService

    public convenience init(
        httpClient: any HTTPClient,
        store: AuthCredentialStore,
        repository: any AuthRepository,
        biometric: any BiometricClient,
        deviceName: any DeviceNameClient,
        applicationVersion: String
    ) {
        self.init(
            store: store,
            repository: repository,
            prelogin: DefaultPreloginService(httpClient: httpClient),
            tokens: DefaultIdentityTokenService(httpClient: httpClient),
            biometric: biometric,
            deviceName: deviceName,
            applicationVersion: applicationVersion
        )
    }

    public init(
        store: AuthCredentialStore,
        repository: any AuthRepository,
        prelogin: any PreloginService,
        tokens: any IdentityTokenService,
        biometric: any BiometricClient,
        deviceName: any DeviceNameClient,
        applicationVersion: String,
        unlockService: any VaultUnlockService = SDKVaultUnlockService()
    ) {
        self.store = store; self.repository = repository; self.tokens = tokens
        self.biometric = biometric; self.deviceName = deviceName
        self.applicationVersion = applicationVersion; self.unlockService = unlockService
        passwordSignIn = PasswordSignInService(
            store: store,
            prelogin: prelogin,
            tokens: tokens,
            deviceName: deviceName,
            applicationVersion: applicationVersion,
            unlockService: unlockService
        )
    }

    public func restore() async throws -> AuthRestoreResult {
        try Task.checkCancellation()
        // Replay durable lock/logout before capturing the epoch that replay itself rotates.
        // Failure reaches the existing storage-recovery route, not setup or a returning unlock.
        try store.recoverPendingCleanup()
        // Capture the persistent fence before the repository hop. A lock/logout during that
        // suspension must not authorize a stale returning route, even for the same account.
        let epoch = try store.autofillPublicationEpoch()
        let state = try await repository.restore()
        try Task.checkCancellation()
        guard try store.autofillPublicationEpoch() == epoch else { throw CancellationError() }
        guard let account = try store.loadAccount() else { return .serverSetup }
        guard ServerURLPolicy.isPermitted(account.serverBaseURL) else { return .serverSetup }
        guard let saved = try store.loadSession() else {
            // Preserve split legacy records; they cannot prove token ownership for local unlock.
            return .passwordSignIn(try ServerEnvironment(baseURL: account.serverBaseURL), requiresStorageMigration: true)
        }
        let domainAccount = try AccountSession(storedAccount: saved.account)
        guard account == saved.account,
              state == .locked(domainAccount) || state == .unlocking(domainAccount) else {
            throw AuthRepositoryError.accountChanged
        }
        let snapshot = await repository.currentSnapshot()
        try Task.checkCancellation()
        guard snapshot.state == state, snapshot.sessionID == nil,
              try store.autofillPublicationEpoch() == epoch,
              try store.loadSession()?.scope == saved.scope,
              try store.loadAccount() == saved.account else { throw CancellationError() }
        // Merely displaying the unlock screen is not an unlock attempt. The command begins the
        // repository transition at submission, so cancelling restore leaves no unlocking state.
        let repository = repository
        return .returningUnlock(try ReturningUnlockService(
            account: saved.account,
            scope: saved.scope,
            store: store,
            tokens: tokens,
            deviceName: deviceName,
            biometric: biometric,
            applicationVersion: applicationVersion,
            beginUnlock: { try await repository.beginUnlock(account: $0) },
            unlockFailed: { await repository.unlockFailed(account: $0) },
            unlockService: unlockService
        ))
    }

    public func prepareHandoff(
        _ pending: any PendingAuthentication,
        onExpired: @escaping @MainActor @Sendable (UUID) -> Void
    ) async throws -> any AuthenticatedSessionCapability {
        let repository = repository
        return try await PendingAuthSession.prepareHandoff(pending) { sessionID in
            await repository.markExpiring(sessionID: sessionID)
            await onExpired(sessionID)
        }
    }
}
