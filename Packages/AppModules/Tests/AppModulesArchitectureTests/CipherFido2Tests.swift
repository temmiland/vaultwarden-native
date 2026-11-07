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
    func savingAnEditedLoginPreservesItsExistingPasskeyInTheOutgoingRequest() throws {
        let dto = try JSONDecoder().decode(CipherResponseDTO.self, from: Data(fido2JSON.utf8))
        let cipher = try dto.toSDKCipher()

        // Simulate what VaultModel.saveDraft does: build a draft from the decrypted view,
        // then turn it back into a CipherView to encrypt and push. We don't have a real FFI Client
        // in this test target, so exercise the same Login round trip directly instead of going
        // through decrypt/encrypt.
        let loginView = LoginView(
            username: "user", password: "pass", passwordRevisionDate: nil, uris: nil, totp: nil,
            autofillOnPageLoad: nil, fido2Credentials: cipher.login?.fido2Credentials
        )
        let existing = CipherView.fixture(id: "cipher-1", login: loginView)

        var draft = try SDKVaultItemDraftMapper.makeDraft(from: existing)
        draft.name = "Renamed" // an unrelated edit - must not touch the passkey
        let rebuilt = try SDKVaultItemDraftMapper.applying(draft, to: existing)

        // `encryptCipher(_:)` (real SDK call, not available in this test target) is what would
        // normally turn `rebuilt.login: LoginView` back into `Login` for the request - since
        // `Fido2Credential`/`EncString` fields are just Strings, wrap it directly to check the DTO
        // mapping without needing a real FFI-backed `Client`.
        let reEncryptedLogin = Login(
            username: rebuilt.login?.username, password: rebuilt.login?.password,
            passwordRevisionDate: nil, uris: nil, totp: nil, autofillOnPageLoad: nil,
            fido2Credentials: rebuilt.login?.fido2Credentials
        )
        let requestDTO = try CipherRequestDTO(cipher: cipher.withLogin(reEncryptedLogin), encryptedFor: "user-1")
        let preservedCredentials = try #require(requestDTO.login?.fido2Credentials)
        #expect(preservedCredentials.count == 1)
        #expect(preservedCredentials[0].credentialId == "enc-credential-id")
        #expect(preservedCredentials[0].rpId == "enc-rp-id")
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
            totp: "totp-seed", autofillOnPageLoad: true,
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

private extension Fido2Credential {
    static func fixture(credentialId: String, rpId: String) -> Fido2Credential {
        Fido2Credential(
            credentialId: credentialId, keyType: "public-key", keyAlgorithm: "ECDSA", keyCurve: "P-256",
            keyValue: "enc-key", rpId: rpId, userHandle: nil, userName: nil, counter: "0",
            rpName: nil, userDisplayName: nil, discoverable: "true", creationDate: Date()
        )
    }
}

private extension Cipher {
    /// Test-only helper: `Cipher` has no `with`-style mutator, and pulling in the full 20-argument
    /// initializer at every call site would obscure what's actually being tested.
    func withLogin(_ login: Login?) -> Cipher {
        Cipher(
            id: id, organizationId: organizationId, folderId: folderId, collectionIds: collectionIds,
            key: key, name: name, notes: notes, type: type, login: login, identity: identity, card: card,
            secureNote: secureNote, sshKey: sshKey, bankAccount: bankAccount, driversLicense: driversLicense,
            passport: passport, favorite: favorite, reprompt: reprompt, organizationUseTotp: organizationUseTotp,
            edit: edit, permissions: permissions, viewPassword: viewPassword, localData: localData,
            attachments: attachments, fields: fields, passwordHistory: passwordHistory, creationDate: creationDate,
            deletedDate: deletedDate, revisionDate: revisionDate, archivedDate: archivedDate, data: data
        )
    }
}
