import Domain
import Foundation

extension AuthCredentialStore {
    /// Capture authority before any HTTP/crypto suspension. Returning unlocks must match the
    /// persisted account, lineage and pre-unlock epoch; fresh login cannot borrow old tokens.
    public func makeTokenProvider(
        identityURL: URL,
        restoringAccount: StoredAuthAccount? = nil,
        expectedScope: TokenScope? = nil,
        expectedPublicationEpoch: UUID? = nil,
        tokenService: any TokenRefreshing
    ) throws -> AppAuthTokenProvider {
        try Task.checkCancellation()
        guard ServerURLPolicy.isPermitted(identityURL) else { throw ServerEnvironmentError.invalidBaseURL }
        var scope: TokenScope?
        var authorizationEpoch: UUID?
        if let restoringAccount {
            guard let session = try loadSession(), session.account == restoringAccount,
                  expectedScope == nil || session.scope == expectedScope,
                  (try? ServerEnvironment(baseURL: restoringAccount.serverBaseURL))?.identityURL == identityURL
            else { throw CancellationError() }
            scope = session.scope
            authorizationEpoch = try returningUnlockEpoch(
                requiringScope: session.scope,
                expectedEpoch: expectedPublicationEpoch
            )
        }
        return AppAuthTokenProvider(
            identityURL: identityURL,
            keychainStore: self,
            tokenService: tokenService,
            scope: scope,
            freshLoginProof: restoringAccount == nil ? try freshLoginCommitProof() : nil,
            authorizationEpoch: authorizationEpoch
        )
    }
}
