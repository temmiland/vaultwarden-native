import BitwardenSdk
import BitwardenSDKAdapter
import Data
import Domain
import Foundation
import Networking
import Testing

@Suite
struct SDKVaultIdentityExportTests {
    @Test
    func protectedLoginPublishesNoPasswordTotpOrPasskeyIdentity() async throws {
        let login = LoginView(
            username: "user", password: "fake-test-password", passwordRevisionDate: nil,
            uris: [LoginUriView(uri: "https://example.com", match: .exact, uriChecksum: nil)],
            totp: "fake-test-seed", autofillOnPageLoad: nil, fido2Credentials: nil
        )
        let passkey = Fido2CredentialAutofillView(
            credentialId: Foundation.Data([1]), cipherId: "cipher-1", rpId: "example.com", userNameForUi: "user",
            userHandle: Foundation.Data([2]), hasCounter: false
        )
        let crypto = SpyVaultCryptoService()
        crypto.fido2AutofillCredentialsResult = [passkey]
        let http = MockHTTPClient()
        let source = SDKVaultSessionSource(
            http: http,
            environment: try Domain.ServerEnvironment(baseURL: URL(string: "https://vault.example.com")!),
            crypto: crypto,
            accessToken: { "token" },
            checkAccess: { try Task.checkCancellation() }
        )
        let response = Foundation.Data("""
        {"ciphers":[{"id":"cipher-1","type":1,"name":"encrypted-name","favorite":false,"reprompt":0,
         "revisionDate":"1970-01-01T00:00:00.000Z","creationDate":"1970-01-01T00:00:00.000Z",
         "login":{"username":"encrypted-user","password":"encrypted-password"}}]}
        """.utf8)
        for cipher in [
            CipherView.fixture(login: login),
            CipherView.fixture(login: login, reprompt: .password),
            CipherView.fixture(login: login, viewPassword: false),
        ] {
            crypto.decryptCiphersResult = [cipher]
            http.responses = [HTTPResponse(statusCode: 200, headers: [:], body: response)]
            let output = try await source.fetchOutput()
            let identities = CredentialIdentityMapper.makeIdentities(from: output.identitySources)
            if cipher.reprompt == .none && cipher.viewPassword {
                #expect(identities.map(\.kind) == [.passkey])
                #expect(output.encryptedLoginRecords.count == 1)
            } else {
                #expect(output.identitySources.isEmpty)
                #expect(identities.isEmpty)
                #expect(output.encryptedLoginRecords.isEmpty)
            }
        }
    }
}
