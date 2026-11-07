import AutoFillContract
import AutoFillData
import Foundation
import Testing

@Suite
struct PasskeyRegistrationRecoveryStoreTests {
    @Test
    func reservationBindsTheCurrentUnlockAndDoesNotAcceptAForgedOrigin() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        var record = PasskeyRecoveryJournalFixture.record()
        record.originatingUnlockID = UUID()
        #expect(throws: PasskeyRegistrationRecoveryError.invalidRecord) { try fixture.store.reserve(
            record,
            requiring: fixture.proof
        ) }
        #expect(try fixture.store.records(requiring: fixture.proof).isEmpty)
        record.originatingUnlockID = nil
        try fixture.store.reserve(record, requiring: fixture.proof)
        #expect(try fixture.store.records(requiring: fixture.proof).first?.originatingUnlockID == fixture.proof.unlockID)
    }

    @Test(arguments: [false, true])
    func abandonmentRequiresAFreshUnlockAndExactEntireRecord(_ confirmed: Bool) throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let record = PasskeyRecoveryJournalFixture.record()
        try fixture.store.reserve(record, requiring: fixture.proof)
        if confirmed { try fixture.store.confirm(record.mutationID, serverCipherID: "saved", requiring: fixture.proof) }
        let reviewed = try #require(try fixture.store.records(requiring: fixture.proof).first)
        #expect(throws: PasskeyRegistrationRecoveryError.freshUnlockRequired) {
            try fixture.store.abandonReviewedRecord(reviewed, requiring: fixture.proof)
        }
        let fresh = ExtensionUnlockProof(account: fixture.proof.account)
        fixture.authorization.setProof(fresh)
        var changed = reviewed
        changed.originatingUnlockID = UUID()
        #expect(throws: PasskeyRegistrationRecoveryError.reviewChanged) {
            try fixture.store.abandonReviewedRecord(changed, requiring: fresh)
        }
        #expect(try fixture.store.records(requiring: fresh) == [reviewed])
        #expect(try !fixture.store.abandonReviewedRecord(reviewed, requiring: fresh))
        #expect(try fixture.store.records(requiring: fresh).isEmpty)
        #expect(throws: PasskeyRegistrationRecoveryError.reviewChanged) {
            try fixture.store.abandonReviewedRecord(reviewed, requiring: fresh)
        }
    }

    @Test
    func oldJournalWithoutOriginStillReadsButCannotBeManuallyAbandoned() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        try fixture.store.reserve(PasskeyRecoveryJournalFixture.record(), requiring: fixture.proof)
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.file)) as? [String: Any])
        var records = try #require(json["records"] as? [[String: Any]])
        records[0].removeValue(forKey: "originatingUnlockID"); json["records"] = records
        try JSONSerialization.data(withJSONObject: json).write(to: fixture.file)
        let old = try #require(try fixture.store.records(requiring: fixture.proof).first)
        #expect(old.originatingUnlockID == nil)
        let fresh = ExtensionUnlockProof(account: fixture.proof.account); fixture.authorization.setProof(fresh)
        let before = try Data(contentsOf: fixture.file)
        #expect(throws: PasskeyRegistrationRecoveryError.legacyOriginUnknown) {
            try fixture.store.abandonReviewedRecord(old, requiring: fresh)
        }
        #expect(try Data(contentsOf: fixture.file) == before)
    }

    private struct Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "passkey-journal-\(UUID().uuidString)"
        )
        let proof = PasskeyRecoveryJournalFixture.proof
        var file: URL { directory.appendingPathComponent("autofill-passkey-recovery-v1.json") }
        let authorization = RecoveryStoreAuthorization()
        var store: PasskeyRegistrationRecoveryStore { PasskeyRegistrationRecoveryStore(
            directoryURL: directory,
            authorization: authorization
        ) }
        init() throws { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        func cleanup() { try? FileManager.default.removeItem(at: directory) }
    }

    @Test
    func reservationSurvivesRecreationHasRestrictedPermissionsAndContainsNoSecrets() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let record = PasskeyRecoveryJournalFixture.record()
        try fixture.store.reserve(record, requiring: fixture.proof)
        #expect(try fixture.store.records(requiring: fixture.proof) == [record])
        #expect(throws: PasskeyRegistrationRecoveryError.pendingMutation) {
            try fixture.store.reserve(PasskeyRecoveryJournalFixture.record(), requiring: fixture.proof)
        }
        try fixture.store.confirm(record.mutationID, serverCipherID: "saved", requiring: fixture.proof)
        #expect(try fixture.store.records(requiring: fixture.proof).first?.phase == .confirmed)
        #expect(
            (try FileManager.default.attributesOfItem(atPath: fixture.file.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600
        )
        #expect(String(describing: record) == "PasskeyRegistrationRecoveryRecord(<redacted>)")
        let fields = Set(Mirror(reflecting: record).children.compactMap(\.label))
        #expect(
            fields == [
                "mutationID",
                "account",
                "credentialID",
                "relyingPartyIdentifier",
                "targetCipherID",
                "serverCipherID",
                "phase",
                "originatingUnlockID",
            ]
        )
        try fixture.store.remove([record.mutationID], requiring: fixture.proof)
        #expect(try fixture.store.records(requiring: fixture.proof).isEmpty)
    }

    @Test(arguments: ["future", "corrupt", "duplicate", "invalid"])
    func unreadableOrFutureJournalIsNeverResetOrOverwritten(_ failure: String) throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let record = PasskeyRecoveryJournalFixture.record()
        try fixture.store.reserve(record, requiring: fixture.proof)
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.file)) as? [String: Any])
        if failure == "future" { json["schemaVersion"] = 2 }
        if failure == "duplicate", let records = json["records"] as? [[String: Any]] { json["records"] = records + records }
        if failure == "invalid", var records = json["records"] as? [[String: Any]] { records[0]["relyingPartyIdentifier"] = ""; json[
            "records"
        ] = records }
        let bytes = failure == "corrupt" ? Data("broken".utf8) : try JSONSerialization.data(withJSONObject: json)
        try bytes.write(to: fixture.file)
        #expect(throws: (any Error).self) { _ = try fixture.store.records(requiring: fixture.proof) }
        #expect(throws: (any Error).self) { try fixture.store.reserve(
            PasskeyRecoveryJournalFixture.record(),
            requiring: fixture.proof
        ) }
        #expect(try Data(contentsOf: fixture.file) == bytes)
    }

    @Test
    func staleProofCannotReserveConfirmOrRemoveAnotherUnlocksJournal() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let record = PasskeyRecoveryJournalFixture.record()
        try fixture.store.reserve(record, requiring: fixture.proof)
        let original = try Data(contentsOf: fixture.file)
        fixture.authorization.setProof(ExtensionUnlockProof(account: fixture.proof.account))
        #expect(throws: CancellationError.self) { try fixture.store.confirm(
            record.mutationID,
            serverCipherID: "saved",
            requiring: fixture.proof
        ) }
        #expect(throws: CancellationError.self) { try fixture.store.remove([record.mutationID], requiring: fixture.proof) }
        #expect(throws: CancellationError.self) { try fixture.store.reserve(record, requiring: fixture.proof) }
        #expect(try Data(contentsOf: fixture.file) == original)
    }

    @Test
    func accountsOnDifferentServersAreSeparateAndRemovalPreservesForeignRecords() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let first = PasskeyRecoveryJournalFixture.record()
        try fixture.store.reserve(first, requiring: fixture.proof)
        let foreign = ExtensionUnlockProof(account: AutoFillAccountIdentity(
            userID: fixture.proof.account.userID,
            serverBaseURL: URL(string: "https://another.example.com")!
        ))
        fixture.authorization.setProof(foreign)
        let second = PasskeyRegistrationRecoveryRecord(
            account: foreign.account,
            credentialID: Data([2]),
            relyingPartyIdentifier: "example.com",
            targetCipherID: nil
        )
        try fixture.store.reserve(second, requiring: foreign)
        try fixture.store.remove([first.mutationID, second.mutationID], requiring: foreign)
        fixture.authorization.setProof(fixture.proof)
        #expect(try fixture.store.records(requiring: fixture.proof) == [first])
    }

    @Test
    func parallelReservationsAcrossStoreInstancesPermitOnlyOneWriter() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let wins = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for _ in 0 ..< 5 {
                group.addTask {
                    do { try fixture.store.reserve(PasskeyRecoveryJournalFixture.record(), requiring: fixture.proof); return true }
                    catch { return false }
                }
            }
            var total = 0; for await won in group { if won { total += 1 } }; return total
        }
        let records = try fixture.store.records(requiring: fixture.proof)
        #expect(wins == 1 && records.count == 1)
    }

    @Test
    func missingContainerCannotCreateAFallbackJournal() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let missing = fixture.directory.appendingPathComponent("missing", isDirectory: true)
        let store = PasskeyRegistrationRecoveryStore(directoryURL: missing, authorization: fixture.authorization)
        #expect(throws: (any Error).self) { try store.reserve(
            PasskeyRecoveryJournalFixture.record(),
            requiring: fixture.proof
        ) }
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }

    @Test
    func confirmedExistingTargetCannotChangeItsCipherID() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let record = PasskeyRecoveryJournalFixture.record(target: "existing")
        try fixture.store.reserve(record, requiring: fixture.proof)
        let original = try Data(contentsOf: fixture.file)
        #expect(throws: PasskeyRegistrationRecoveryError.invalidRecord) {
            try fixture.store.confirm(record.mutationID, serverCipherID: "foreign", requiring: fixture.proof)
        }
        #expect(try Data(contentsOf: fixture.file) == original)
    }
}

final class RecoveryStoreAuthorization: AutoFillCacheMutationAuthorizing, @unchecked Sendable {
    private let lock = NSLock()
    private var proof = PasskeyRecoveryJournalFixture.proof
    func setProof(_ value: ExtensionUnlockProof) { lock.withLock { proof = value } }
    func withAuthorizedCacheMutation<Value>(requiring expected: ExtensionUnlockProof, _ operation: () throws -> Value) throws -> Value {
        try lock.withLock { guard expected == proof else { throw CancellationError() }; return try operation() }
    }
}
