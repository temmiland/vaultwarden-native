import Foundation

/// Nonsecret returning-account presentation; no wrapped keys, tokens or storage scope.
public struct ReturningUnlockAccount: Sendable, Equatable {
    public let session: AccountSession
    public var isBiometricUnlockEnabled: Bool
    public var isPinUnlockEnabled: Bool
    public var email: String { session.email }
    public init(session: AccountSession, isBiometricUnlockEnabled: Bool, isPinUnlockEnabled: Bool) {
        self.session = session
        self.isBiometricUnlockEnabled = isBiometricUnlockEnabled
        self.isPinUnlockEnabled = isPinUnlockEnabled
    }
}

public enum ReturningUnlockMethod: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    case password(String), pin(String), biometric
    public var description: String { "ReturningUnlockMethod(<redacted>)" }
    public var debugDescription: String { description }
}

public struct ReturningUnlockAvailability: Sendable {
    public let isPinAvailable: Bool
    public let isBiometricAvailable: Bool
    public let biometryKind: BiometryKind
    public let failure: ReturningUnlockFailure?
    public init(
        isPinAvailable: Bool,
        isBiometricAvailable: Bool,
        biometryKind: BiometryKind,
        failure: ReturningUnlockFailure? = nil
    ) {
        self.isPinAvailable = isPinAvailable; self.isBiometricAvailable = isBiometricAvailable
        self.biometryKind = biometryKind; self.failure = failure
    }
}

public enum ReturningUnlockResult: Sendable {
    case unlocked(any PendingAuthentication, offerBiometricEnrollment: Bool)
    case rejected(ReturningUnlockFailure)
    case cancelled
}

/// The route owns this capability until success/retirement. Successful pending sessions transfer
/// ownership: revoking the old command capability must not revoke its successor.
@MainActor
public protocol ReturningUnlockCommands: AuthAttemptCapability {
    var account: ReturningUnlockAccount { get }
    func availability() -> ReturningUnlockAvailability
    func unlock(using method: ReturningUnlockMethod) async -> ReturningUnlockResult
}

/// Stable UI errors, never SDK/storage diagnostics. Associated values are nonsecret policy facts.
public enum ReturningUnlockFailure: Error, LocalizedError, Sendable, Equatable {
    case invalidEncryptionParameters, accountChanged, anotherPinAttempt, emptyPassword, emptyPIN
    case pinUnavailable, pinNotSetup, pinReadFailed, pinStateFailed, incorrectPassword
    case biometricReadFailed, biometricCryptoFailed, biometricCleanupFailed
    case biometricUnavailable(cleanupFailed: Bool)
    case biometricNotConfirmed(BiometryKind)
    case biometricNotSetup(BiometryKind, cleanupFailed: Bool)
    case storageUnavailable(password: Bool), savedSessionChanged
    case incorrectPIN(remaining: Int)
    case pinLimit(cleanupConfirmed: Bool, atAppearance: Bool)
    case pinCounterFailed(cleanupConfirmed: Bool), pinResetFailed(cleanupConfirmed: Bool)

    public var errorDescription: String? {
        switch self {
        case .invalidEncryptionParameters: AuthFlowError.invalidEncryptionParameters.localizedDescription
        case .accountChanged: "The saved account changed. Return to sign-in and try again."
        case .anotherPinAttempt: "Another PIN unlock is already in progress. Try again."
        case .emptyPassword: "Enter your master password."
        case .emptyPIN: "Enter your PIN."
        case .pinUnavailable: "PIN unlock isn't available. Use your master password or try again."
        case .pinNotSetup: "PIN unlock isn't set up on this device. Use your master password."
        case .pinReadFailed: "Couldn't access PIN unlock data. Use your master password or try again."
        case .pinStateFailed: "Couldn't safely check PIN unlock data. Use your master password or try again."
        case .incorrectPassword: "Incorrect master password."
        case .biometricReadFailed: "Couldn't access biometric unlock data. Try again or use your master password."
        case .biometricCryptoFailed: "Couldn't unlock with biometric data. Use your master password or try again."
        case .biometricCleanupFailed: "Couldn't fully disable biometric unlock (saved biometric setting cleanup failed)."
        case let .biometricUnavailable(failed):
            "Biometric unlock isn't currently available. Use your master password." + (
                failed ? " \(Self.biometricCleanupFailed.localizedDescription)" : ""
            )
        case let .biometricNotConfirmed(kind): "\(kind.displayName) wasn't confirmed."
        case let .biometricNotSetup(kind, failed):
            "\(kind.displayName) unlock isn't set up on this device. Use your master password." + (
                failed ? " \(Self.biometricCleanupFailed.localizedDescription)" : ""
            )
        case let .storageUnavailable(password): password
            ? "Couldn't access this device's saved authentication data. Try again."
            : "Couldn't access this device's saved authentication data. Use your master password or try again."
        case .savedSessionChanged: "The saved session changed while unlocking. Sign in again."
        case let .incorrectPIN(remaining): remaining == 1
            ? "Incorrect PIN. 1 attempt left before PIN unlock is turned off."
            : "Incorrect PIN. \(remaining) attempts left."
        case let .pinLimit(confirmed, appearance):
            "Too many incorrect PINs. PIN unlock has been turned off — use your master password." + (
                confirmed ? "" : appearance
                    ? " The saved attempt limit still blocks PIN unlock, but PIN-key cleanup could not be confirmed."
                    : " The attempt limit still blocks PIN unlock, but PIN-key cleanup could not be confirmed."
            )
        case let .pinCounterFailed(confirmed):
            "Couldn't securely record the PIN attempt. PIN unlock is disabled for this session — use your master password." + (
                confirmed ? ""
                    : " The stored PIN key and account flag could not be persistently disabled; do not retry PIN unlock."
            )
        case let .pinResetFailed(confirmed):
            "PIN was accepted, but its attempt limit couldn't be reset. PIN unlock is disabled — use your master password." + (
                confirmed ? ""
                    : " Saved PIN data could not be safely disabled; do not retry PIN unlock."
            )
        }
    }
}
