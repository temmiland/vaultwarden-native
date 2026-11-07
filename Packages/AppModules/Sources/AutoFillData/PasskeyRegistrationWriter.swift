import AutoFillContract
import BitwardenSDKAdapter
import Domain
import Foundation

public enum PasskeyRegistrationError: Error, Sendable, Equatable {
    case recoveryRequired, recoveryStorageUnavailable, writeRejected, outcomeUnknown, committedNeedsRepair
}

public struct PasskeyRegistrationReceipt: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let mutationID: UUID
    public let credentialID: Data
    public let needsProjectionRepair: Bool
    public var description: String { "PasskeyRegistrationReceipt(<redacted>)" }
    public var debugDescription: String { description }
}

/// Mutation ownership is independent of UI cancellation. The same shared grant still gates
/// writes/projection; once HTTP may have run, no failure can silently reopen a retryable create.
public actor PasskeyRegistrationWriter {
    private var isWriting = false
    private var isTerminal = false
    private var failure: PasskeyRegistrationError?
    private var confirmation: PasskeyRegistrationReceipt?
    public init() {}
    public func lastFailure() -> PasskeyRegistrationError? { failure }
    public func requiresRecovery() -> Bool { isTerminal }
    public func confirmedReceipt() -> PasskeyRegistrationReceipt? { confirmation }
    public func prepareAttempt() throws {
        try Task.checkCancellation()
        guard !isWriting else { throw AutoFillOperationError.operationInProgress }
        guard !isTerminal else { throw PasskeyRegistrationError.recoveryRequired }
        failure = nil
    }

    public func save(
        record: PasskeyRegistrationRecoveryRecord,
        proof: ExtensionUnlockProof,
        journal: any PasskeyRegistrationRecoveryStoring,
        checkAccess: @escaping @Sendable () throws -> Void,
        write: @escaping @Sendable () async throws -> CipherResponseDTO,
        project: @escaping @Sendable (CipherResponseDTO) async throws -> Void
    ) async throws -> PasskeyRegistrationReceipt {
        try Task.checkCancellation()
        guard !isWriting else { throw AutoFillOperationError.operationInProgress }
        guard !isTerminal else { throw PasskeyRegistrationError.recoveryRequired }
        isWriting = true
        failure = nil
        defer { isWriting = false }
        let task = Task {
            try await self.perform(
                record: record,
                proof: proof,
                journal: journal,
                checkAccess: checkAccess,
                write: write,
                project: project
            )
        }
        do { let receipt = try await task.value; confirmation = receipt; return receipt }
        catch let error as PasskeyRegistrationError { failure = error; throw error }
    }

    private func perform(
        record: PasskeyRegistrationRecoveryRecord,
        proof: ExtensionUnlockProof,
        journal: any PasskeyRegistrationRecoveryStoring,
        checkAccess: @Sendable () throws -> Void,
        write: @Sendable () async throws -> CipherResponseDTO,
        project: @Sendable (CipherResponseDTO) async throws -> Void
    ) async throws -> PasskeyRegistrationReceipt {
        try checkAccess()
        do { try journal.reserve(record, requiring: proof) }
        catch PasskeyRegistrationRecoveryError.pendingMutation { throw PasskeyRegistrationError.recoveryRequired }
        catch { throw PasskeyRegistrationError.recoveryStorageUnavailable }
        let persisted: CipherResponseDTO
        do {
            try checkAccess()
            persisted = try await write()
        } catch SDKPasskeyWriteError.notSubmitted {
            try releaseRejected(record, proof: proof, journal: journal)
            throw PasskeyRegistrationError.writeRejected
        } catch SDKPasskeyWriteError.rejected {
            try releaseRejected(record, proof: proof, journal: journal)
            throw PasskeyRegistrationError.writeRejected
        } catch let error as SessionAuthorizationError {
            // The owned SDK transport emits this only before the cipher request. Refresh
            // uncertainty is separate from a potentially committed passkey server mutation.
            try releaseRejected(record, proof: proof, journal: journal)
            throw error
        } catch SDKPasskeyWriteError.confirmedButUnreadable {
            isTerminal = true
            do { try journal.confirm(record.mutationID, serverCipherID: record.targetCipherID, requiring: proof) }
            catch { throw PasskeyRegistrationError.committedNeedsRepair }
            throw PasskeyRegistrationError.committedNeedsRepair
        } catch {
            // Includes lock/cancellation: retain the pre-write marker rather than claiming that
            // an already issued server request could be rolled back or safely retried.
            isTerminal = true
            throw PasskeyRegistrationError.outcomeUnknown
        }
        isTerminal = true
        guard let id = persisted.id, !id.isEmpty, SDKVaultAccessPolicy.isEligibleForAutoFill(persisted),
              record.targetCipherID == nil || record.targetCipherID == id else {
            throw PasskeyRegistrationError.committedNeedsRepair
        }
        var repair = false
        do { try journal.confirm(record.mutationID, serverCipherID: persisted.id, requiring: proof) }
        catch { repair = true } // the durable submitted marker remains; never erase it here
        try checkAccess()
        do { try await project(persisted) }
        catch { repair = true }
        try checkAccess()
        // The marker survives even successful incremental projection until full app sync/OS publication
        // proves the selected credential. A local projection failure does not undo server success.
        return PasskeyRegistrationReceipt(
            mutationID: record.mutationID,
            credentialID: record.credentialID,
            needsProjectionRepair: repair
        )
    }

    private func releaseRejected(
        _ record: PasskeyRegistrationRecoveryRecord,
        proof: ExtensionUnlockProof,
        journal: any PasskeyRegistrationRecoveryStoring
    ) throws {
        do { try journal.remove([record.mutationID], requiring: proof) }
        catch { isTerminal = true; throw PasskeyRegistrationError.recoveryRequired }
    }
}
