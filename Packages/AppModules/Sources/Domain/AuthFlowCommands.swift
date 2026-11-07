import Foundation

/// Restore returns presentation-safe routes, never stored tokens, keys or SDK resources.
public enum AuthRestoreResult: Sendable {
    case serverSetup
    case passwordSignIn(ServerEnvironment, requiresStorageMigration: Bool)
    case returningUnlock(any ReturningUnlockCommands)
}

/// Opaque runtime handed to the app owner. Presentation can validate or retire it, but cannot
/// obtain credentials or build repositories. Data and app composition own the concrete assembly.
public protocol AuthenticatedSessionCapability: Sendable {
    var id: UUID { get }
    var account: AccountSession { get }
    func checkAccess() throws
    func validateAuthorization() async throws
    func revoke(_ reason: SessionRevocationReason) async
}

@MainActor
public protocol AuthFlowCommands: Sendable {
    var passwordSignIn: any PasswordSignInCommands { get }
    func restore() async throws -> AuthRestoreResult
    func prepareHandoff(
        _ pending: any PendingAuthentication,
        onExpired: @escaping @MainActor @Sendable (UUID) -> Void
    ) async throws -> any AuthenticatedSessionCapability
}
