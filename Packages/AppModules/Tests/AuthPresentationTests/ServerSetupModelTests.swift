@testable import AuthPresentation
import Domain
import Foundation
import Testing

@MainActor
@Suite
struct ServerSetupModelTests {
    @Test
    func emptyURLShowsError() async {
        var continuedWith: ServerEnvironment?
        let model = ServerSetupModel { continuedWith = $0 }

        await model.perform(.continueTapped)

        #expect(model.state.errorMessage != nil)
        #expect(continuedWith == nil)
    }

    @Test
    func validURLWithoutSchemeDefaultsToHTTPS() async {
        var continuedWith: ServerEnvironment?
        let model = ServerSetupModel { continuedWith = $0 }

        model.receive(.urlTextChanged("vault.example.com"))
        await model.perform(.continueTapped)

        #expect(model.state.errorMessage == nil)
        #expect(continuedWith?.baseURL.absoluteString == "https://vault.example.com")
        #expect(continuedWith?.apiURL.absoluteString == "https://vault.example.com/api")
        #expect(continuedWith?.identityURL.absoluteString == "https://vault.example.com/identity")
    }

    @Test
    func malformedURLShowsError() async {
        var continuedWith: ServerEnvironment?
        let model = ServerSetupModel { continuedWith = $0 }

        model.receive(.urlTextChanged("ftp://vault.example.com"))
        await model.perform(.continueTapped)

        #expect(model.state.errorMessage != nil)
        #expect(continuedWith == nil)
    }

    @Test
    func nonLoopbackHTTPIsRejected() async {
        var continuedWith: ServerEnvironment?
        let model = ServerSetupModel { continuedWith = $0 }

        model.receive(.urlTextChanged("http://vault.example.com"))
        await model.perform(.continueTapped)

        #expect(model.state.errorMessage != nil)
        #expect(continuedWith == nil)
    }

    @Test
    func reverseProxyInputUsesTheOneNormalizedDomainEnvironment() async {
        var continuedWith: ServerEnvironment?
        let model = ServerSetupModel { continuedWith = $0 }
        model.receive(.urlTextChanged("https://vault.example.com/vault/"))
        await model.perform(.continueTapped)
        #expect(continuedWith?.baseURL.absoluteString == "https://vault.example.com/vault")
        #expect(continuedWith?.identityURL.absoluteString == "https://vault.example.com/vault/identity")
    }

    @Test(arguments: ["https://user:password@vault.example.com", "https://vault.example.com?token=fixture",
                      "https://vault.example.com#fragment", "https://vault.example.com:0"])
    func unsafeServerURLsNeverReachLogin(value: String) async {
        var continued = false
        let model = ServerSetupModel { _ in continued = true }
        model.receive(.urlTextChanged(value))
        await model.perform(.continueTapped)
        #expect(!continued)
        #expect(model.state.errorMessage == "Enter a valid HTTPS server URL.")
    }

    @Test
    func debugBuildMayUseLoopbackHTTPForLocalDevelopment() async {
        var continuedWith: ServerEnvironment?
        let model = ServerSetupModel { continuedWith = $0 }

        model.receive(.urlTextChanged("http://localhost:8080"))
        await model.perform(.continueTapped)

        #if DEBUG
            #expect(model.state.errorMessage == nil)
            #expect(continuedWith?.baseURL.absoluteString == "http://localhost:8080")
        #else
            #expect(model.state.errorMessage != nil)
            #expect(continuedWith == nil)
        #endif
    }
}
