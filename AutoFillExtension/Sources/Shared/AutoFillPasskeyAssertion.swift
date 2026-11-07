import AutoFillContract
import AutoFillData
import BitwardenSDKAdapter
import Foundation

/// Callback composition only. Selection/RP/cache authorization is Data-owned; Apple output
/// mapping belongs to the synchronous terminal-context adapter.
enum AutoFillPasskeyAssertion {
    static func make(
        for match: AutoFillLoginSummary,
        clientDataHash: Data,
        relyingPartyIdentifier: String,
        allowedCredentials: [Data],
        userVerification: String,
        session: ExtensionVaultSession
    ) async throws -> AutoFillCompletion {
        let result = try await session.passkeys.assertion(
            for: match,
            relyingPartyIdentifier: relyingPartyIdentifier,
            allowedCredentials: allowedCredentials,
            userVerification: userVerification
        ) { view, request in
            let store = AutoFillFido2Bridge.store(views: [view], session: session)
            let ui = AutoFillFido2Bridge.userInterface(
                session: session,
                relyingPartyIdentifier: relyingPartyIdentifier,
                selected: view
            )
            let response = try await session.perform {
                try await $0.assertion(
                    relyingPartyIdentifier: relyingPartyIdentifier,
                    request: request,
                    clientDataHash: clientDataHash,
                    userInterface: ui,
                    credentialStore: store
                )
            }
            return PasskeyAssertionPayload(
                userHandle: response.userHandle,
                signature: response.signature,
                authenticatorData: response.authenticatorData,
                credentialID: response.credentialID
            )
        }
        return .passkeyAssertion(
            relyingPartyIdentifier: relyingPartyIdentifier,
            clientDataHash: clientDataHash,
            credential: result
        )
    }
}
