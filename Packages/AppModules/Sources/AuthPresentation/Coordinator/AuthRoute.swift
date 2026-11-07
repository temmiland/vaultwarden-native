import Domain
import Foundation

/// Screens `AuthCoordinator` can navigate to.
enum AuthRoute {
    /// First run / logged-out: pick a Vaultwarden server.
    case serverSetup
    /// Email + master password against the chosen server.
    case login(environment: ServerEnvironment)
    /// A second factor is required to complete the in-progress login.
    case twoFactor(context: any AuthSecondFactorChallenge)
    /// A previous session exists locally - offer biometric or password re-entry instead of a full
    /// server-setup + login flow.
    case unlock(commands: any ReturningUnlockCommands)
    /// Shown once immediately after any successful unlock to offer enabling Touch ID.
    case enableBiometrics(context: any PendingAuthentication)
    /// Startup could not distinguish a missing local account from a Keychain/decode failure.
    /// Offers retry before the user explicitly chooses to continue with a fresh sign-in.
    case keychainUnavailable
}
