import AutoFillContract
import BitwardenSdk
import Domain
import Foundation

/// Typed AutoFill ports. The extension never receives SDK FIDO models or the unlocked Client;
/// all crypto and WebAuthn work shares its permanently revocable resource.
public struct SDKAutoFillService: Sendable {
    private let session: SDKSessionClient
    public init(session: SDKSessionClient) { self.session = session }

    public static func makeExtensionResource(account: SharedAccountInfo, applicationVersion: String) throws -> SDKSessionClient {
        let environment = try SDKAutoFillAccountMapper.environment(for: account)
        return SDKSessionClient(
            tokenProvider: SDKManagedTokenAdapter(accessToken: { nil }),
            settings: SDKClientFactory.makeSettings(
                identityURL: environment.identityURL,
                apiURL: environment.apiURL,
                deviceIdentifier: "autofill-extension",
                applicationVersion: applicationVersion
            )
        )
    }

    public func initializeUser(account: SharedAccountInfo, userKey: String) async throws {
        try await initializeUser(InitUserCryptoRequest(
            userId: account.userId,
            kdfParams: try SDKAutoFillAccountMapper.kdf(for: account),
            email: account.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            accountCryptographicState: .v1(privateKey: account.encryptedPrivateKey),
            method: .decryptedKey(decryptedUserKey: userKey),
            upgradeToken: nil
        ))
    }

    private func initializeUser(_ request: InitUserCryptoRequest) async throws {
        try await session.withClient { try await $0.crypto().initializeUserCrypto(req: request) }
    }

    public func initializeOrganizations(_ keys: [String: String]) async throws {
        try await SDKVaultCryptoService(sessionClient: session).initializeOrganizationCrypto(organizationKeys: keys)
    }

    private func decrypt(_ cipher: Cipher) async throws -> CipherView {
        try await SDKVaultCryptoService(sessionClient: session).decryptCipher(cipher)
    }

    public func decryptView(_ cipher: CipherResponseDTO) async throws -> SDKAutoFillCredentialView {
        SDKAutoFillCredentialView(
            legacyView: try await decrypt(cipher.toSDKCipher()),
            supportsLosslessEditing: !cipher.hasUnrecognizedPayload
        )
    }

    public func decryptView(_ cipher: SDKAutoFillEncryptedCipher) async throws -> SDKAutoFillCredentialView {
        SDKAutoFillCredentialView(legacyView: try await decrypt(cipher.value))
    }

    public static func newPasskeyTarget(relyingPartyIdentifier: String, userName: String?) -> SDKAutoFillCredentialView {
        SDKAutoFillCredentialView(
            legacyView: PasskeyItemFactory.makeLoginCipherView(
                relyingPartyIdentifier: relyingPartyIdentifier,
                userName: userName
            )
        )
    }

    public func encryptPasswordSave(
        title: String, username: String, password: String, uri: String,
        target: SDKAutoFillCredentialView?
    ) async throws -> SDKAutoFillEncryptedCipher {
        let view = try Self.passwordSaveView(
            title: title,
            username: username,
            password: password,
            uri: uri,
            target: target
        )
        let encrypted = try await SDKVaultCryptoService(sessionClient: session).encryptCipher(view)
        return SDKAutoFillEncryptedCipher(
            legacyCipher: encrypted.cipher,
            encryptedFor: encrypted.encryptedFor,
            lastKnownRevisionDate: target?.legacyView.revisionDate
        )
    }

    static func passwordSaveView(
        title: String,
        username: String,
        password: String,
        uri: String,
        target: SDKAutoFillCredentialView?
    ) throws -> CipherView {
        guard !title.isEmpty, !username.isEmpty, !password.isEmpty, !uri.isEmpty,
              title.utf8.count <= 4096, username.utf8.count <= 4096,
              password.utf8.count <= 1_048_576, uri.utf8.count <= 2048,
              target == nil || target?.allowsPasswordSaving == true else {
            throw SDKAutoFillFidoError.accessDenied
        }
        var draft: VaultItemDraft
        if let target {
            draft = try SDKVaultItemDraftMapper.makeDraft(from: target.legacyView)
        } else {
            draft = VaultItemDraft(kind: .login)
            draft.name = title
            draft.uris = [uri]
        }
        draft.username = username
        draft.password = password
        return try SDKVaultItemDraftMapper.applying(draft, to: target?.legacyView)
    }

    public func assertion(
        relyingPartyIdentifier: String,
        request: String,
        clientDataHash: Foundation.Data,
        userInterface: SDKAutoFillFidoUserInterface,
        credentialStore: SDKAutoFillFidoCredentialStore
    ) async throws -> SDKAutoFillAssertionResult {
        let response = try await userInterface.withVerificationFailureMapping {
            try await authenticate(
                origin: .web("https://\(relyingPartyIdentifier)"),
                request: request,
                clientData: .defaultWithCustomHash(hash: clientDataHash),
                userInterface: userInterface,
                credentialStore: credentialStore
            )
        }
        return SDKAutoFillAssertionResult(
            credentialID: response.rawId,
            userHandle: response.response.userHandle,
            signature: response.response.signature,
            authenticatorData: response.response.authenticatorData
        )
    }

    public func registration(
        relyingPartyIdentifier: String,
        request: String,
        clientDataHash: Foundation.Data,
        userInterface: SDKAutoFillFidoUserInterface,
        credentialStore: SDKAutoFillFidoCredentialStore
    ) async throws -> SDKAutoFillRegistrationResult {
        let response = try await userInterface.withVerificationFailureMapping {
            try await register(
                origin: .web("https://\(relyingPartyIdentifier)"),
                request: request,
                clientData: .defaultWithCustomHash(hash: clientDataHash),
                userInterface: userInterface,
                credentialStore: credentialStore
            )
        }
        return SDKAutoFillRegistrationResult(
            credentialID: response.rawId,
            attestationObject: response.response.attestationObject
        )
    }

    public func passkeyMetadata(in view: SDKAutoFillCredentialView) throws -> [SDKAutoFillPasskeyMetadata] {
        try passkeys(in: view.legacyView).map { SDKAutoFillPasskeyMetadata(legacyView: $0) }
    }

    public func registrationIdentitySource(
        _ cipher: CipherResponseDTO,
        credentialID: Foundation.Data,
        relyingPartyIdentifier: String
    ) async throws -> VaultLoginIdentitySource {
        let view = try await decryptView(cipher)
        return try SDKAutoFillRegistrationIdentityMapper.source(
            cipher: cipher,
            view: view,
            passkeys: passkeyMetadata(in: view),
            credentialID: credentialID,
            relyingPartyIdentifier: relyingPartyIdentifier
        )
    }

    public func oneTimeCode(seed: String, at date: Date) throws -> TimeBasedOneTimeCode {
        let response = try session.withClient { try $0.vault().generateTotp(key: seed, time: date) }
        return TimeBasedOneTimeCode(code: response.code, period: response.period, generatedAt: date)
    }

    private func passkeys(in cipher: CipherView) throws -> [Fido2CredentialAutofillView] {
        try session.withClient { try $0.platform().fido2().getFido2AutofillCredentials(cipherView: cipher) }
    }

    private func authenticate(
        origin: Origin,
        request: String,
        clientData: ClientData,
        userInterface: any Fido2UserInterface,
        credentialStore: any Fido2CredentialStore
    ) async throws -> PublicKeyCredentialAuthenticatorAssertionResponse {
        try await session.withClient {
            try await $0.platform().fido2().client(userInterface: userInterface, credentialStore: credentialStore)
                .authenticate(origin: origin, request: request, clientData: clientData)
        }
    }

    private func register(
        origin: Origin,
        request: String,
        clientData: ClientData,
        userInterface: any Fido2UserInterface,
        credentialStore: any Fido2CredentialStore
    ) async throws -> PublicKeyCredentialAuthenticatorAttestationResponse {
        try await session.withClient {
            try await $0.platform().fido2().client(userInterface: userInterface, credentialStore: credentialStore)
                .register(origin: origin, request: request, clientData: clientData)
        }
    }
}
