import AutoFillContract
import AutoFillData
import BitwardenSdk
import BitwardenSDKAdapter
import Foundation
import Testing

@Suite
struct PasskeyRegistrationPersistenceTests {
    @Test(arguments: [false, true])
    func reserveUsesExactAddedBytesAndOriginBeforeCreateOrUpdateHTTP(_ creating: Bool) async throws {
        let source = RegistrationSourceFixture(creating: creating), writer = PasskeyRegistrationWriter()
        let receipt = try await source.persistence(writer: writer).save(source.encrypted)
        let record = try #require(source.journal.entries.first)
        #expect(record.credentialID == Foundation.Data([2]) && record.relyingPartyIdentifier == "example.com")
        #expect(record.originatingUnlockID == PasskeyRecoveryJournalFixture.proof.unlockID)
        #expect(record.targetCipherID == (creating ? nil : "cipher-1") && record.phase == .confirmed)
        #expect(receipt.credentialID == record.credentialID && !receipt.needsProjectionRepair)
        #expect(source.access.writeCount == 1 && source.access.projectionCount == 1)
    }

    @Test(arguments: ["lock", "cache", "cancel"])
    func staleOrCancelledDecryptCannotReserveOrSubmit(_ scenario: String) async throws {
        let source = RegistrationSourceFixture(decryptGate: AuthOperationTestGate())
        let persistence = source.persistence(writer: PasskeyRegistrationWriter())
        let task = Task { try await persistence.save(source.encrypted) }
        guard let decryptGate = source.decryptGate else { Issue.record("Missing gate"); return }
        await decryptGate.waitUntilPaused()
        if scenario == "lock" { source.access.revoke() }
        else if scenario == "cache" { source.advanceCache() }
        else { task.cancel() }
        await decryptGate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(source.journal.entries.isEmpty && source.access.writeCount == 0 && source.access.projectionCount == 0)
    }

    @Test(arguments: ["unchanged", "foreign-rp", "target", "readonly"])
    func invalidSDKMutationCannotJournalOrWrite(_ scenario: String) async throws {
        let source = RegistrationSourceFixture(scenario: scenario)
        await #expect(throws: (any Error).self) { try await source.persistence(writer: PasskeyRegistrationWriter()).save(
            source.encrypted
        ) }
        #expect(source.journal.entries.isEmpty && source.access.writeCount == 0)
    }

    @Test
    func projectionFailureKeepsConfirmedReceiptAndBlocksSecondWrite() async throws {
        let source = RegistrationSourceFixture(failProjection: true), writer = PasskeyRegistrationWriter()
        let persistence = source.persistence(writer: writer)
        #expect(try await persistence.save(source.encrypted).needsProjectionRepair)
        #expect(source.journal.entries.first?.phase == .confirmed)
        await #expect(throws: PasskeyRegistrationError.recoveryRequired) { try await persistence.save(source.encrypted) }
        #expect(source.access.writeCount == 1)
    }

    @Test
    func cancelledHTTPConsumerStillProjectsInMutationOwnedTask() async throws {
        let source = RegistrationSourceFixture(writeGate: AuthOperationTestGate()), writer = PasskeyRegistrationWriter()
        let persistence = source.persistence(writer: writer)
        let task = Task { try await persistence.save(source.encrypted) }
        guard let gate = source.writeGate else { Issue.record("Missing gate"); return }
        await gate.waitUntilPaused(); task.cancel(); await gate.release()
        #expect(try await !task.value.needsProjectionRepair)
        #expect(source.access.writeCount == 1 && source.access.projectionCount == 1)
        #expect(await writer.confirmedReceipt() != nil && source.journal.entries.first?.phase == .confirmed)
    }
}

final class RegistrationSourceFixture: PasskeyRegistrationSource, @unchecked Sendable {
    private let lock = NSLock()
    private var cacheAdvanced = false
    let access = PasskeyRecoveryAccessFixture(), journal = PasskeyRecoveryJournalFixture()
    let target: SDKAutoFillCredentialView, updated: SDKAutoFillCredentialView, encrypted: SDKAutoFillEncryptedCipher
    let previous: [SDKAutoFillPasskeyMetadata], current: [SDKAutoFillPasskeyMetadata]
    let decryptGate: AuthOperationTestGate?, writeGate: AuthOperationTestGate?
    let failProjection: Bool

    init(
        creating: Bool = false,
        scenario: String = "valid",
        decryptGate: AuthOperationTestGate? = nil,
        writeGate: AuthOperationTestGate? = nil,
        failProjection: Bool = false
    ) {
        let id: String? = creating ? nil : "cipher-1"
        target = SDKAutoFillCredentialView(legacyView: .fixture(id: id, name: "before", edit: scenario != "readonly"))
        encrypted = SDKAutoFillEncryptedCipher(legacyCipher: .fixture(id: id), encryptedFor: "user-1")
        updated = SDKAutoFillCredentialView(legacyView: .fixture(
            id: scenario == "target" ? "other" : id,
            name: "after",
            login: AutoFillQuerySourceFixture.view(hasPasskeys: true).login
        ))
        let old = SDKPasskeyRegistrationContractTests.metadata(id: Foundation.Data([1]), cipher: id ?? "")
        previous = creating ? [] : [old]
        current = (creating ? [] : [old]) + (
            scenario == "unchanged" ? [] : [SDKPasskeyRegistrationContractTests.metadata(
                id: Foundation.Data([2]), cipher: id ?? "",
                rp: scenario == "foreign-rp" ? "other.example.com" : "example.com"
            )]
        )
        self.decryptGate = decryptGate; self.writeGate = writeGate; self.failProjection = failProjection
    }

    func advanceCache() { lock.withLock { cacheAdvanced = true } }
    func checkAccess() throws { try access.check() }
    func requireOriginalAccess(to target: SDKAutoFillCredentialView) throws {
        try Task.checkCancellation(); try access.check()
        if lock.withLock({ cacheAdvanced }) { throw CancellationError() }
    }

    func metadata(in view: SDKAutoFillCredentialView) throws -> [SDKAutoFillPasskeyMetadata] {
        try access.check(); return view.name == "before" ? previous : current
    }

    func decrypt(_ cipher: SDKAutoFillEncryptedCipher) async throws -> SDKAutoFillCredentialView {
        await decryptGate?.pause(); return updated
    }

    func save(_ cipher: SDKAutoFillEncryptedCipher) async throws -> CipherResponseDTO {
        #expect(journal.entries.count == 1 && journal.entries.first?.phase == .submitted)
        await writeGate?.pause()
        #expect(!Task.isCancelled)
        _ = access.write()
        return AutoFillQuerySourceFixture.dto(target.id ?? "created")
    }

    func persistence(writer: PasskeyRegistrationWriter) -> PasskeyRegistrationPersistence {
        PasskeyRegistrationPersistence(
            source: self,
            target: target,
            relyingPartyIdentifier: "example.com",
            proof: PasskeyRecoveryJournalFixture.proof,
            writer: writer,
            journal: journal,
            project: { dto, id, rp in
                #expect(
                    !Task.isCancelled && id == Foundation.Data([2]) && rp == "example.com"
                )
                if self.failProjection { throw PasskeyRecoveryFixtureError.storage }
                self.access.project(dto); self.advanceCache()
            }
        )
    }
}
