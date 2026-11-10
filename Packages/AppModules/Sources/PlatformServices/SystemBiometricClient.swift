import Domain
import Foundation
import LocalAuthentication
import SecurityStorage

/// Internal LAContext seam. Creating a new context for each availability check/evaluation avoids
/// retaining invalidated authorization state and makes the OS error mapping deterministic in tests.
@MainActor
protocol LocalAuthenticationContext: AnyObject {
    var biometryType: LABiometryType { get }
    var keychainAuthenticationContext: KeychainAuthenticationContext { get }
    func invalidate()
    func preventAdditionalInteraction()
    func canEvaluateBiometrics() -> Result<Void, NSError>
    func evaluateBiometrics(reason: String) async -> Result<Bool, NSError>
}

@MainActor
protocol LocalAuthenticationContextFactory: AnyObject {
    func makeContext() -> any LocalAuthenticationContext
}

@MainActor
private final class SystemLocalAuthenticationContext: LocalAuthenticationContext {
    private let context = LAContext()

    var biometryType: LABiometryType { context.biometryType }
    var keychainAuthenticationContext: KeychainAuthenticationContext { KeychainAuthenticationContext(context) }
    func invalidate() { context.invalidate() }
    func preventAdditionalInteraction() { context.interactionNotAllowed = true }

    func canEvaluateBiometrics() -> Result<Void, NSError> {
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .failure(error ?? LAError(.biometryNotAvailable) as NSError)
        }
        return .success(())
    }

    func evaluateBiometrics(reason: String) async -> Result<Bool, NSError> {
        await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
                if let error = error as NSError? {
                    continuation.resume(returning: .failure(error))
                } else {
                    continuation.resume(returning: .success(success))
                }
            }
        }
    }
}

@MainActor
private final class SystemLocalAuthenticationContextFactory: LocalAuthenticationContextFactory {
    func makeContext() -> any LocalAuthenticationContext {
        SystemLocalAuthenticationContext()
    }
}

/// The only LocalAuthentication adapter in the target architecture. It converts framework errors
/// into presentation-safe Domain results; no feature needs to import LocalAuthentication or inspect
/// `LAError` values directly.
@MainActor
public final class SystemBiometricClient: BiometricClient {
    private let contextFactory: any LocalAuthenticationContextFactory

    public convenience init() {
        self.init(contextFactory: SystemLocalAuthenticationContextFactory())
    }

    init(contextFactory: any LocalAuthenticationContextFactory) {
        self.contextFactory = contextFactory
    }

    public func availability() -> BiometricAvailability {
        let context = contextFactory.makeContext()
        switch context.canEvaluateBiometrics() {
        case .success:
            return .available(Self.biometryKind(from: context.biometryType))
        case let .failure(error):
            return .unavailable(Self.unavailableReason(from: error))
        }
    }

    public func evaluate(reason: String) async -> BiometricEvaluationResult {
        let context = contextFactory.makeContext()
        defer { context.invalidate() }
        return await evaluate(context: context, reason: reason)
    }

    public func performAuthenticated<Value: Sendable>(
        reason: String, operation: @MainActor () throws -> Value
    ) async throws -> (BiometricEvaluationResult, Value?) {
        let context = contextFactory.makeContext()
        defer { context.invalidate() }
        let result = await evaluate(context: context, reason: reason)
        guard result == .succeeded else { return (result, nil) }
        context.preventAdditionalInteraction()
        return try KeychainAuthenticationScope.$current.withValue(context.keychainAuthenticationContext) {
            (result, try operation())
        }
    }

    private func evaluate(context: any LocalAuthenticationContext, reason: String) async -> BiometricEvaluationResult {
        switch context.canEvaluateBiometrics() {
        case let .failure(error):
            return .unavailable(Self.unavailableReason(from: error))
        case .success:
            break
        }

        switch await context.evaluateBiometrics(reason: reason) {
        case .success(true):
            return .succeeded
        case .success(false):
            return .failed
        case let .failure(error):
            return Self.evaluationResult(from: error)
        }
    }

    static func biometryKind(from type: LABiometryType) -> BiometryKind {
        switch type {
        case .touchID:
            return .touchID
        case .faceID:
            return .faceID
        case .opticID:
            return .opticID
        default:
            return .unknown
        }
    }

    static func unavailableReason(from error: NSError) -> BiometricUnavailableReason {
        guard error.domain == LAError.errorDomain,
              let code = LAError.Code(rawValue: error.code)
        else { return .unknown }

        switch code {
        case .biometryNotAvailable:
            return .notAvailable
        case .biometryNotEnrolled:
            return .notEnrolled
        case .biometryLockout:
            return .lockedOut
        case .passcodeNotSet:
            return .passcodeNotSet
        default:
            return .unknown
        }
    }

    static func evaluationResult(from error: NSError) -> BiometricEvaluationResult {
        guard error.domain == LAError.errorDomain,
              let code = LAError.Code(rawValue: error.code)
        else { return .failed }

        switch code {
        case .userCancel, .appCancel, .systemCancel:
            return .cancelled
        case .biometryNotAvailable, .biometryNotEnrolled, .biometryLockout, .passcodeNotSet:
            return .unavailable(Self.unavailableReason(from: error))
        default:
            return .failed
        }
    }
}
