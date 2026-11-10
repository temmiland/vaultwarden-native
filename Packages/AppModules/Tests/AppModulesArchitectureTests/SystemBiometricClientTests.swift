import Domain
import Foundation
import LocalAuthentication
@testable import PlatformServices
import Security
@testable import SecurityStorage
import Testing

@Suite
@MainActor
struct SystemBiometricClientTests {
    @Test
    func theRealKeychainAcceptsAScopedContextWithoutPromptingForUnprotectedMetadata() throws {
        let key = "context-probe-" + UUID().uuidString
        let store = DefaultKeychainStore(service: "land.temmi.vaultwarden-macos.tests")
        defer { try? store.remove(key) }
        let value = Data("synthetic-context-probe".utf8)
        try store.write(value, for: key)
        let context = LAContext()
        context.interactionNotAllowed = true
        defer { context.invalidate() }
        try KeychainAuthenticationScope.$current.withValue(KeychainAuthenticationContext(context)) {
            let restored = try store.read(key)
            #expect(restored == value)
        }
        #expect(KeychainAuthenticationScope.current == nil)
    }

    @Test
    func oneAuthenticatedContextReachesTheProtectedReadAndIsDiscardedAfterwards() async throws {
        let context = MockLocalAuthenticationContext(canEvaluate: .success(()))
        let client: any BiometricClient = SystemBiometricClient(
            contextFactory: MockLocalAuthenticationContextFactory(contexts: [context])
        )
        let access = AuthenticationRecordingKeychainAccess()
        let store = DefaultKeychainStore(service: "synthetic", systemAccess: access)
        let (result, value) = try await client.performAuthenticated(reason: "Unlock") {
            #expect(context.interactionPrevented)
            return try store.read("synthetic-key")
        }
        #expect(result == .succeeded)
        #expect(value == Data("synthetic".utf8))
        #expect(context.evaluationCount == 1)
        #expect(access.authenticationContext?.value === context.rawAuthenticationContext)
        #expect(KeychainAuthenticationScope.current == nil)
        #expect(context.invalidated)
    }

    @Test
    func cancelledAuthenticationNeverReadsAProtectedItem() async throws {
        let context = MockLocalAuthenticationContext(
            canEvaluate: .success(()), evaluation: .failure(laError(.userCancel))
        )
        let client: any BiometricClient = SystemBiometricClient(
            contextFactory: MockLocalAuthenticationContextFactory(contexts: [context])
        )
        let (result, value): (BiometricEvaluationResult, String?) = try await client.performAuthenticated(
            reason: "Unlock"
        ) {
            Issue.record("Cancelled authentication executed the protected operation")
            return "unexpected"
        }
        #expect(result == .cancelled)
        #expect(value == nil)
        #expect(KeychainAuthenticationScope.current == nil)
        #expect(context.invalidated)
    }

    @Test
    func aFailedProtectedOperationStillClearsAndInvalidatesItsContext() async {
        let context = MockLocalAuthenticationContext(canEvaluate: .success(()))
        let client: any BiometricClient = SystemBiometricClient(
            contextFactory: MockLocalAuthenticationContextFactory(contexts: [context])
        )
        await #expect(throws: KeychainStoreError.decodeFailed) {
            let _: (BiometricEvaluationResult, String?) = try await client.performAuthenticated(reason: "Unlock") {
                throw KeychainStoreError.decodeFailed
            }
        }
        #expect(KeychainAuthenticationScope.current == nil)
        #expect(context.invalidated)
    }

    @Test
    func availableSensorReportsTheSpecificBiometryKind() {
        let context = MockLocalAuthenticationContext(canEvaluate: .success(()), biometryType: .faceID)
        let client = SystemBiometricClient(contextFactory: MockLocalAuthenticationContextFactory(contexts: [context]))

        #expect(client.availability() == .available(.faceID))
    }

    @Test
    func unavailableEnrollmentAndLockoutStayDistinguishable() {
        let notEnrolled = MockLocalAuthenticationContext(
            canEvaluate: .failure(laError(.biometryNotEnrolled)), biometryType: .none
        )
        let lockedOut = MockLocalAuthenticationContext(
            canEvaluate: .failure(laError(.biometryLockout)), biometryType: .none
        )

        let enrollmentClient = SystemBiometricClient(
            contextFactory: MockLocalAuthenticationContextFactory(contexts: [notEnrolled])
        )
        let lockoutClient = SystemBiometricClient(
            contextFactory: MockLocalAuthenticationContextFactory(contexts: [lockedOut])
        )

        #expect(enrollmentClient.availability() == .unavailable(.notEnrolled))
        #expect(lockoutClient.availability() == .unavailable(.lockedOut))
    }

    @Test
    func evaluationSeparatesUserCancellationFromAuthenticationFailure() async {
        let cancelled = MockLocalAuthenticationContext(
            canEvaluate: .success(()), evaluation: .failure(laError(.userCancel))
        )
        let failed = MockLocalAuthenticationContext(
            canEvaluate: .success(()), evaluation: .failure(laError(.authenticationFailed))
        )

        let cancelledClient = SystemBiometricClient(
            contextFactory: MockLocalAuthenticationContextFactory(contexts: [cancelled])
        )
        let failedClient = SystemBiometricClient(
            contextFactory: MockLocalAuthenticationContextFactory(contexts: [failed])
        )

        #expect(await cancelledClient.evaluate(reason: "Unlock") == .cancelled)
        #expect(await failedClient.evaluate(reason: "Unlock") == .failed)
    }

    @Test
    func evaluationDoesNotPromptWhenTheSensorIsUnavailable() async {
        let context = MockLocalAuthenticationContext(
            canEvaluate: .failure(laError(.biometryNotAvailable))
        )
        let client = SystemBiometricClient(contextFactory: MockLocalAuthenticationContextFactory(contexts: [context]))

        #expect(await client.evaluate(reason: "Unlock") == .unavailable(.notAvailable))
        #expect(context.evaluationCount == 0)
    }
}

@MainActor
private final class MockLocalAuthenticationContextFactory: LocalAuthenticationContextFactory {
    private var contexts: [MockLocalAuthenticationContext]

    init(contexts: [MockLocalAuthenticationContext]) {
        self.contexts = contexts
    }

    func makeContext() -> any LocalAuthenticationContext {
        precondition(!contexts.isEmpty, "A test requested more LocalAuthentication contexts than configured")
        return contexts.removeFirst()
    }
}

@MainActor
private final class MockLocalAuthenticationContext: LocalAuthenticationContext {
    let canEvaluate: Result<Void, NSError>
    let evaluation: Result<Bool, NSError>
    let biometryType: LABiometryType
    private(set) var evaluationCount = 0
    let rawAuthenticationContext = NSObject()
    var keychainAuthenticationContext: KeychainAuthenticationContext { KeychainAuthenticationContext(
        rawAuthenticationContext
    ) }
    private(set) var invalidated = false
    private(set) var interactionPrevented = false
    func invalidate() { invalidated = true }
    func preventAdditionalInteraction() { interactionPrevented = true }

    init(
        canEvaluate: Result<Void, NSError>,
        evaluation: Result<Bool, NSError> = .success(true),
        biometryType: LABiometryType = .touchID
    ) {
        self.canEvaluate = canEvaluate
        self.evaluation = evaluation
        self.biometryType = biometryType
    }

    func canEvaluateBiometrics() -> Result<Void, NSError> { canEvaluate }

    func evaluateBiometrics(reason _: String) async -> Result<Bool, NSError> {
        evaluationCount += 1
        return evaluation
    }
}

private func laError(_ code: LAError.Code) -> NSError {
    NSError(domain: LAError.errorDomain, code: code.rawValue)
}

private final class AuthenticationRecordingKeychainAccess: KeychainSystemAccess, @unchecked Sendable {
    private let lock = NSLock()
    private var captured: KeychainAuthenticationContext?
    var authenticationContext: KeychainAuthenticationContext? { lock.withLock { captured } }
    func update(_: KeychainItem, value _: Data, protection _: KeychainProtection) -> OSStatus { errSecSuccess }
    func add(_: KeychainItem, value _: Data, protection _: KeychainProtection) -> OSStatus { errSecSuccess }
    func remove(_: KeychainItem) -> OSStatus { errSecSuccess }
    func read(_: KeychainItem, authenticationContext: KeychainAuthenticationContext?) -> KeychainReadResponse {
        lock.withLock { captured = authenticationContext }
        return KeychainReadResponse(status: errSecSuccess, data: Data("synthetic".utf8))
    }
}
