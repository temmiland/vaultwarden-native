import BitwardenSdk
import BitwardenSDKAdapter
import Foundation
import Testing

/// Regression coverage for two bugs found during manual testing: (1) `login.fido2Credentials` was
/// never parsed out of the sync response, so passkeys silently vanished from every login item;
/// (2) worse, saving *any* edit to a login item with a passkey dropped it permanently, because
/// `ItemDraft` always rebuilt the login with `fido2Credentials: nil`.
@Suite
struct CipherFido2Tests {
    private let fido2JSON = """
    {
        "id": "cipher-1",
        "type": 1,
        "name": "Encrypted Name",
        "favorite": false,
        "reprompt": 0,
        "revisionDate": "2024-01-01T00:00:00.000Z",
        "creationDate": "2024-01-01T00:00:00.000Z",
        "login": {
            "username": "enc-username",
            "fido2Credentials": [
                {
                    "credentialId": "enc-credential-id",
                    "keyType": "enc-key-type",
                    "keyAlgorithm": "enc-key-algorithm",
                    "keyCurve": "enc-key-curve",
                    "keyValue": "enc-key-value",
                    "rpId": "enc-rp-id",
                    "rpName": "enc-rp-name",
                    "userHandle": "enc-user-handle",
                    "userName": "enc-user-name",
                    "userDisplayName": "enc-user-display-name",
                    "counter": "enc-counter",
                    "discoverable": "enc-discoverable",
                    "creationDate": "2024-01-01T00:00:00.000Z"
                }
            ]
        }
    }
    """

    // MARK: - Sync parsing (bug 1)

    @Test
    func syncResponseParsesFido2CredentialsIntoTheSDKLogin() throws {
        let dto = try JSONDecoder().decode(CipherResponseDTO.self, from: Data(fido2JSON.utf8))
        let cipher = try dto.toSDKCipher()

        let credentials = try #require(cipher.login?.fido2Credentials)
        #expect(credentials.count == 1)
        #expect(credentials[0].credentialId == "enc-credential-id")
        #expect(credentials[0].rpId == "enc-rp-id")
        #expect(credentials[0].userName == "enc-user-name")
    }

    @Test
    func aCredentialMissingARequiredFieldCannotBeSilentlyErasedByEditing() throws {
        let json = """
        {
            "id": "cipher-1", "type": 1, "name": "Name", "favorite": false, "reprompt": 0,
            "revisionDate": "2024-01-01T00:00:00.000Z", "creationDate": "2024-01-01T00:00:00.000Z",
            "login": { "fido2Credentials": [ { "creationDate": "2024-01-01T00:00:00.000Z" } ] }
        }
        """
        let dto = try JSONDecoder().decode(CipherResponseDTO.self, from: Data(json.utf8))
        #expect(throws: CipherMappingError.invalidField("login.fido2Credentials")) {
            _ = try dto.toSDKCipher()
        }
    }

    // MARK: - Save round trip (bug 2)

    @Test
    func savingAnEditedLoginPreservesItsExistingPasskeyInTheOutgoingRequest() async throws {
        let email = "synthetic@example.invalid", password = "synthetic-test-password"
        let kdf = Kdf.pbkdf2(iterations: 600_000)
        let client = SDKClientFactory.makeClient(
            tokenProvider: SDKManagedTokenAdapter(accessToken: { nil }),
            settings: SDKClientFactory.makeSettings(
                identityURL: URL(string: "https://example.invalid/identity")!,
                apiURL: URL(string: "https://example.invalid/api")!,
                deviceIdentifier: "synthetic-passkey-roundtrip", applicationVersion: "test"
            )
        )
        let keys = try client.auth().makeRegisterKeys(email: email, password: password, kdf: kdf)
        try await client.crypto().initializeUserCrypto(req: InitUserCryptoRequest(
            userId: "00000000-0000-4000-8000-000000000001", kdfParams: kdf, email: email,
            accountCryptographicState: .v1(privateKey: keys.keys.private),
            method: .masterPasswordUnlock(password: password, masterPasswordUnlock: MasterPasswordUnlockData(
                kdf: kdf, masterKeyWrappedUserKey: keys.encryptedUserKey, salt: email
            )), upgradeToken: nil
        ))
        let crypto = SDKVaultCryptoService(client: client)
        let credential = Fido2CredentialView.fixture(
            credentialId: "00000000-0000-4000-8000-000000000002",
            rpId: "example.com"
        )
        let login = LoginView(
            username: "user",
            password: "pass",
            passwordRevisionDate: nil,
            uris: nil,
            totp: nil,
            autofillOnPageLoad: nil,
            fido2Credentials: [credential]
        )
        let original = CipherView.fixture(id: "00000000-0000-4000-8000-000000000003", login: login)
        let encrypted = try await crypto.encryptCipher(original)
        let decoded = try await crypto.decryptCipher(encrypted.cipher)
        var draft = try SDKVaultItemDraftMapper.makeDraft(from: decoded)
        draft.name = "Renamed"
        let rebuilt = try SDKVaultItemDraftMapper.applying(draft, to: decoded)
        let updated = try await crypto.encryptCipher(rebuilt)
        let request = try CipherRequestDTO(cipher: updated.cipher, encryptedFor: updated.encryptedFor)
        #expect(request.login?.fido2Credentials?.count == 1)
        #expect(request.login?.fido2Credentials?.first?.keyValue != credential.keyValue)
        let roundTrip = try await crypto.decryptCipher(updated.cipher)
        #expect(roundTrip.name == "Renamed")
        #expect(roundTrip.login?.fido2Credentials == [credential])
    }

    @Test
    func adapterPreservesFido2CredentialsOutsideTheDomainDraft() throws {
        let loginView = LoginView(
            username: "user", password: nil, passwordRevisionDate: nil, uris: nil, totp: nil,
            autofillOnPageLoad: nil,
            fido2Credentials: [.fixture(credentialId: "cred-1", rpId: "example.com")]
        )
        let cipher = CipherView.fixture(id: "cipher-1", login: loginView)

        let draft = try SDKVaultItemDraftMapper.makeDraft(from: cipher)
        let rebuilt = try SDKVaultItemDraftMapper.applying(draft, to: cipher)

        #expect(rebuilt.login?.fido2Credentials?.first?.credentialId == "cred-1")
    }

    @Test
    func editingOneLoginFieldPreservesURISettingsAndHiddenLoginMetadata() throws {
        let originalRevision = Date(timeIntervalSince1970: 1_700_000_000)
        let originalLogin = LoginView(
            username: "before", password: "secret", passwordRevisionDate: originalRevision,
            uris: [LoginUriView(uri: "https://example.com/login", match: .exact, uriChecksum: "checksum")],
            totp: "totp-seed", autofillOnPageLoad: true, httpAuthenticationEnabled: true,
            fido2Credentials: [.fixture(credentialId: "cred-1", rpId: "example.com")]
        )
        let existing = CipherView.fixture(id: "cipher-1", login: originalLogin)

        var draft = try SDKVaultItemDraftMapper.makeDraft(from: existing)
        draft.username = "after"
        let rebuilt = try SDKVaultItemDraftMapper.applying(draft, to: existing)

        #expect(rebuilt.login?.username == "after")
        #expect(rebuilt.login?.password == "secret")
        #expect(rebuilt.login?.passwordRevisionDate == originalRevision)
        #expect(rebuilt.login?.uris?.first?.match == .exact)
        #expect(rebuilt.login?.uris?.first?.uriChecksum == "checksum")
        #expect(rebuilt.login?.autofillOnPageLoad == true)
        #expect(rebuilt.login?.httpAuthenticationEnabled == true)
        #expect(rebuilt.login?.fido2Credentials?.first?.credentialId == "cred-1")
    }

    @Test
    func emptyServerURIRowsDoNotShiftOrLoseTheFollowingURIMetadata() throws {
        let original = LoginView(
            username: "user", password: "secret", passwordRevisionDate: nil,
            uris: [
                LoginUriView(uri: nil, match: .never, uriChecksum: "nil-row-checksum"),
                LoginUriView(uri: "https://example.com", match: .exact, uriChecksum: "actual-uri-checksum"),
            ],
            totp: nil, autofillOnPageLoad: nil, fido2Credentials: nil
        )
        let existing = CipherView.fixture(login: original)
        var draft = try SDKVaultItemDraftMapper.makeDraft(from: existing)
        draft.name = "Renamed"
        let rebuilt = try SDKVaultItemDraftMapper.applying(draft, to: existing)

        #expect(rebuilt.login?.uris == original.uris)
        #expect(draft.uris == ["", "https://example.com"])
    }
}

private extension Fido2CredentialView {
    static func fixture(credentialId: String, rpId: String) -> Fido2CredentialView {
        Fido2CredentialView(
            credentialId: credentialId, keyType: "public-key", keyAlgorithm: "ECDSA", keyCurve: "P-256",
            keyValue: "enc-key", rpId: rpId, userHandle: nil, userName: nil, counter: "0",
            rpName: nil, userDisplayName: nil, discoverable: "true",
            creationDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
