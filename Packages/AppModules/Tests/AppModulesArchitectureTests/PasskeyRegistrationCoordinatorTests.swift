import AutoFillData
import BitwardenSDKAdapter
import Domain
import Foundation
import Testing

@Suite
struct PasskeyRegistrationCoordinatorTests {
    @Test
    func cryptoOutputWithoutThisInvocationsReceiptCannotComplete() async throws {
        let coordinator = PasskeyRegistrationCoordinator(writer: PasskeyRegistrationWriter())
        await #expect(throws: AutoFillOperationError.saveFailed) {
            try await coordinator.register(checkAccess: {}, operation: { Self.result() })
        }
    }

    @Test(arguments: ["valid", "id", "attestation"])
    func completionIsBoundToConfirmedCredentialAndNonemptyAttestation(_ scenario: String) async throws {
        let writer = PasskeyRegistrationWriter(), source = RegistrationSourceFixture(), coordinator = PasskeyRegistrationCoordinator(
            writer: writer
        )
        let operation: @Sendable () async throws -> SDKAutoFillRegistrationResult = {
            _ = try await source.persistence(writer: writer).save(source.encrypted)
            return Self.result(
                id: scenario == "id" ? Foundation.Data([99]) : Foundation.Data([2]),
                attestation: scenario == "attestation" ? Foundation.Data() : Foundation.Data([3])
            )
        }
        if scenario == "valid" {
            let result = try await coordinator.register(checkAccess: { try source.checkAccess() }, operation: operation)
            #expect(
                result.credentialID == Foundation.Data([2]) && String(describing: result) == "SDKAutoFillRegistrationResult(<redacted>)"
            )
        } else {
            await #expect(throws: PasskeyRegistrationError.committedNeedsRepair) {
                try await coordinator.register(checkAccess: { try source.checkAccess() }, operation: operation)
            }
        }
        #expect(source.access.writeCount == 1 && source.journal.entries.count == 1)
        await #expect(throws: PasskeyRegistrationError.recoveryRequired) {
            try await coordinator.register(
                checkAccess: {},
                operation: { Issue.record("Terminal attempt cannot invoke SDK again"); return Self.result() }
            )
        }
    }

    @Test(arguments: [SDKPasskeyWriteError.rejected, .outcomeUnknown, .confirmedButUnreadable])
    func wrappedFFICallbackFailureKeepsCorrectMutationClassification(_ error: SDKPasskeyWriteError) async throws {
        let writer = PasskeyRegistrationWriter(), coordinator = PasskeyRegistrationCoordinator(writer: writer)
        let journal = PasskeyRecoveryJournalFixture()
        let expected: PasskeyRegistrationError = error == .rejected ? .writeRejected : (
            error == .outcomeUnknown ? .outcomeUnknown : .committedNeedsRepair
        )
        await #expect(throws: expected) {
            try await coordinator.register(checkAccess: {}, operation: {
                do { _ = try await writer.save(
                    record: PasskeyRecoveryJournalFixture.record(),
                    proof: PasskeyRecoveryJournalFixture.proof,
                    journal: journal,
                    checkAccess: {},
                    write: { throw error },
                    project: { _ in Issue.record("Unconfirmed write must not project") }
                ) } catch { throw PasskeyRecoveryFixtureError.write } // SDK/FFI erased the callback error type
                return Self.result()
            })
        }
        #expect(journal.entries.count == (error == .rejected ? 0 : 1))
    }

    @Test
    func parallelRegistrationIsRejectedBeforeAnotherCryptoOperation() async throws {
        let gate = AuthOperationTestGate(), coordinator = PasskeyRegistrationCoordinator(
            writer: PasskeyRegistrationWriter()
        )
        let task = Task { try await coordinator.register(
            checkAccess: {},
            operation: { await gate.pause(); throw PasskeyRecoveryFixtureError.write }
        ) }
        await gate.waitUntilPaused()
        await #expect(throws: AutoFillOperationError.operationInProgress) {
            try await coordinator.register(
                checkAccess: {},
                operation: { Issue.record("Busy operation must not reach crypto"); return Self.result() }
            )
        }
        await gate.release()
        await #expect(throws: PasskeyRecoveryFixtureError.write) { try await task.value }
        // Pre-write failure releases the whole-registration gate, not a permanent busy state.
        await #expect(throws: AutoFillOperationError.saveFailed) { try await coordinator.register(
            checkAccess: {},
            operation: { Self.result() }
        ) }
    }

    @Test(arguments: ["lock", "cancel", "ffi-after-confirm", "verification-after-confirm"])
    func postCommitRevocationOrCancellationCannotPublishButKeepsRecovery(_ scenario: String) async throws {
        let writer = PasskeyRegistrationWriter(), source = RegistrationSourceFixture(), coordinator = PasskeyRegistrationCoordinator(
            writer: writer
        )
        let gate = AuthOperationTestGate()
        let task = Task { try await coordinator.register(checkAccess: { try source.checkAccess() }, operation: {
            _ = try await source.persistence(writer: writer).save(source.encrypted)
            await gate.pause()
            if scenario == "ffi-after-confirm" { throw PasskeyRecoveryFixtureError.write }
            if scenario == "verification-after-confirm" { throw PasskeyUserVerificationError.userCanceled }
            return Self.result()
        }) }
        await gate.waitUntilPaused()
        if scenario == "lock" { source.access.revoke() }
        if scenario == "cancel" { task.cancel() }
        await gate.release()
        if scenario == "ffi-after-confirm" || scenario == "verification-after-confirm" {
            await #expect(throws: PasskeyRegistrationError.committedNeedsRepair) { try await task.value }
        } else { await #expect(throws: CancellationError.self) { try await task.value } }
        #expect(
            source.access.writeCount == 1 && source.access.projectionCount == 1 && source.journal.entries.first?.phase == .confirmed
        )
    }

    @Test
    func cancelledSubmissionCannotStartSDKOperation() async throws {
        let gate = AuthOperationTestGate(), coordinator = PasskeyRegistrationCoordinator(
            writer: PasskeyRegistrationWriter()
        )
        let task = Task { await gate.pause(); return try await coordinator.register(
            checkAccess: {},
            operation: { Issue.record("Cancelled attempt reached SDK"); return Self.result() }
        ) }
        await gate.waitUntilPaused(); task.cancel(); await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    private static func result(
        id: Foundation.Data = Foundation.Data([2]),
        attestation: Foundation.Data = Foundation.Data([3])
    ) -> SDKAutoFillRegistrationResult {
        SDKAutoFillRegistrationResult(credentialID: id, attestationObject: attestation)
    }
}
