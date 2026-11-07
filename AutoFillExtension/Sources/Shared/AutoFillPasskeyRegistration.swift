import AuthenticationServices
import AutoFillContract
import AutoFillData
import BitwardenSDKAdapter
import Data
import Foundation
import Networking
import PlatformServices
import SecurityStorage

/// Apple request/result mapping and scoped composition only. SDK callbacks/encoding belong to
/// BitwardenSDKAdapter; whole-registration and server-writer sequencing belong to AutoFillData.
enum AutoFillPasskeyRegistration {
    enum Target: Sendable {
        case existing(SDKAutoFillCredentialView)
        case newItem(relyingPartyIdentifier: String, userName: String?)

        func cipherView() -> SDKAutoFillCredentialView {
            switch self {
            case let .existing(cipher): return cipher
            case let .newItem(rp, userName):
                return SDKAutoFillService.newPasskeyTarget(relyingPartyIdentifier: rp, userName: userName)
            }
        }
    }

    @MainActor
    static func register(
        request: ASPasskeyCredentialRequest,
        identity: ASPasskeyCredentialIdentity,
        target: Target,
        session: ExtensionVaultSession
    ) async throws -> AutoFillCompletion {
        _ = try session.readCache()
        let rp = identity.relyingPartyIdentifier, clientDataHash = request.clientDataHash
        let requestJSON = try SDKWebAuthnCreationRequest.make(
            relyingPartyIdentifier: rp,
            userName: identity.userName,
            userHandle: identity.userHandle,
            supportedAlgorithms: request.supportedAlgorithms.map { Int($0.rawValue) },
            userVerification: request.userVerificationPreference.rawValue
        )
        let response = try await session.registrations.register(checkAccess: { try session.checkAccess() }, operation: {
            let view = target.cipherView()
            guard view.allowsPasskeyRegistration else { throw AutoFillOperationError.accessDenied }
            if view.id != nil { try session.requireCurrentAccess(to: view, forEditing: true) }
            let persistence = try makePersistence(target: view, relyingPartyIdentifier: rp, session: session)
            let store = AutoFillFido2Bridge.store(views: [view], session: session, save: {
                let receipt = try await persistence.save($0)
                if receipt.needsProjectionRepair { AutoFillLog.logger.debug(
                    "passkey saved; durable projection recovery required"
                ) }
            })
            let ui = AutoFillFido2Bridge.userInterface(session: session, relyingPartyIdentifier: rp, target: view)
            return try await session.perform {
                try await $0.registration(
                    relyingPartyIdentifier: rp,
                    request: requestJSON,
                    clientDataHash: clientDataHash,
                    userInterface: ui,
                    credentialStore: store
                )
            }
        })
        AutoFillLog.logger.debug("registerPasskey: credential created and saved")
        return .passkeyRegistration(
            relyingPartyIdentifier: rp,
            clientDataHash: clientDataHash,
            credentialID: response.credentialID,
            attestationObject: response.attestationObject
        )
    }

    private static func makePersistence(
        target: SDKAutoFillCredentialView,
        relyingPartyIdentifier: String,
        session: ExtensionVaultSession
    ) throws -> PasskeyRegistrationPersistence {
        try session.checkAccess()
        let journal = try SharedAppGroup.makePasskeyRecoveryStore()
        guard try journal.records(requiring: session.proof).isEmpty else { throw PasskeyRegistrationError.recoveryRequired }
        guard session.accountInfo.serverBaseURL != nil else { throw AutoFillOperationError.noAccountInfo }
        let hasTokens: Bool
        do { hasTokens = try SharedAppGroup.makeTokenStore().load(requiringUnlockProof: session.proof) != nil }
        catch { throw AutoFillOperationError.keychainUnavailable }
        guard hasTokens else { throw AutoFillOperationError.notAuthenticated }
        let environment = try SDKAutoFillAccountMapper.environment(for: session.accountInfo)
        let http = ExtensionHTTPClient(base: Networking.URLSessionHTTPClient(), session: session)
        let tokens = SharedTokenProvider(
            identityURL: environment.identityURL,
            store: try SharedAppGroup.makeTokenStore(),
            httpClient: http,
            unlockProof: session.proof
        )
        let source = LivePasskeyRegistrationSource(
            session: session,
            service: SDKCipherService(
                httpClient: http,
                apiURL: environment.apiURL,
                userID: session.accountInfo.userId,
                accessToken: { await tokens.getAccessToken() },
                requireAccessToken: { try await tokens.requireAccessToken() }
            )
        )
        let projection = PasskeyRegistrationProjection(
            cache: try AutoFillVaultStore.cacheStore,
            proof: session.proof,
            cacheRevision: session.cacheRevision,
            identities: SystemCredentialIdentityStore(),
            identityMutations: SharedAppGroup.identityMutationCoordinator(containerURL: SharedAppGroup.containerURL),
            checkAccess: { try session.checkAccess() }
        )
        return PasskeyRegistrationPersistence(
            source: source,
            target: target,
            relyingPartyIdentifier: relyingPartyIdentifier,
            proof: session.proof,
            writer: session.registrationWrites,
            journal: journal,
            project: { dto, credentialID, rp in
                try await projection.project(dto, credentialID: credentialID, relyingPartyIdentifier: rp, makeIdentity: { persisted in
                    let identitySource = try await session.perform {
                        try await $0.registrationIdentitySource(
                            persisted,
                            credentialID: credentialID,
                            relyingPartyIdentifier: rp
                        )
                    }
                    let identities = CredentialIdentityMapper.makeIdentities(
                        from: [identitySource]
                    )
                    guard identities.count == 1, let identity = identities.first else { throw PasskeyRegistrationProjectionError.invalidIdentity }
                    return identity
                })
            }
        )
    }
}

/// Invocation-scoped transport composition. The original cache fences pre-submit HTTP; post-send
/// checks are proof-only because the confirmed write's own projection will advance that UUID.
struct ExtensionHTTPClient: HTTPClient {
    let base: any HTTPClient
    let session: ExtensionVaultSession
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        _ = try session.readCache()
        let response = try await base.send(request)
        try session.checkAccess()
        return response
    }

    func upload(_ request: HTTPRequest, fromFile fileURL: URL) async throws -> HTTPResponse {
        try session.checkAccess()
        let response = try await base.upload(request, fromFile: fileURL)
        try session.checkAccess()
        return response
    }

    func download(_ request: HTTPRequest, to destinationURL: URL) async throws -> HTTPFileResponse {
        try session.checkAccess()
        let response = try await base.download(request, to: destinationURL)
        try session.checkAccess()
        return response
    }
}
