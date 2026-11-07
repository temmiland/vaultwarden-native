import AppFeature
import BitwardenSDKAdapter
import Data
import Domain
import Foundation
import Networking
import Observation
import SecurityStorage
import XCTest

/// Each test owns isolated, in-memory credentials; never the contributor's actual Keychain.
final class IntegrationKeychain: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Foundation.Data] = [:]
    func write(_ value: Foundation.Data, for account: String, protection: KeychainProtection) {
        lock.withLock { values[account] = value }
    }

    func read(_ account: String) throws -> Foundation.Data {
        try lock.withLock {
            guard let value = values[account] else { throw KeychainStoreError.notFound }
            return value
        }
    }

    func remove(_ account: String) { _ = lock.withLock { values.removeValue(forKey: account) } }
}

actor IntegrationHTTP: HTTPClient {
    private(set) var requests: [HTTPRequest] = []

    func send(_ request: HTTPRequest) -> HTTPResponse {
        requests.append(request)
        return HTTPResponse(statusCode: 503, headers: [:], body: Foundation.Data())
    }

    func upload(_ request: HTTPRequest, fromFile fileURL: URL) throws -> HTTPResponse { throw CancellationError() }
    func download(_ request: HTTPRequest, to destinationURL: URL) throws -> HTTPFileResponse { throw CancellationError() }
}

@MainActor
final class IntegrationBiometric: BiometricClient {
    func availability() -> BiometricAvailability { .unavailable(.notAvailable) }
    func evaluate(reason: String) async -> BiometricEvaluationResult { .unavailable(.notAvailable) }
}

@MainActor
final class IntegrationDevice: DeviceNameClient {
    func currentDeviceName() -> String { "Synthetic integration device" }
}

/// One-shot rendezvous: tests prove an interleaving by waiting for `entered`, not by sleeping.
final class IntegrationGate: @unchecked Sendable {
    let entered = XCTestExpectation(description: "Gate entered")
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init() { entered.assertForOverFulfill = false }

    func pass() async {
        entered.fulfill()
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock {
                if isOpen { return true }
                waiters.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func open() {
        let pending = lock.withLock {
            isOpen = true
            defer { waiters = [] }
            return waiters
        }
        pending.forEach { $0.resume() }
    }
}

enum IntegrationFileFailure: Error, Equatable { case preparation, cleanup }

/// Injected in place of `SensitiveTemporaryFileStore.shared` session hooks. Records ordering so a
/// test can prove final cleanup waited for (noncooperative) preparation instead of racing it.
final class IntegrationFileLifecycle: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    private var preparationGate: IntegrationGate?
    private var failsPreparation = false
    private var failsCleanup = false

    var events: [String] { lock.withLock { recorded } }

    func holdPreparation(at gate: IntegrationGate) { lock.withLock { preparationGate = gate } }
    func failPreparation(_ fails: Bool) { lock.withLock { failsPreparation = fails } }
    func failCleanup(_ fails: Bool) { lock.withLock { failsCleanup = fails } }

    func prepare() async throws {
        let (gate, fails) = lock.withLock {
            recorded.append("prepare")
            return (preparationGate, failsPreparation)
        }
        // Deliberately ignores cancellation, like a filesystem call already in progress.
        await gate?.pass()
        lock.withLock { recorded.append("prepared") }
        if fails { throw IntegrationFileFailure.preparation }
    }

    func cleanUp() throws {
        let fails = lock.withLock {
            recorded.append("cleanup")
            return failsCleanup
        }
        if fails { throw IntegrationFileFailure.cleanup }
    }
}

enum IntegrationIsolationError: Error { case hostResolvesSharedAppGroup }

@MainActor
struct IntegrationAssembly {
    private let privateKeychain = IntegrationKeychain()
    let store: AuthCredentialStore
    let http = IntegrationHTTP()
    let files: IntegrationFileLifecycle
    let defaults: UserDefaults
    let defaultsName = "vaultwarden.integration.\(UUID().uuidString)"
    let composition: AppComposition
    let environment: ServerEnvironment
    let storedAccount: StoredAuthAccount

    init(files: IntegrationFileLifecycle = IntegrationFileLifecycle()) throws {
        // The real composition still reaches SharedAppGroup for AutoFill projection/identity
        // coordination. The hostless bundle must resolve no App Group, so those paths fail closed
        // before any owner container, shared Keychain or system credential-identity store.
        guard SharedAppGroup.containerURL == nil else { throw IntegrationIsolationError.hostResolvesSharedAppGroup }
        store = AuthCredentialStore(
            keychain: privateKeychain, sharedKeychain: IntegrationKeychain(), sharedLockPolicy: .processOnly
        )
        self.files = files
        defaults = UserDefaults(suiteName: defaultsName)!
        composition = AppComposition(
            credentials: store, http: http, biometric: IntegrationBiometric(), deviceName: IntegrationDevice(),
            timeoutSettings: DefaultVaultTimeoutSettingsRepository(userDefaults: defaults),
            prepareSession: { try await files.prepare() }, cleanUpFiles: { try files.cleanUp() }
        )
        environment = try ServerEnvironment(baseURL: URL(string: "https://vault.example.invalid/proxy")!)
        storedAccount = StoredAuthAccount(
            userId: "synthetic-account", email: "synthetic@example.invalid", serverBaseURL: environment.baseURL,
            kdfType: 0, kdfIterations: 600_000, kdfMemory: nil, kdfParallelism: nil,
            encryptedUserKey: "synthetic-wrapped-key", encryptedPrivateKey: "synthetic-wrapped-private-key",
            isBiometricUnlockEnabled: false
        )
    }

    func cleanUp() { defaults.removePersistentDomain(forName: defaultsName) }

    var account: AccountSession { get throws { try AccountSession(storedAccount: storedAccount) } }

    /// A returning account as a previous app run would have committed it, without any network.
    @discardableResult
    func saveReturningAccount() throws -> PersistedAuthSession {
        let saved = PersistedAuthSession(
            account: storedAccount,
            scope: TokenScope(account: storedAccount.tokenIdentity),
            tokens: TokenPair(
                accessToken: "synthetic-access",
                refreshToken: "synthetic-refresh",
                expiresAt: .distantFuture
            )
        )
        try PrivateAuthSessionStore(keychain: privateKeychain).save(saved)
        return saved
    }

    /// The concrete capability a successful unlock hands to app composition. Each call is a new
    /// runtime (new session ID) for the same persisted account.
    func session() throws -> AuthenticatedSession {
        let saved = try saveReturningAccount()
        let resource = SDKSessionClient(
            tokenProvider: SDKManagedTokenAdapter(accessToken: { nil }),
            settings: SDKClientFactory.makeSettings(
                identityURL: environment.identityURL, apiURL: environment.apiURL,
                deviceIdentifier: UUID().uuidString, applicationVersion: "integration"
            )
        )
        return try AuthenticatedSession(
            account: AccountSession(storedAccount: storedAccount), resource: resource,
            tokenProvider: store.makeTokenProvider(
                identityURL: environment.identityURL, restoringAccount: storedAccount,
                tokenService: DefaultTokenRefreshService(httpClient: http)
            ), scope: saved.scope
        )
    }

    /// Mirrors the returning-unlock route: restore to `locked`, then begin the repository unlock
    /// that a submitted password/PIN/biometric command performs before handing off its runtime.
    func beginReturningUnlock() async throws {
        try saveReturningAccount()
        guard case .returningUnlock = try await composition.authCommands.restore() else {
            throw AuthRepositoryError.invalidTransition
        }
        try await composition.authRepository.beginUnlock(account: account)
    }
}

extension XCTestCase {
    /// Bounded wait on the observable app model; re-evaluates only when observed state changes.
    @MainActor
    func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let expectation = XCTestExpectation(description: description)
        let observer = ObservationWaiter(condition: condition, expectation: expectation)
        observer.evaluate()
        await fulfillment(of: [expectation], timeout: timeout)
        observer.stop()
    }
}

@MainActor
private final class ObservationWaiter {
    private let condition: @MainActor () -> Bool
    private let expectation: XCTestExpectation
    private var isFinished = false

    init(condition: @escaping @MainActor () -> Bool, expectation: XCTestExpectation) {
        self.condition = condition
        self.expectation = expectation
    }

    func evaluate() {
        guard !isFinished else { return }
        let satisfied = withObservationTracking {
            condition()
        } onChange: { [weak self] in
            Task { @MainActor in self?.evaluate() }
        }
        if satisfied {
            isFinished = true
            expectation.fulfill()
        }
    }

    func stop() { isFinished = true }
}
