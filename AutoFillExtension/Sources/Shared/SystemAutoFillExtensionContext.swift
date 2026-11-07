import AuthenticationServices
import AutoFillData
import Foundation

/// Sole Apple terminal adapter. Use callback APIs to start the OS call synchronously; optional
/// background completion handlers are not an acknowledgment that can authorize another request.
@MainActor
final class SystemAutoFillExtensionContext: AutoFillExtensionContext {
    private let context: ASCredentialProviderExtensionContext
    init(_ context: ASCredentialProviderExtensionContext) { self.context = context }
    func supports(_ kind: AutoFillCompletionKind) -> Bool {
        if kind == .passwordSaved {
            #if os(iOS)
                if #available(iOS 26.2, *) { return true }
            #endif
            return false
        }
        if kind == .oneTimeCode {
            if #available(macOS 15.0, iOS 18.0, *) { return true }
            return false
        }
        return true // password/passkeys supported by the app's macOS 14 / iOS 17 floor
    }

    func complete(_ credential: AutoFillCompletion) {
        switch credential {
        case .passwordSaved:
            #if os(iOS)
                guard #available(iOS 26.2, *) else { cancel(.failed); return }
                context.completeSavePasswordRequest(completionHandler: nil)
            #else
                cancel(.failed)
            #endif
        case let .password(value):
            context.completeRequest(
                withSelectedCredential: ASPasswordCredential(user: value.username, password: value.password),
                completionHandler: nil
            )
        case let .oneTimeCode(code):
            guard #available(macOS 15.0, iOS 18.0, *) else { cancel(.failed); return }
            context.completeOneTimeCodeRequest(using: ASOneTimeCodeCredential(code: code.code), completionHandler: nil)
        case let .passkeyAssertion(rp, hash, value):
            let assertion = ASPasskeyAssertionCredential(
                userHandle: value.userHandle,
                relyingParty: rp,
                signature: value.signature,
                clientDataHash: hash,
                authenticatorData: value.authenticatorData,
                credentialID: value.credentialID
            )
            context.completeAssertionRequest(using: assertion, completionHandler: nil)
        case let .passkeyRegistration(rp, hash, id, attestation):
            let registration = ASPasskeyRegistrationCredential(
                relyingParty: rp,
                clientDataHash: hash,
                credentialID: id,
                attestationObject: attestation
            )
            context.completeRegistrationRequest(using: registration, completionHandler: nil)
        }
    }

    func cancel(_ reason: AutoFillCancellationReason) {
        let code: ASExtensionError.Code
        switch reason {
        case .userCanceled: code = .userCanceled
        case .userInteractionRequired: code = .userInteractionRequired
        case .credentialIdentityNotFound: code = .credentialIdentityNotFound
        case .failed: code = .failed
        }
        context.cancelRequest(withError: ASExtensionError(code))
    }
}
