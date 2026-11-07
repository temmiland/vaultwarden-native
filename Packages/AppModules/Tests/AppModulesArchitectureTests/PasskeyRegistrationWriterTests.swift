import AutoFillContract
import AutoFillData
import BitwardenSDKAdapter
import Domain
import Foundation
import Testing

@Suite
struct PasskeyRegistrationWriterTests {
    @Test
    func refreshRecoveryFailureReleasesOnlyTheUnsubmittedPasskeyReservation() async throws {
        let writer = PasskeyRegistrationWriter(), journal = PasskeyRecoveryJournalFixture(), access = PasskeyRecoveryAccessFixture(
        )
        await #expect(throws: SessionAuthorizationError.refreshRecoveryRequired) {
            _ = try await writer.save(
                record: PasskeyRecoveryJournalFixture.record(), proof: PasskeyRecoveryJournalFixture.proof,
                journal: journal, checkAccess: { try access.check() },
                write: { throw SessionAuthorizationError.refreshRecoveryRequired }, project: { access.project($0) }
            )
        }
        #expect(journal.entries.isEmpty && access.writeCount == 0 && access.projectionCount == 0)
        #expect(await writer.requiresRecovery() == false)
    }

    @Test
    func cancelledUIConsumerStillFinishesAsyncIdentityProjectionAndConfirmsResult() async throws {
        let writer = PasskeyRegistrationWriter(), journal = PasskeyRecoveryJournalFixture(), access = PasskeyRecoveryAccessFixture(
        )
        let gate = AuthOperationTestGate()
        let task = Task { try await writer.save(
            record: PasskeyRecoveryJournalFixture.record(),
            proof: PasskeyRecoveryJournalFixture.proof,
            journal: journal,
            checkAccess: { try access.check() },
            write: { access.write() },
            project: {
                access.project($0); await gate.pause(); #expect(!Task.isCancelled)
            }
        ) }
        await gate.waitUntilPaused(); task.cancel(); await gate.release()
        let receipt = try await task.value
        #expect(!receipt.needsProjectionRepair && access.writeCount == 1 && access.projectionCount == 1)
        #expect(await writer.confirmedReceipt() == receipt && journal.entries.first?.phase == .confirmed)
    }

    @Test(arguments: [false, true])
    func asyncIdentityFailurePreservesReceiptAndRecoveryMarkerWithoutRetryingWrite(_ failRemove: Bool) async throws {
        let fixture = try PasskeyProjectionCacheFixture(), identities = PasskeyIdentityProbe(
            failAdd: true,
            failRemove: failRemove
        )
        defer { try? fixture.cleanup() }
        let writer = PasskeyRegistrationWriter(), journal = PasskeyRecoveryJournalFixture(), access = PasskeyRecoveryAccessFixture(
        )
        let projection = fixture.projection(identities: identities)
        let receipt = try await writer.save(
            record: PasskeyRecoveryJournalFixture.record(),
            proof: fixture.proof,
            journal: journal,
            checkAccess: { try fixture.authorization.check() },
            write: { access.write() },
            project: {
                try await projection.project(
                    $0,
                    credentialID: Foundation.Data([1]),
                    relyingPartyIdentifier: "example.com",
                    makeIdentity: { _ in PasskeyProjectionCacheFixture.identity() }
                )
            }
        )
        #expect(receipt.needsProjectionRepair && access.writeCount == 1 && journal.entries.first?.phase == .confirmed)
        #expect(await identities.removed.count == 1)
        await #expect(throws: PasskeyRegistrationError.recoveryRequired) { try await writer.prepareAttempt() }
    }

    @Test
    func reservePrecedesWriteAndConfirmedMutationProjectsOnce() async throws {
        let writer = PasskeyRegistrationWriter(), journal = PasskeyRecoveryJournalFixture(), access = PasskeyRecoveryAccessFixture(
        )
        let record = PasskeyRecoveryJournalFixture.record()
        let receipt = try await writer.save(
            record: record,
            proof: PasskeyRecoveryJournalFixture.proof,
            journal: journal,
            checkAccess: { try access.check() },
            write: {
                #expect(journal.entries == [record]); return access.write()
            },
            project: { access.project($0) }
        )
        #expect(!receipt.needsProjectionRepair && receipt.mutationID == record.mutationID)
        #expect(
            receipt.credentialID == record.credentialID && String(describing: receipt) == "PasskeyRegistrationReceipt(<redacted>)"
        )
        #expect(await writer.confirmedReceipt() == receipt)
        #expect(access.writeCount == 1 && access.projectionCount == 1)
        #expect(journal.entries.first?.phase == .confirmed && journal.entries.first?.serverCipherID == "saved")
        #expect(await writer.requiresRecovery())
        #expect(await writer.lastFailure() == nil)
        await #expect(throws: PasskeyRegistrationError.recoveryRequired) { try await writer.prepareAttempt() }
        await #expect(throws: PasskeyRegistrationError.recoveryRequired) {
            _ = try await writer.save(
                record: record,
                proof: PasskeyRecoveryJournalFixture.proof,
                journal: journal,
                checkAccess: { try access.check() },
                write: { access.write() },
                project: { access.project($0) }
            )
        }
        #expect(access.writeCount == 1)
    }

    @Test(arguments: ["projection", "confirm"])
    func localFailureRetainsServerSuccessAndDurableRecovery(_ failure: String) async throws {
        let writer = PasskeyRegistrationWriter(), journal = PasskeyRecoveryJournalFixture(), access = PasskeyRecoveryAccessFixture(
        )
        if failure == "confirm" { journal.fail("confirm") }
        let receipt = try await writer.save(
            record: PasskeyRecoveryJournalFixture.record(),
            proof: PasskeyRecoveryJournalFixture.proof,
            journal: journal,
            checkAccess: { try access.check() },
            write: { access.write() },
            project: {
                if failure == "projection" { throw PasskeyRecoveryFixtureError.storage }; access.project(
                    $0
                )
            }
        )
        #expect(receipt.needsProjectionRepair && access.writeCount == 1 && journal.entries.count == 1)
    }

    @Test
    func cancelledUIConsumerDoesNotSkipConfirmedProjection() async throws {
        let writer = PasskeyRegistrationWriter(), journal = PasskeyRecoveryJournalFixture(), access = PasskeyRecoveryAccessFixture(
        )
        let gate = AuthOperationTestGate()
        let task = Task { try await writer.save(
            record: PasskeyRecoveryJournalFixture.record(),
            proof: PasskeyRecoveryJournalFixture.proof,
            journal: journal,
            checkAccess: { try access.check() },
            write: { await gate.pause(); return access.write() },
            project: { access.project($0) }
        ) }
        await gate.waitUntilPaused(); task.cancel(); await gate.release()
        #expect(try await !task.value.needsProjectionRepair)
        #expect(access.projectionCount == 1 && journal.entries.first?.phase == .confirmed)
    }

    @Test
    func runtimeRevocationAfterWriteDeniesProjectionButRetainsTheMarker() async throws {
        let writer = PasskeyRegistrationWriter(), journal = PasskeyRecoveryJournalFixture(), access = PasskeyRecoveryAccessFixture(
        )
        let gate = AuthOperationTestGate()
        let task = Task { try await writer.save(
            record: PasskeyRecoveryJournalFixture.record(),
            proof: PasskeyRecoveryJournalFixture.proof,
            journal: journal,
            checkAccess: { try access.check() },
            write: { await gate.pause(); return access.write() },
            project: { access.project($0) }
        ) }
        await gate.waitUntilPaused(); access.revoke(); await gate.release()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(access.writeCount == 1 && access.projectionCount == 0 && journal.entries.count == 1)
    }

    @Test(arguments: [SDKPasskeyWriteError.notSubmitted, .rejected])
    func definiteRejectionReleasesOnlyItsOwnMarker(_ failure: SDKPasskeyWriteError) async throws {
        let writer = PasskeyRegistrationWriter(), journal = PasskeyRecoveryJournalFixture(), access = PasskeyRecoveryAccessFixture(
        )
        await #expect(throws: PasskeyRegistrationError.writeRejected) {
            _ = try await writer.save(
                record: PasskeyRecoveryJournalFixture.record(),
                proof: PasskeyRecoveryJournalFixture.proof,
                journal: journal,
                checkAccess: { try access.check() },
                write: { throw failure },
                project: { access.project($0) }
            )
        }
        #expect(journal.entries.isEmpty && access.projectionCount == 0)
        #expect(await writer.confirmedReceipt() == nil)
        #expect(await writer.lastFailure() == .writeRejected)
        try await writer.prepareAttempt()
        #expect(await writer.lastFailure() == nil)
        _ = try await writer.save(
            record: PasskeyRecoveryJournalFixture.record(),
            proof: PasskeyRecoveryJournalFixture.proof,
            journal: journal,
            checkAccess: { try access.check() },
            write: { access.write() },
            project: { access.project($0) }
        )
        #expect(access.writeCount == 1)
    }

    @Test(arguments: [SDKPasskeyWriteError.outcomeUnknown, .confirmedButUnreadable])
    func ambiguousOrUnreadableSuccessRemainsBlockedAcrossWriterRecreation(_ failure: SDKPasskeyWriteError) async throws {
        let journal = PasskeyRecoveryJournalFixture(), access = PasskeyRecoveryAccessFixture()
        let writer = PasskeyRegistrationWriter()
        let expected: PasskeyRegistrationError = failure == .outcomeUnknown ? .outcomeUnknown : .committedNeedsRepair
        await #expect(throws: expected) {
            _ = try await writer.save(
                record: PasskeyRecoveryJournalFixture.record(),
                proof: PasskeyRecoveryJournalFixture.proof,
                journal: journal,
                checkAccess: { try access.check() },
                write: { throw failure },
                project: { access.project($0) }
            )
        }
        #expect(journal.entries.count == 1)
        #expect(await writer.lastFailure() == expected)
        #expect(await writer.confirmedReceipt() == nil)
        await #expect(throws: PasskeyRegistrationError.recoveryRequired) {
            _ = try await PasskeyRegistrationWriter().save(
                record: PasskeyRecoveryJournalFixture.record(),
                proof: PasskeyRecoveryJournalFixture.proof,
                journal: journal,
                checkAccess: { try access.check() },
                write: { access.write() },
                project: { access.project($0) }
            )
        }
        #expect(access.writeCount == 0)
    }

    @Test(arguments: ["reserve", "remove"])
    func storageFailureCannotReachAnUnguardedWriteOrEnableRetry(_ failure: String) async throws {
        let writer = PasskeyRegistrationWriter(), journal = PasskeyRecoveryJournalFixture(), access = PasskeyRecoveryAccessFixture(
        )
        journal.fail(failure)
        await #expect(throws: (any Error).self) {
            _ = try await writer.save(
                record: PasskeyRecoveryJournalFixture.record(),
                proof: PasskeyRecoveryJournalFixture.proof,
                journal: journal,
                checkAccess: { try access.check() },
                write: { throw SDKPasskeyWriteError.rejected },
                project: { access.project($0) }
            )
        }
        #expect(access.writeCount == 0 && access.projectionCount == 0)
        if failure == "remove" { #expect(journal.entries.count == 1) }
    }

    @Test
    func parallelCallbackCannotSubmitAnotherWrite() async throws {
        let writer = PasskeyRegistrationWriter(), journal = PasskeyRecoveryJournalFixture(), access = PasskeyRecoveryAccessFixture(
        )
        let gate = AuthOperationTestGate()
        let task = Task { try await writer.save(
            record: PasskeyRecoveryJournalFixture.record(),
            proof: PasskeyRecoveryJournalFixture.proof,
            journal: journal,
            checkAccess: { try access.check() },
            write: { await gate.pause(); return access.write() },
            project: { access.project($0) }
        ) }
        await gate.waitUntilPaused()
        await #expect(throws: AutoFillOperationError.operationInProgress) {
            _ = try await writer.save(
                record: PasskeyRecoveryJournalFixture.record(),
                proof: PasskeyRecoveryJournalFixture.proof,
                journal: journal,
                checkAccess: { try access.check() },
                write: { access.write() },
                project: { access.project($0) }
            )
        }
        await gate.release(); _ = try await task.value
        #expect(access.writeCount == 1)
    }

    @Test(arguments: ["missing-id", "foreign-target", "protected"])
    func unusableConfirmedResponseCannotProjectAnotherItemOrReopenTheWriter(_ failure: String) async throws {
        let writer = PasskeyRegistrationWriter(), journal = PasskeyRecoveryJournalFixture(), access = PasskeyRecoveryAccessFixture(
        )
        var response = AutoFillQuerySourceFixture.dto("saved")
        if failure == "missing-id" { response.id = nil }
        if failure == "protected" { response.reprompt = 1 }
        let result = response
        await #expect(throws: PasskeyRegistrationError.committedNeedsRepair) {
            _ = try await writer.save(
                record: PasskeyRecoveryJournalFixture.record(target: failure == "foreign-target" ? "other" : nil),
                proof: PasskeyRecoveryJournalFixture.proof,
                journal: journal,
                checkAccess: { try access.check() },
                write: { result },
                project: { access.project($0) }
            )
        }
        #expect(access.projectionCount == 0 && journal.entries.count == 1)
        #expect(await writer.confirmedReceipt() == nil)
    }

    @Test
    func alreadyCancelledSubmissionCannotReserveOrSend() async throws {
        let writer = PasskeyRegistrationWriter(), journal = PasskeyRecoveryJournalFixture(), access = PasskeyRecoveryAccessFixture(
        )
        let gate = AuthOperationTestGate()
        let task = Task {
            await gate.pause()
            return try await writer.save(
                record: PasskeyRecoveryJournalFixture.record(),
                proof: PasskeyRecoveryJournalFixture.proof,
                journal: journal,
                checkAccess: { try access.check() },
                write: { access.write() },
                project: { access.project($0) }
            )
        }
        await gate.waitUntilPaused(); task.cancel(); await gate.release()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(journal.entries.isEmpty && access.writeCount == 0)
    }
}
