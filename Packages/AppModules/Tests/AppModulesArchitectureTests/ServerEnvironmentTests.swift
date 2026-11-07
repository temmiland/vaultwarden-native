@testable import Domain
import Foundation
import Testing

/// Existing Core regression semantics on the single Domain owner; no unused icon route bridge.
@Suite
struct ServerEnvironmentTests {
    @Test
    func derivesSubServiceURLsFromSingleBase() throws {
        let environment = try ServerEnvironment(baseURL: URL(string: "https://vault.example.com")!)
        #expect(environment.apiURL.absoluteString == "https://vault.example.com/api")
        #expect(environment.identityURL.absoluteString == "https://vault.example.com/identity")
        #expect(environment.webVaultURL.absoluteString == "https://vault.example.com")
    }

    @Test
    func preservesExistingExplicitServiceRoutes() throws {
        let environment = try ServerEnvironment(
            baseURL: URL(string: "https://vault.example.com")!,
            apiURL: URL(string: "https://api.example.com")!,
            identityURL: URL(string: "https://identity.example.com")!,
            webVaultURL: URL(string: "https://vault.example.com")!
        )
        #expect(environment.apiURL.absoluteString == "https://api.example.com")
        #expect(environment.identityURL.absoluteString == "https://identity.example.com")
    }

    @Test
    func serverURLPolicyRejectsCleartextNonLoopbackHosts() {
        #expect(!ServerURLPolicy.isPermitted(URL(string: "http://vault.example.com")!))
        #expect(ServerURLPolicy.isPermitted(URL(string: "https://vault.example.com")!))
    }

    @Test(arguments: ["https://user:password@vault.example.com", "https://vault.example.com?token=fixture",
                      "https://vault.example.com#fragment", "https://vault.example.com:0",
                      "https://vault.example.com:65536", "file:///fixture", "https:///vault"])
    func rejectsUnsafeBaseAndServiceURLs(value: String) throws {
        // Foundation can reject malformed URL strings even before Domain validation.
        guard let url = URL(string: value) else { return }
        #expect(!ServerURLPolicy.isPermitted(url))
        #expect(throws: ServerEnvironmentError.invalidBaseURL) { _ = try ServerEnvironment(baseURL: url) }
        #expect(throws: ServerEnvironmentError.invalidBaseURL) {
            _ = try ServerEnvironment(
                baseURL: URL(string: "https://vault.example.com")!,
                apiURL: url,
                identityURL: URL(string: "https://vault.example.com/identity")!,
                webVaultURL: URL(string: "https://vault.example.com")!
            )
        }
    }

    @Test(arguments: ["http://localhost:8080/vault", "http://127.0.0.1:8080", "http://[::1]:8080"])
    func loopbackHTTPMatchesTheBuildPolicy(value: String) {
        let permitted = ServerURLPolicy.isPermitted(URL(string: value)!)
        #if DEBUG
            #expect(permitted)
        #else
            #expect(!permitted)
        #endif
    }

    @Test
    func decodedEnvironmentCannotBypassURLValidationAndKeepsWireFields() throws {
        let environment = try ServerEnvironment(baseURL: URL(string: "https://vault.example.com/vault/")!)
        let encoded = try JSONEncoder().encode(environment)
        #expect(try JSONDecoder().decode(ServerEnvironment.self, from: encoded) == environment)
        var fields = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: String])
        #expect(Set(fields.keys) == ["baseURL", "apiURL", "identityURL", "webVaultURL"])
        fields["identityURL"] = "https://user:password@vault.example.com/identity"
        let unsafe = try JSONSerialization.data(withJSONObject: fields)
        #expect(throws: ServerEnvironmentError.invalidBaseURL) { _ = try JSONDecoder().decode(
            ServerEnvironment.self,
            from: unsafe
        ) }
    }
}
