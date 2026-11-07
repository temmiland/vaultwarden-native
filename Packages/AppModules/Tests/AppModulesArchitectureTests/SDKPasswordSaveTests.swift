import BitwardenSdk
@testable import BitwardenSDKAdapter
import Foundation
import Testing

@Suite
struct SDKPasswordSaveTests {
    @Test
    func updatePreservesExistingURIRestrictionsTOTPAndPasskeys() throws {
        let original = AutoFillQuerySourceFixture.view(hasPasskeys: true, uriMatchType: .exact)
        let view = try SDKAutoFillService.passwordSaveView(
            title: "Untrusted new title", username: "new-user", password: "new-password",
            uri: "https://different.example.org", target: SDKAutoFillCredentialView(legacyView: original)
        )
        #expect(view.id == original.id && view.name == original.name)
        #expect(view.login?.username == "new-user" && view.login?.password == "new-password")
        #expect(view.login?.uris == original.login?.uris)
        #expect(view.login?.totp == original.login?.totp)
        #expect(view.login?.fido2Credentials == original.login?.fido2Credentials)
        #expect(view.fields == original.fields && view.organizationId == original.organizationId)
    }

    @Test
    func createHasNoExistingItemOrPasskeyAuthority() throws {
        let view = try SDKAutoFillService.passwordSaveView(
            title: "Example",
            username: "user",
            password: "secret",
            uri: "https://example.com",
            target: nil
        )
        #expect(view.id == nil && view.organizationId == nil && view.collectionIds.isEmpty)
        #expect(view.name == "Example" && view.login?.username == "user" && view.login?.password == "secret")
        #expect(view.login?.uris?.first?.uri == "https://example.com")
        #expect(view.login?.fido2Credentials?.isEmpty != false)
    }

    @Test(arguments: ["reprompt", "readonly", "unsupported"])
    func protectedOrLossyTargetsCannotBecomePasswordUpdates(_ scenario: String) throws {
        let target = SDKAutoFillCredentialView(
            legacyView: .fixture(edit: scenario != "readonly", reprompt: scenario == "reprompt" ? .password : .none),
            supportsLosslessEditing: scenario != "unsupported"
        )
        #expect(throws: SDKAutoFillFidoError.accessDenied) {
            _ = try SDKAutoFillService.passwordSaveView(
                title: "Example",
                username: "user",
                password: "secret",
                uri: "https://example.com",
                target: target
            )
        }
    }
}
