@testable import AuthPresentation
import Domain

@MainActor
final class MockBiometricClient: BiometricClient {
    var availabilityResult: BiometricAvailability = .available(.touchID)
    var evaluationResult: BiometricEvaluationResult = .succeeded
    private(set) var evaluationCount = 0

    func availability() -> BiometricAvailability { availabilityResult }

    func evaluate(reason: String) async -> BiometricEvaluationResult {
        evaluationCount += 1
        return evaluationResult
    }
}
