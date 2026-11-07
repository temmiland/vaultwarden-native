import Domain
import Foundation
import LocalAuthentication

protocol PasskeyVerificationContext: Sendable {
    func canVerify() -> Bool
    func evaluate(reason: String) async throws -> Bool
}

/// Each factory call returns a new context used by one evaluation, not cached authorization.
private final class DeviceOwnerPasskeyContext: PasskeyVerificationContext, @unchecked Sendable {
    private let context = LAContext()
    func canVerify() -> Bool { context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }
    func evaluate(reason: String) async throws -> Bool {
        try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }
}

public struct SystemPasskeyUserVerifier: PasskeyUserVerifying {
    private let makeContext: @Sendable () -> any PasskeyVerificationContext
    public init() { makeContext = { DeviceOwnerPasskeyContext() } }
    init(makeContext: @escaping @Sendable () -> any PasskeyVerificationContext) { self.makeContext = makeContext }
    public func isVerificationAvailable() -> Bool {
        makeContext().canVerify()
    }

    public func verify(reason: String) async throws -> Bool {
        try Task.checkCancellation()
        let context = makeContext()
        guard context.canVerify() else { return false }
        do {
            let verified = try await context.evaluate(reason: reason)
            try Task.checkCancellation()
            return verified
        } catch {
            try Task.checkCancellation()
            let failure = error as NSError
            if failure.domain == LAError.errorDomain, failure.code == LAError.userCancel.rawValue {
                throw PasskeyUserVerificationError.userCanceled
            }
            return false // user/OS rejection is not successful verification
        }
    }
}
