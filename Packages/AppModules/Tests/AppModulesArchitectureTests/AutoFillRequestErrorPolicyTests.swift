import AutoFillData
import BitwardenSDKAdapter
import Domain
import Foundation
import Testing

@Suite
struct AutoFillRequestErrorPolicyTests {
    @Test
    func unconfirmedRefreshNeedsMainAppSignInAndNeverOffersARegistrationRetry() {
        let failure = SessionAuthorizationError.refreshRecoveryRequired
        #expect(
            AutoFillRequestErrorPolicy.cancellation(for: failure, route: .registrationStartup) == .userInteractionRequired
        )
        #expect(!AutoFillRequestErrorPolicy.registrationCanRetry(failure))
        let message = AutoFillRequestErrorPolicy.registrationMessage(for: failure)
        #expect(message.contains("Sign out and sign in") && message.contains("no passkey write was submitted"))
    }

    @Test(
        arguments: [
            AutoFillFailureRoute.withoutInteraction,
            .identifiedCredential,
            .passkeyAssertion,
            .registrationStartup,
        ]
    )
    func typedErrorsKeepTheirMeaningAcrossRoutes(_ route: AutoFillFailureRoute) {
        #expect(
            AutoFillRequestErrorPolicy.cancellation(for: CancellationError(), route: route) == .userInteractionRequired
        )
        #expect(
            AutoFillRequestErrorPolicy.cancellation(for: PasskeyUserVerificationError.userCanceled, route: route) == .userCanceled
        )
        #expect(
            AutoFillRequestErrorPolicy.cancellation(for: AutoFillOperationError.keychainUnavailable, route: route) == .userInteractionRequired
        )
        #expect(
            AutoFillRequestErrorPolicy.cancellation(for: AutoFillOperationError.decryptFailed, route: route) == .credentialIdentityNotFound
        )
        #expect(
            AutoFillRequestErrorPolicy.cancellation(for: AutoFillCompletionError.unsupportedRequest, route: route) == .failed
        )
        #expect(
            AutoFillRequestErrorPolicy.cancellation(for: AutoFillCompletionError.malformedCredential, route: route) == .credentialIdentityNotFound
        )
    }

    @Test
    func untypedFailuresUseRouteSpecificFallbackWithoutExposingErrorText() {
        let error = NSError(
            domain: "fixture-secret",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "synthetic-secret-body"]
        )
        #expect(
            AutoFillRequestErrorPolicy.cancellation(for: error, route: .withoutInteraction) == .userInteractionRequired
        )
        #expect(
            AutoFillRequestErrorPolicy.cancellation(for: error, route: .registrationStartup) == .userInteractionRequired
        )
        #expect(
            AutoFillRequestErrorPolicy.cancellation(for: error, route: .identifiedCredential) == .credentialIdentityNotFound
        )
        #expect(AutoFillRequestErrorPolicy.cancellation(for: error, route: .passkeyAssertion) == .failed)
        for message in [
            AutoFillRequestErrorPolicy.registrationMessage(for: error),
            AutoFillRequestErrorPolicy.listMessage(for: error),
        ] {
            #expect(!message.contains("synthetic-secret-body") && !message.contains("fixture-secret"))
        }
    }

    @Test
    func onlyKnownUnsubmittedOrDefinitelyRejectedRegistrationErrorsAllowRetry() {
        let retry: [any Error] = [PasskeyRegistrationError.writeRejected,
                                  PasskeyRegistrationError.recoveryStorageUnavailable,
                                  PasskeyUserVerificationError.userCanceled, AutoFillOperationError.notAuthenticated,
                                  AutoFillOperationError.noAccountInfo, AutoFillOperationError.noSharedKey,
                                  AutoFillOperationError.keychainUnavailable,
                                  AutoFillOperationError.accessDenied, SDKAutoFillFidoError.accessDenied]
        let stop: [any Error] = [PasskeyRegistrationError.recoveryRequired, PasskeyRegistrationError.outcomeUnknown,
                                 PasskeyRegistrationError.committedNeedsRepair, AutoFillOperationError.saveFailed,
                                 AutoFillCompletionError.malformedCredential,
                                 AutoFillCompletionError.unsupportedRequest,
                                 SDKAutoFillFidoError.invalidRequest, CancellationError(),
                                 NSError(domain: "fixture", code: 1)]
        #expect(retry.allSatisfy { AutoFillRequestErrorPolicy.registrationCanRetry($0) })
        #expect(stop.allSatisfy { !AutoFillRequestErrorPolicy.registrationCanRetry($0) })
    }

    @Test
    func messagesDistinguishPreWriteStorageFailureFromPotentiallyCommittedWrite() {
        let before = AutoFillRequestErrorPolicy.registrationMessage(
            for: PasskeyRegistrationError.recoveryStorageUnavailable
        )
        let after = AutoFillRequestErrorPolicy.registrationMessage(for: PasskeyRegistrationError.committedNeedsRepair)
        #expect(before.contains("No new write was started") && !after.contains("No new write was started"))
        #expect(after.contains("prevent duplicates") && after.contains("sync"))
        #expect(
            AutoFillRequestErrorPolicy.listMessage(for: AutoFillOperationError.keychainUnavailable).contains(
                "couldn't be accessed"
            )
        )
        #expect(
            AutoFillRequestErrorPolicy.registrationMessage(for: AutoFillCompletionError.unsupportedRequest).contains(
                "Cancel"
            )
        )
    }
}
