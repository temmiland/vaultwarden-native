import AutoFillContract
import AutoFillData
import Data
import Foundation
import Testing

struct PasskeyRecoveryReviewFixture: Sendable {
    let directory: URL
    let authorization = RecoveryStoreAuthorization()
    let origin = PasskeyRecoveryJournalFixture.proof
    let fresh: ExtensionUnlockProof
    let access = PasskeyRecoveryAccessFixture()
    let record: PasskeyRegistrationRecoveryRecord
    var file: URL { directory.appendingPathComponent("autofill-passkey-recovery-v1.json") }
    var journal: PasskeyRegistrationRecoveryStore { PasskeyRegistrationRecoveryStore(
        directoryURL: directory,
        authorization: authorization
    ) }
    init(sameUnlock: Bool = false, legacy: Bool = false, confirmed: Bool = false) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("passkey-review-\(UUID())")
        fresh = sameUnlock ? origin : ExtensionUnlockProof(account: origin.account)
        record = PasskeyRecoveryJournalFixture.record()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try journal.reserve(record, requiring: origin)
        if confirmed { try journal.confirm(record.mutationID, serverCipherID: "saved", requiring: origin) }
        if legacy {
            var json = try #require(
                JSONSerialization.jsonObject(with: Foundation.Data(contentsOf: file)) as? [String: Any]
            )
            var records = try #require(json["records"] as? [[String: Any]])
            records[0].removeValue(forKey: "originatingUnlockID"); json["records"] = records
            try JSONSerialization.data(withJSONObject: json).write(to: file)
        }
        authorization.setProof(fresh)
    }

    func recovery() -> PasskeyRegistrationRecoveryReconciler {
        PasskeyRegistrationRecoveryReconciler(journal: journal, proof: fresh, checkAccess: { try access.check() })
    }

    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}
