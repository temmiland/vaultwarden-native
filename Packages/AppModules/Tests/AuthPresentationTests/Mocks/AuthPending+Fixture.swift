@testable import AuthPresentation
import BitwardenSdk
import BitwardenSDKAdapter
import Data
import Domain

/// Presentation has no raw-client factory; these are test-only no-handle integration fixtures.
extension AuthDependencies {
    func pendingSession(client: Client, provider: AppAuthTokenProvider, account: AccountSession) -> PendingAuthSession {
        PendingAuthSession(
            account: account,
            cryptography: SDKAuthCredentialCryptography(
                resource: SDKSessionClient(client: client),
                unlockService: unlockService
            ),
            provider: provider,
            store: keychainStore
        )
    }
}
