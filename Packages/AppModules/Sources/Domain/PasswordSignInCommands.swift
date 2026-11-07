import Foundation

/// An explicit lifetime, not a Client/token/password container. Revocation is permanent;
/// transferring a challenge to a pending session keeps the same attempt ID.
public protocol AuthAttemptCapability: AnyObject, Sendable {
    var id: UUID { get }
    func revoke() async
}

public protocol PendingAuthentication: AuthAttemptCapability {
    var account: AccountSession { get }
    func validateAuthorization() async throws
    func publishAutoFillUnlock() async
    func enableBiometricUnlock() async throws
}

public protocol AuthSecondFactorChallenge: AuthAttemptCapability {
    var environment: ServerEnvironment { get }
    var availableProviders: [Int] { get }
    func submitTOTP(code: String, remember: Bool) async throws -> PasswordSignInResult
}

public enum PasswordSignInResult: Sendable {
    case unlocked(any PendingAuthentication)
    case twoFactorRequired(any AuthSecondFactorChallenge)
    case rejected(PasswordSignInRejection)
}

public enum PasswordSignInRejection: Error, LocalizedError, Sendable, Equatable {
    case invalidCredentials, busy, unavailable, invalidResponse, failed, invalidTwoFactor
    public var errorDescription: String? {
        switch self {
        case .invalidCredentials: "Username or password is incorrect."
        case .busy: "The server is busy. Please try again shortly."
        case .unavailable: "The server is temporarily unavailable. Please try again."
        case .invalidResponse: "The server returned an unrecognized response."
        case .failed: "Login failed. Please check your details and try again."
        case .invalidTwoFactor: "That code wasn't accepted. Try again."
        }
    }
}

public protocol PasswordSignInCommands: Sendable {
    func signIn(email: String, password: String, environment: ServerEnvironment) async throws -> PasswordSignInResult
}
