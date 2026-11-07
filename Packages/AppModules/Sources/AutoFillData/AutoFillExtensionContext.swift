import Domain
import Foundation

public enum AutoFillCancellationReason: Sendable, Equatable {
    case userCanceled, userInteractionRequired, credentialIdentityNotFound, failed
}

public enum AutoFillCompletionKind: Sendable, Equatable {
    case password, oneTimeCode, passkeyAssertion, passkeyRegistration
}

public enum AutoFillCompletionError: Error, Sendable, Equatable {
    case unsupportedRequest, malformedCredential
}

/// Transient output only, never picker/model state. Diagnostic descriptions redact ALL cases.
/// An empty SDK-decoded passkey user handle is valid; no private passkey key is carried here.
public enum AutoFillCompletion: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    case password(AutoFillPassword)
    case oneTimeCode(TimeBasedOneTimeCode)
    case passkeyAssertion(
        relyingPartyIdentifier: String,
        clientDataHash: Foundation.Data,
        credential: PasskeyAssertionPayload
    )
    case passkeyRegistration(
        relyingPartyIdentifier: String,
        clientDataHash: Foundation.Data,
        credentialID: Foundation.Data,
        attestationObject: Foundation.Data
    )

    public var kind: AutoFillCompletionKind {
        switch self {
        case .password: .password
        case .oneTimeCode: .oneTimeCode
        case .passkeyAssertion: .passkeyAssertion
        case .passkeyRegistration: .passkeyRegistration
        }
    }

    public var description: String { "AutoFillCompletion(<redacted>)" }
    public var debugDescription: String { description }
    func validate(at date: Date) throws {
        let valid: Bool
        switch self {
        case let .password(value): valid = !value.password.isEmpty // intentionally empty username is allowed
        case let .oneTimeCode(code): try code.validate(at: date); valid = true
        case let .passkeyAssertion(rp, hash, value):
            valid = !rp.isEmpty && !hash.isEmpty && !value.credentialID.isEmpty && !value.signature.isEmpty && !value.authenticatorData.isEmpty
        case let .passkeyRegistration(rp, hash, id, attestation):
            valid = !rp.isEmpty && !hash.isEmpty && !id.isEmpty && !attestation.isEmpty
        }
        guard valid else { throw AutoFillCompletionError.malformedCredential }
    }
}

/// Synchronously START the platform's completion/cancellation on MainActor. This port must not
/// schedule another Task, await or keep credential output for later. OS acceptance/dismissal may
/// still happen later and is not atomic with the final shared-grant check.
@MainActor
public protocol AutoFillExtensionContext: AnyObject {
    func supports(_ kind: AutoFillCompletionKind) -> Bool
    func complete(_ credential: AutoFillCompletion)
    func cancel(_ reason: AutoFillCancellationReason)
}
