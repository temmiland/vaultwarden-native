@testable import AuthPresentation
import BitwardenSdk
import BitwardenSDKAdapter
@testable import Data
import Domain
import Foundation
import Testing

@MainActor
@Suite
struct AuthCompositionIntegrationTests {
    @Test
    func repositoryAndPINSettingsUseExactlyTheInjectedCredentialStore() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "vw-auth-services-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let privateKeychain = MockKeychainService()
        let sharedKeychain = MockKeychainService()
        let store = AuthCredentialStore(
            keychain: privateKeychain,
            sharedKeychain: sharedKeychain,
            sharedContainerURL: directory
        )
        let account = StoredAuthAccount.fixture()
        let saved = try store.saveSession(account: account, tokens: TokenPair(
            accessToken: "fixture-access", refreshToken: "fixture-refresh", expiresAt: .distantFuture
        ))
        let repository = DefaultAuthRepository(persistence: store)
        let tokens = MockIdentityTokenService()
        let commands = DefaultAuthFlowService(
            store: store,
            repository: repository,
            prelogin: DefaultPreloginService(httpClient: MockHTTPClient()),
            tokens: tokens,
            biometric: MockBiometricClient(),
            deviceName: MockDeviceNameClient(),
            applicationVersion: "0.0.0"
        )
        guard case let .returningUnlock(unlock) = try await commands.restore() else {
            Issue.record("The flow did not use the injected credential store"); return
        }
        #expect(unlock.account.session == (try AccountSession(storedAccount: account)))
        #expect(await repository.currentSnapshot().state == .locked(try AccountSession(storedAccount: account)))
        try store.enrollPinProtectedUserKey(
            "fixture-protected-pin-key",
            requiringScope: saved.scope,
            publicationEpoch: store.autofillPublicationEpoch()
        )
        let provider = AppAuthTokenProvider(
            identityURL: account.serverBaseURL.appendingPathComponent("identity"),
            keychainStore: store,
            tokenService: tokens,
            scope: saved.scope
        )
        let session = try AuthenticatedSession(
            account: AccountSession(storedAccount: account),
            resource: SDKSessionClient(client: Client(noHandle: Client.NoHandle())),
            tokenProvider: provider,
            scope: saved.scope
        )
        let enrollment = SessionPinUnlockSettings(session: session, store: store)
        #expect(try await enrollment.isEnabled())
        try await enrollment.remove()
        #expect(try store.loadAccount()?.isPinUnlockEnabled == false)
        try await repository.lock()
        #expect(try store.loadSession()?.tokens.accessToken == "fixture-access")
        #expect(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(".vaultwarden-token-store.lock").path
            )
        )
        await session.revoke(.lock)
    }
}
