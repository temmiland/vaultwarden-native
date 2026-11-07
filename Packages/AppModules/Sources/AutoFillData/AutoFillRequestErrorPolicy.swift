import BitwardenSDKAdapter
import Domain
import Foundation

public enum AutoFillFailureRoute: Sendable { case withoutInteraction, identifiedCredential, passkeyAssertion, registrationStartup }

/// Non-secret error vocabulary for the Apple adapter. No generic error description is rendered.
public enum AutoFillRequestErrorPolicy {
    public static func cancellation(for error: any Error, route: AutoFillFailureRoute) -> AutoFillCancellationReason {
        if error is CancellationError { return .userInteractionRequired } // revoked/stale invocation; old IDs are gated separately
        if error is SessionAuthorizationError { return .userInteractionRequired }
        if let verification = error as? PasskeyUserVerificationError, verification == .userCanceled { return .userCanceled }
        if let code = error as? TimeBasedOneTimeCodeError {
            return code == .expired ? .userInteractionRequired : .credentialIdentityNotFound
        }
        if let failure = error as? AutoFillCompletionError {
            return failure == .unsupportedRequest ? .failed : .credentialIdentityNotFound
        }
        if let failure = error as? AutoFillOperationError {
            switch failure {
            case .noSharedKey, .noAccountInfo, .keychainUnavailable, .noCache, .notAuthenticated: return .userInteractionRequired
            case .decryptFailed, .accessDenied: return .credentialIdentityNotFound
            case .saveFailed, .operationInProgress: break
            }
        }
        switch route {
        case .withoutInteraction, .registrationStartup: return .userInteractionRequired
        case .identifiedCredential: return .credentialIdentityNotFound
        case .passkeyAssertion: return .failed
        }
    }

    public static func registrationMessage(for error: any Error) -> String {
        if let authorization = error as? SessionAuthorizationError {
            return (authorization.errorDescription ?? "Session authorization failed.") + " Open the main app; no passkey write was submitted."
        }
        return switch error {
        case PasskeyRegistrationError.recoveryRequired, PasskeyRegistrationError.outcomeUnknown, PasskeyRegistrationError.committedNeedsRepair:
            "A passkey write may already be saved. Cancel this request and sync in Vaultwarden before registering again. An unresolved write stays blocked to prevent duplicates."
        case PasskeyRegistrationError.recoveryStorageUnavailable:
            "Passkey recovery data couldn't be stored safely. No new write was started. Open Vaultwarden and check its storage before trying again."
        case PasskeyRegistrationError.writeRejected:
            "The passkey write wasn't submitted or was rejected by the server. Check access in Vaultwarden before trying again."
        case PasskeyUserVerificationError.userCanceled:
            "Passkey verification was cancelled. No new write was started."
        case AutoFillOperationError.notAuthenticated:
            "Passkey saving needs access from the app. Open Vaultwarden, unlock and sync, then try again."
        case AutoFillOperationError.noAccountInfo, AutoFillOperationError.noSharedKey:
            "Open Vaultwarden and unlock it once so it can set up passkey saving, then try again."
        case AutoFillOperationError.keychainUnavailable:
            "Vaultwarden's saved account data couldn't be accessed. Open the app and try again."
        case AutoFillOperationError.accessDenied, SDKAutoFillFidoError.accessDenied:
            "This item can't be changed here. Use an official client for items requiring master-password verification."
        case SDKAutoFillFidoError.invalidRequest, AutoFillCompletionError.unsupportedRequest, AutoFillCompletionError.malformedCredential:
            "This passkey request couldn't be completed safely. Cancel it and start a new request after syncing in Vaultwarden."
        default:
            "Couldn't save the passkey. The write may have succeeded. Sync your vault in the app before trying again."
        }
    }

    /// Only known pre-write/definite-rejection failures allow a local retry. Ambiguous/untyped
    /// errors and output-validation failures must not leave the same Save action enabled.
    public static func registrationCanRetry(_ error: any Error) -> Bool {
        switch error {
        case PasskeyRegistrationError.writeRejected, PasskeyRegistrationError.recoveryStorageUnavailable,
             PasskeyUserVerificationError.userCanceled,
             AutoFillOperationError.notAuthenticated, AutoFillOperationError.noAccountInfo, AutoFillOperationError.noSharedKey,
             AutoFillOperationError.keychainUnavailable, AutoFillOperationError.accessDenied, SDKAutoFillFidoError.accessDenied: true
        default: false
        }
    }

    public static func listMessage(for error: any Error) -> String {
        if case AutoFillOperationError.keychainUnavailable = error { return "Saved vault data couldn't be accessed. Open Vaultwarden and try again." }
        return "Vault data is unavailable or changed. Open Vaultwarden, unlock and sync, then start a new AutoFill request."
    }
}
