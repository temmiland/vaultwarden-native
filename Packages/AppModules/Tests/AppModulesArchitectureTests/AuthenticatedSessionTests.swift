import BitwardenSdk
import BitwardenSDKAdapter
import Data
import Domain
import Foundation
import Networking
import Testing

@Suite
struct AuthenticatedSessionTests {
    private func account() throws -> AccountSession {
        AccountSession(
            accountID: AccountID(rawValue: "account-1"),
            email: "fixture@example.com",
            environment: try ServerEnvironment(baseURL: URL(string: "https://vault.example.com/vault/")!)
        )
    }

    private func scope(userID: String = "account-1", server: String = "https://vault.example.com/vault/") -> TokenScope {
        TokenScope(account: TokenAccountIdentity(userID: userID, serverBaseURL: URL(string: server)!))
    }

    private func resource() -> SDKSessionClient { SDKSessionClient(client: Client(noHandle: Client.NoHandle())) }

    @Test
    func domainRoutesNormalizeWithoutChangingExistingGrantIdentity() async throws {
        let scope = scope()
        let tokens = AssemblyTokens(scope: scope)
        let session = try AuthenticatedSession(
            account: account(),
            resource: resource(),
            tokenProvider: tokens,
            scope: scope
        )
        #expect(session.environment.baseURL.absoluteString == "https://vault.example.com/vault")
        #expect(session.storageAccount.serverBaseURL.absoluteString == "https://vault.example.com/vault/")
        #expect(session.storageAccount == scope.account)
        #expect(try await session.validatedTokenScope() == scope)
    }

    @Test
    func mismatchedAccountOrServerScopeCannotConstructSession() throws {
        for invalid in [scope(userID: "other-account"), scope(server: "https://other.example.com/vault/")] {
            #expect(throws: CancellationError.self) {
                _ = try AuthenticatedSession(
                    account: account(),
                    resource: resource(),
                    tokenProvider: AssemblyTokens(scope: invalid),
                    scope: invalid
                )
            }
        }
    }

    @Test
    func revokedResourceCannotBecomeAFreshSession() throws {
        let resource = resource()
        resource.revoke()
        let scope = scope()
        #expect(throws: CancellationError.self) {
            _ = try AuthenticatedSession(
                account: account(),
                resource: resource,
                tokenProvider: AssemblyTokens(scope: scope),
                scope: scope
            )
        }
    }

    @Test
    func everyCopySharesPermanentRuntimeAndTokenRevocation() async throws {
        let scope = scope()
        let tokens = AssemblyTokens(scope: scope)
        let session = try AuthenticatedSession(
            account: account(),
            resource: resource(),
            tokenProvider: tokens,
            scope: scope
        )
        let copy = session
        #expect(copy.id == session.id)
        try copy.checkAccess()
        await session.revoke(.lock)
        #expect(throws: CancellationError.self) { try copy.checkAccess() }
        do { _ = try await copy.validatedTokenScope(); Issue.record("Revoked copy remained authorized") }
        catch is CancellationError {}
        await copy.revoke(.logout)
        #expect(await tokens.revokeCount == 1)
    }

    @Test
    func vaultSourceUsesInjectedHTTPAndCannotStartAfterRevocation() async throws {
        let scope = scope()
        let tokens = AssemblyTokens(scope: scope)
        let session = try AuthenticatedSession(
            account: account(),
            resource: resource(),
            tokenProvider: tokens,
            scope: scope
        )
        let http = AssemblyHTTPClient()
        let source = session.makeVaultSource(httpClient: http)
        // 503 is deliberately before any SDK crypto. Verify actual scoped transport and route.
        do { _ = try await source.fetchOutput(); Issue.record("Expected fixture server error") }
        catch let error as HTTPStatusError { #expect(error.statusCode == 503) }
        let request = try #require(await http.requests.first)
        #expect(request.url.absoluteString == "https://vault.example.com/vault/api/sync?excludeDomains=true")
        #expect(request.headers["Authorization"] == "Bearer fixture-token")
        await session.revoke(.lock)
        do { _ = try await source.fetchOutput(); Issue.record("Revoked source made a request") }
        catch is CancellationError {}
        #expect(await http.requests.count == 1)
    }
}

private actor AssemblyTokens: SessionTokenProviding {
    let scope: TokenScope
    private(set) var revokeCount = 0
    init(scope: TokenScope) { self.scope = scope }
    func getAccessToken() -> String? { revokeCount == 0 ? "fixture-token" : nil }
    func validatedSessionScope() throws -> TokenScope {
        guard revokeCount == 0 else { throw CancellationError() }
        return scope
    }

    func revoke() { revokeCount += 1 }
}

private actor AssemblyHTTPClient: HTTPClient {
    private(set) var requests: [HTTPRequest] = []
    func send(_ request: HTTPRequest) -> HTTPResponse {
        requests.append(request)
        return HTTPResponse(statusCode: 503, headers: [:], body: Data())
    }

    func upload(_ request: HTTPRequest, fromFile fileURL: URL) async throws -> HTTPResponse { throw CancellationError() }
    func download(_ request: HTTPRequest, to destinationURL: URL) async throws -> HTTPFileResponse { throw CancellationError(
    ) }
}
