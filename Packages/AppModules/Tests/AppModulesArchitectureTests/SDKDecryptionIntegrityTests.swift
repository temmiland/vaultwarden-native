import BitwardenSdk
import BitwardenSDKAdapter
import Foundation
import Testing

@Suite
struct SDKDecryptionIntegrityTests {
    @Test
    func completeProjectionAndLegitimateEmptyOptionalValuesAreAccepted() throws {
        try SDKDecryptionIntegrity.validate(.fixture(), decrypted: .fixture())
        let login = LoginView(
            username: "",
            password: "",
            passwordRevisionDate: nil,
            uris: nil,
            totp: nil,
            autofillOnPageLoad: nil,
            fido2Credentials: nil
        )
        try SDKDecryptionIntegrity.validate(.fixture(), decrypted: .fixture(login: login))
    }

    @Test(arguments: ["username", "password", "totp"])
    func silentlyDroppedLoginFieldsAreRejected(_ missing: String) {
        let encrypted = Login(
            username: "fake-wrapped-user",
            password: "fake-wrapped-password",
            passwordRevisionDate: nil,
            uris: nil,
            totp: "fake-wrapped-totp",
            autofillOnPageLoad: nil,
            fido2Credentials: nil
        )
        let decoded = LoginView(
            username: missing == "username" ? nil : "user",
            password: missing == "password" ? nil : "pass",
            passwordRevisionDate: nil,
            uris: nil,
            totp: missing == "totp" ? nil : "seed",
            autofillOnPageLoad: nil,
            fido2Credentials: nil
        )
        #expect(throws: SDKDecryptionIntegrityError.incompleteCipher) {
            try SDKDecryptionIntegrity.validate(.fixture(login: encrypted), decrypted: .fixture(login: decoded))
        }
    }

    @Test
    func emptyMandatoryNameAndLostPayloadCannotBecomeAnEditableBlankItem() {
        for view in [CipherView.fixture(name: ""), .fixture(login: nil), .fixture(id: "another-item"),
                     .fixture(organizationId: "another-owner")] {
            #expect(throws: SDKDecryptionIntegrityError.incompleteCipher) {
                try SDKDecryptionIntegrity.validate(.fixture(), decrypted: view)
            }
        }
    }

    @Test
    func uriRemovalCannotSilentlyChangeAnEditableOrAutoFillProjection() {
        let encrypted = Login(
            username: "fake-user",
            password: "fake-password",
            passwordRevisionDate: nil,
            uris: [LoginUri(uri: "fake-uri", match: .exact, uriChecksum: "fake-checksum")],
            totp: nil,
            autofillOnPageLoad: nil,
            fido2Credentials: nil
        )
        #expect(throws: SDKDecryptionIntegrityError.incompleteCipher) {
            try SDKDecryptionIntegrity.validate(.fixture(login: encrypted), decrypted: .fixture())
        }
    }

    @Test(arguments: [#""notes":"fake-wrapped-notes""#,
                      #""fields":[{"name":"fake-wrapped-field","value":"fake-wrapped-value","type":0}]"#,
                      #""passwordHistory":[{"password":"fake-wrapped-history","lastUsedDate":"1970-01-01T00:00:00.000Z"}]"#,
                      #""card":{"number":"fake-wrapped-number"}"#,
                      #""identity":{"email":"fake-wrapped-email"}"#])
    func lostHiddenFieldsAndPayloadsAreRejected(_ payload: String) throws {
        let data = Data(
            "{\"id\":\"cipher-1\",\"name\":\"fake-wrapped-name\",\"type\":1,\"favorite\":false,\"reprompt\":0,\"revisionDate\":\"1970-01-01T00:00:00.000Z\",\"creationDate\":\"1970-01-01T00:00:00.000Z\",\(payload)}".utf8
        )
        let cipher = try JSONDecoder().decode(CipherResponseDTO.self, from: data).toSDKCipher()
        #expect(throws: SDKDecryptionIntegrityError.incompleteCipher) {
            try SDKDecryptionIntegrity.validate(cipher, decrypted: .fixture())
        }
    }

    @Test
    func reportedAttachmentFailureRetainsTheExistingSeparateReadOnlyPolicy() throws {
        let view = CipherView.fixture(attachmentDecryptionFailures: ["attachment-1"])
        try SDKDecryptionIntegrity.validate(.fixture(), decrypted: view)
        #expect(SDKVaultPresentationMapper.permissions(for: view, collections: []).canEdit == false)
    }
}
