import BitwardenSDKAdapter
import Foundation

/// Whole-registration single-flight + final receipt gate, independent of Apple/SDK callbacks.
/// Crypto output alone never authorizes completion without this invocation's confirmed write.
public actor PasskeyRegistrationCoordinator {
    private let writer: PasskeyRegistrationWriter
    private var isRegistering = false
    public init(writer: PasskeyRegistrationWriter) { self.writer = writer }
    public func register(
        checkAccess: @Sendable () throws -> Void,
        operation: @Sendable () async throws -> SDKAutoFillRegistrationResult
    ) async throws -> SDKAutoFillRegistrationResult {
        try Task.checkCancellation()
        guard !isRegistering else { throw AutoFillOperationError.operationInProgress }
        isRegistering = true
        defer { isRegistering = false }
        try checkAccess()
        try await writer.prepareAttempt()
        try Task.checkCancellation()
        let result: SDKAutoFillRegistrationResult
        do { result = try await operation() }
        catch {
            // FFI may wrap callback errors. Recover our operation's redacted terminal state,
            // never classify an unknown/confirmed server mutation as a retryable SDK failure.
            if let failure = await writer.lastFailure() { throw failure }
            if await writer.requiresRecovery() { throw PasskeyRegistrationError.committedNeedsRepair }
            throw error
        }
        try Task.checkCancellation()
        try checkAccess()
        guard let receipt = await writer.confirmedReceipt() else { throw AutoFillOperationError.saveFailed }
        guard receipt.credentialID == result.credentialID, !result.attestationObject.isEmpty else {
            throw PasskeyRegistrationError.committedNeedsRepair
        }
        try Task.checkCancellation()
        try checkAccess()
        return result
    }
}
