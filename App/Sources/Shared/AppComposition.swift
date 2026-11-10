import AppFeature
import BitwardenSDKAdapter
import Data
import Domain
import Foundation
import Networking
import PlatformServices
import SecurityStorage
import SwiftUI

typealias VaultwardenAppModel = AppModel<AppSessionAdapter>

/// Composition-only bridge from a Domain session resource to concrete session repositories.
/// Feature UI never receives this adapter or the underlying Data/SDK authority.
struct AppSessionAdapter: AppSessionResource {
    let session: AuthenticatedSession
    let vaultRepository: DefaultVaultRepository
    let sendRepository: DefaultSendRepository
    let settingsRepository: DefaultSettingsRepository

    init(session: AuthenticatedSession, http: any HTTPClient) {
        self.session = session
        settingsRepository = DefaultSettingsRepository(runtime: session.runtime, http: http)
        sendRepository = DefaultSendRepository(
            runtime: session.runtime,
            cryptography: SDKSendCryptography(crypto: session.sendCryptoService),
            http: http,
            temporaryFiles: SensitiveTemporaryFileStore.shared
        )
        let projection = SessionVaultProjection.make(session: session)
        vaultRepository = DefaultVaultRepository(
            source: session.makeVaultSource(
                httpClient: http,
                initialRevision: projection.initialRevision
            ),
            projectionWriter: projection.writer,
            identityPublisher: projection.identityPublisher,
            registrationRecovery: projection.registrationRecovery
        )
    }

    var id: UUID { session.id }
    var account: AccountSession { session.runtime.account }
    func checkAccess() throws { try session.checkAccess() }
    func validateAuthorization() async throws { _ = try await session.validatedTokenScope() }
    func revoke(_ reason: SessionRevocationReason) async {
        await session.revoke(reason)
        await vaultRepository.lock()
        await sendRepository.lock()
    }
}

@MainActor
struct AppComposition {
    let authCommands: any AuthFlowCommands
    let biometricClient: any BiometricClient
    let authRepository: any AuthRepository
    let timeoutSettings: DefaultVaultTimeoutSettingsRepository
    private let credentialStore: AuthCredentialStore
    private let http: any HTTPClient
    private let prepareSession: @Sendable () async throws -> Void
    private let cleanUpFiles: @Sendable () async throws -> Void
    private let timeoutUnlockStore: SharedAutoFillUnlockStore?

    init() throws {
        // Validate before constructing any credential store, repository or authenticating UI.
        let storage = try SharedAppGroup.validatedStorage()
        AppStorageProbe.runIfRequested(containerURL: storage.containerURL)
        let credentials = AuthCredentialStore(
            keychain: DefaultKeychainStore(service: storage.configuration.privateKeychainService),
            sharedKeychain: SharedAppGroup.makeSharedKeychain(configuration: storage.configuration),
            sharedContainerURL: storage.containerURL
        )
        self.init(
            credentials: credentials,
            http: URLSessionHTTPClient(),
            biometric: SystemBiometricClient(),
            deviceName: SystemDeviceNameClient(),
            timeoutSettings: DefaultVaultTimeoutSettingsRepository(),
            timeoutUnlockStore: try SharedAppGroup.makeUnlockStore(),
            prepareSession: { try await SensitiveTemporaryFileStore.shared.beginSession() },
            cleanUpFiles: { try await SensitiveTemporaryFileStore.shared.removeStaleWorkDirectories() }
        )
    }

    /// The same assembly is exercised with isolated storage/transport in platform tests. The live
    /// initializer above still validates entitlements before constructing any of these dependencies.
    init(
        credentials: AuthCredentialStore,
        http: any HTTPClient,
        biometric: any BiometricClient,
        deviceName: any DeviceNameClient,
        timeoutSettings: DefaultVaultTimeoutSettingsRepository,
        timeoutUnlockStore: SharedAutoFillUnlockStore? = nil,
        prepareSession: @escaping @Sendable () async throws -> Void,
        cleanUpFiles: @escaping @Sendable () async throws -> Void
    ) {
        credentialStore = credentials
        let repository = DefaultAuthRepository(persistence: credentials)
        authRepository = repository
        biometricClient = biometric
        self.http = http
        self.prepareSession = prepareSession
        self.cleanUpFiles = cleanUpFiles
        self.timeoutUnlockStore = timeoutUnlockStore
        authCommands = DefaultAuthFlowService(
            httpClient: http, store: credentials, repository: repository,
            biometric: biometric, deviceName: deviceName,
            applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        )
        self.timeoutSettings = timeoutSettings
    }

    func makeModel() -> VaultwardenAppModel {
        VaultwardenAppModel(
            authRepository: authRepository,
            timeoutDriver: PersistentTimeoutDriver(settings: timeoutSettings, unlockStore: timeoutUnlockStore),
            prepareAuthenticatedSession: prepareSession,
            cleanUpTemporaryFiles: cleanUpFiles
        )
    }

    func makePinUnlockSettings(for session: AuthenticatedSession) -> any PinUnlockSettings {
        SessionPinUnlockSettings(session: session, store: credentialStore)
    }

    /// The only concrete session conversion is in the app composition root, not Auth UI.
    func accept(_ capability: any AuthenticatedSessionCapability, into model: VaultwardenAppModel) async {
        guard let session = capability as? AuthenticatedSession else {
            await capability.revoke(.lock)
            await model.lockNow()
            return
        }
        await model.didAuthenticate(AppSessionAdapter(session: session, http: http))
    }
}

extension AppModel where Session == AppSessionAdapter {
    func scenePhaseChanged(to phase: ScenePhase) async {
        switch phase {
        case .active: await scenePhaseChanged(to: AppScenePhase.active)
        case .inactive: await scenePhaseChanged(to: AppScenePhase.inactive)
        case .background: await scenePhaseChanged(to: AppScenePhase.background)
        @unknown default: break
        }
    }
}

@MainActor
private final class PersistentTimeoutDriver: AppTimeoutDriving {
    private let watchdog: VaultTimeoutWatchdog
    private let settings: any VaultTimeoutSettingsRepository
    private let unlockStore: SharedAutoFillUnlockStore?

    init(settings: any VaultTimeoutSettingsRepository, unlockStore: SharedAutoFillUnlockStore?) {
        self.settings = settings
        self.unlockStore = unlockStore
        watchdog = VaultTimeoutWatchdog(preference: { try settings.load() })
    }

    func noteBecameActive() throws {
        watchdog.noteBecameActive()
        try unlockStore?.setInactiveTimeout(nil)
    }

    func noteBecameInactive() throws {
        watchdog.noteBecameInactive()
        try unlockStore?.setInactiveTimeout(settings.load())
    }

    func pendingAppAction() throws -> AppTimeoutAction? {
        if let action = try unlockStore?.expiredTimeoutAction() {
            return action == .lock ? .lock : .logOut
        }
        guard let pending = try watchdog.pendingAction() else { return nil }
        switch pending {
        case .lock: return .lock
        case .logOut: return .logOut
        }
    }
}
