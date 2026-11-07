import BitwardenSDKAdapter
import Domain
import Foundation
import Networking

/// Session-scoped Data assembly. Auth bootstrap supplies an opaque SDK resource and typed account,
/// never a raw Client or token closure. Presentation receives only the Domain session capability;
/// app composition consumes this concrete assembly to build session-bound repositories/adapters.
public struct AuthenticatedSession: AuthenticatedSessionCapability {
    public let runtime: SessionRuntime
    /// Exact persisted identity, including legacy trailing slash. Do not silently rewrite an
    /// existing grant/cache owner merely because Domain normalizes HTTP service routes.
    public let storageAccount: TokenAccountIdentity
    private let sdkSession: SDKSessionClient

    public var id: UUID { runtime.id }
    public var account: AccountSession { runtime.account }
    public var userId: String { runtime.account.accountID.rawValue }
    public var email: String { runtime.account.email }
    public var environment: ServerEnvironment { runtime.account.environment }
    public var sendCryptoService: SDKSendCryptoService { SDKSendCryptoService(sessionClient: sdkSession) }
    public var passwordGeneratorService: SDKPasswordGeneratorService { SDKPasswordGeneratorService(
        sessionClient: sdkSession
    ) }

    public init(
        account: AccountSession,
        resource: SDKSessionClient,
        tokenProvider: any SessionTokenProviding,
        scope: TokenScope
    ) throws {
        try Task.checkCancellation()
        guard resource.isActive else { throw CancellationError() }
        guard !account.accountID.rawValue.isEmpty, scope.account.userID == account.accountID.rawValue,
              try ServerEnvironment(baseURL: scope.account.serverBaseURL).baseURL == account.environment.baseURL
        else { throw CancellationError() }
        guard [account.environment.baseURL, account.environment.apiURL, account.environment.identityURL,
               account.environment.webVaultURL].allSatisfy(ServerURLPolicy.isPermitted) else {
            throw ServerEnvironmentError.invalidBaseURL
        }
        sdkSession = resource
        storageAccount = scope.account
        runtime = SessionRuntime(account: account, resource: resource, tokens: tokenProvider)
    }

    public func checkAccess() throws { try runtime.checkAccess() }
    public func validateAuthorization() async throws { _ = try await runtime.validatedTokenScope() }
    public func validatedTokenScope() async throws -> TokenScope { try await runtime.validatedTokenScope() }

    /// Transport comes from app composition, not an implicit live client hidden in the session.
    /// The token capability never escapes the Data/SDK boundary as a public closure.
    public func makeVaultSource(httpClient: any HTTPClient, initialRevision: UInt64 = 0) -> SDKVaultSourceAdapter {
        SDKVaultSourceAdapter(backing: SDKVaultSessionSource(
            http: SessionHTTPClient(runtime: runtime, base: httpClient), environment: runtime.account.environment,
            crypto: SDKVaultCryptoService(sessionClient: sdkSession),
            accessToken: { [runtime] in await runtime.getAccessToken() },
            requireAccessToken: { [runtime] in try await runtime.requireAccessToken() },
            checkAccess: { [runtime] in try runtime.checkAccess() }, initialRevision: initialRevision
        ))
    }

    @MainActor
    public func scopedPasteboardClient(_ base: any PasteboardClient) -> any PasteboardClient {
        SessionPasteboardClient(runtime: runtime, base: base)
    }

    public func revoke(_ reason: SessionRevocationReason) async { await runtime.revoke(reason) }
    public func derivePINProtectedUserKey(pin: String) async throws -> String {
        try await SDKAuthenticationService(sessionClient: sdkSession).derivePINProtectedUserKey(pin: pin)
    }
}
