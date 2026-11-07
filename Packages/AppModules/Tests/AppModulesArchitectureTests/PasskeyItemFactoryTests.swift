import BitwardenSdk
import BitwardenSDKAdapter
import Foundation
import Testing

/// The item a passkey saved from the AutoFill extension lands in has to be a normal login,
/// indistinguishable from one created in the app - otherwise it shows up half-formed in the vault.
@Suite
struct PasskeyItemFactoryTests {
    @Test
    func newItemIsALoginNamedAfterTheRelyingParty() {
        let cipher = PasskeyItemFactory.makeLoginCipherView(
            relyingPartyIdentifier: "example.com", userName: "ada@example.com"
        )

        #expect(cipher.type == .login)
        #expect(cipher.name == "example.com")
        #expect(cipher.login?.username == "ada@example.com")
    }

    /// The item needs a URI, or ordinary password autofill won't match it to the site it was
    /// created for - a passkey entry that doesn't answer for its own domain is confusing.
    @Test
    func newItemCarriesTheSiteAsAnHTTPSURI() {
        let cipher = PasskeyItemFactory.makeLoginCipherView(
            relyingPartyIdentifier: "example.com", userName: nil
        )

        #expect(cipher.login?.uris?.compactMap(\.uri) == ["https://example.com"])
    }

    /// A new item has no server-side identity yet; `ServerPasskeyWriter` keys off exactly this to
    /// decide create-vs-update, so a stray id here would turn a create into a failing update.
    @Test
    func newItemHasNoIdYet() {
        let cipher = PasskeyItemFactory.makeLoginCipherView(
            relyingPartyIdentifier: "example.com", userName: "ada"
        )

        #expect(cipher.id == nil)
    }

    @Test
    func aMissingUserNameYieldsAnEmptyUsernameRatherThanACrash() {
        let cipher = PasskeyItemFactory.makeLoginCipherView(
            relyingPartyIdentifier: "example.com", userName: nil
        )

        #expect(cipher.login?.username == nil || cipher.login?.username?.isEmpty == true)
    }
}
