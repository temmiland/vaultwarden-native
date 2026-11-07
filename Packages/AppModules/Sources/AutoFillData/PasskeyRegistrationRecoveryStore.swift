import AutoFillContract
import Foundation

/// A versioned, redacted-metadata journal in the explicitly injected App Group. Reserving before
/// HTTP prevents another process/invocation from silently retrying an unknown/confirmed mutation.
public struct PasskeyRegistrationRecoveryStore: PasskeyRegistrationRecoveryStoring {
    private struct Envelope: Codable {
        var schemaVersion = 1
        var records: [PasskeyRegistrationRecoveryRecord]
    }

    private let directoryURL: URL
    private let authorization: any AutoFillCacheMutationAuthorizing
    private var fileURL: URL { directoryURL.appendingPathComponent("autofill-passkey-recovery-v1.json") }

    public init(directoryURL: URL, authorization: any AutoFillCacheMutationAuthorizing) {
        self.directoryURL = directoryURL; self.authorization = authorization
    }

    public func records(requiring proof: ExtensionUnlockProof) throws -> [PasskeyRegistrationRecoveryRecord] {
        try authorization.withAuthorizedCacheMutation(requiring: proof) {
            try read().filter { $0.account == proof.account }
        }
    }

    public func reserve(_ record: PasskeyRegistrationRecoveryRecord, requiring proof: ExtensionUnlockProof) throws {
        try record.validate()
        guard record.account == proof.account, record.phase == .submitted, record.serverCipherID == nil else {
            throw PasskeyRegistrationRecoveryError.invalidRecord
        }
        guard record.originatingUnlockID == nil || record.originatingUnlockID == proof.unlockID else {
            throw PasskeyRegistrationRecoveryError.invalidRecord
        }
        try authorization.withAuthorizedCacheMutation(requiring: proof) {
            var records = try read()
            guard !records.contains(where: { $0.account == record.account }) else { throw PasskeyRegistrationRecoveryError.pendingMutation }
            guard !records.contains(where: { $0.mutationID == record.mutationID }) else { throw PasskeyRegistrationRecoveryError.invalidRecord }
            var boundRecord = record
            boundRecord.originatingUnlockID = proof.unlockID
            records.append(boundRecord)
            try write(records)
        }
    }

    public func confirm(_ mutationID: UUID, serverCipherID: String?, requiring proof: ExtensionUnlockProof) throws {
        try authorization.withAuthorizedCacheMutation(requiring: proof) {
            var records = try read()
            guard let index = records.firstIndex(where: { $0.mutationID == mutationID && $0.account == proof.account }) else {
                throw PasskeyRegistrationRecoveryError.missingMutation
            }
            guard records[index].phase == .submitted || records[index].serverCipherID == serverCipherID else {
                throw PasskeyRegistrationRecoveryError.invalidRecord
            }
            records[index].phase = .confirmed; records[index].serverCipherID = serverCipherID
            try records[index].validate()
            try write(records)
        }
    }

    public func remove(_ mutationIDs: Set<UUID>, requiring proof: ExtensionUnlockProof) throws {
        try authorization.withAuthorizedCacheMutation(requiring: proof) {
            let records = try read()
            let remaining = records.filter { $0.account != proof.account || !mutationIDs.contains($0.mutationID) }
            if remaining != records { try write(remaining) }
        }
    }

    public func abandonReviewedRecord(
        _ expected: PasskeyRegistrationRecoveryRecord,
        requiring proof: ExtensionUnlockProof
    ) throws -> Bool {
        try authorization.withAuthorizedCacheMutation(requiring: proof) {
            guard expected.account == proof.account else { throw PasskeyRegistrationRecoveryError.invalidRecord }
            var records = try read()
            guard let index = records.firstIndex(where: { $0.mutationID == expected.mutationID }), records[index] == expected else {
                throw PasskeyRegistrationRecoveryError.reviewChanged
            }
            guard let origin = expected.originatingUnlockID else { throw PasskeyRegistrationRecoveryError.legacyOriginUnknown }
            guard origin != proof.unlockID else { throw PasskeyRegistrationRecoveryError.freshUnlockRequired }
            records.remove(at: index)
            try write(records)
            return records.contains { $0.account == proof.account }
        }
    }

    private func read() throws -> [PasskeyRegistrationRecoveryRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: fileURL))
        guard envelope.schemaVersion == 1 else { throw PasskeyRegistrationRecoveryError.unsupportedSchema }
        var ids = Set<UUID>()
        for record in envelope.records {
            try record.validate()
            guard ids.insert(record.mutationID).inserted else { throw PasskeyRegistrationRecoveryError.invalidRecord }
        }
        return envelope.records
    }

    private func write(_ records: [PasskeyRegistrationRecoveryRecord]) throws {
        // The validated App Group exists already. Never create a fallback directory or delete
        // the journal on read/schema/write failure. Empty journals retain their version envelope.
        let data = try JSONEncoder().encode(Envelope(records: records))
        #if os(iOS)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        #else
            try data.write(to: fileURL, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: fileURL.path)
        let handle = try FileHandle(forWritingTo: fileURL)
        do { try handle.synchronize() }
        catch { try handle.close(); throw error }
        try handle.close()
    }
}
