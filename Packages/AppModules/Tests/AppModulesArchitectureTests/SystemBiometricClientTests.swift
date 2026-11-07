import Domain
import Foundation
import LocalAuthentication
@testable import PlatformServices
import Testing

@Suite
@MainActor
struct SystemBiometricClientTests {
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
