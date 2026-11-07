import AutoFillContract
import AutoFillData
import Foundation
import Testing

@Suite
struct AutoFillCacheCommitReceiptTests {
    @Test
    func receiptProvesTheExactPostWriteEncryptedRecordAndBothRevisionFences() throws {
        let fixture = try PasskeyProjectionCacheFixture()
        defer { try? fixture.cleanup() }
        let receipt = try fixture.store.upsertReturningReceipt(
            AutoFillQuerySourceFixture.dto("saved"),
            for: fixture.proof.account,
            requiringProof: fixture.proof,
            cacheRevision: fixture.originalRevision
        )
        try fixture.store.requireCurrent(receipt, requiring: fixture.proof)
        #expect(receipt.revision != fixture.originalRevision && receipt.projectionRevision == 18)
        #expect(String(describing: receipt) == "AutoFillCacheCommitReceipt(<redacted>)")
    }

    @Test(arguments: ["uuid", "revision", "encrypted-record", "duplicate", "missing", "owner", "proof", "lock"])
    func alteredCacheOrGrantInvalidatesReceipt(_ mutation: String) throws {
        let fixture = try PasskeyProjectionCacheFixture()
        defer { try? fixture.cleanup() }
        let receipt = try fixture.store.upsertReturningReceipt(
            AutoFillQuerySourceFixture.dto("saved"),
            for: fixture.proof.account,
            requiringProof: fixture.proof,
            cacheRevision: fixture.originalRevision
        )
        try fixture.edit { cache in
            switch mutation {
            case "uuid": cache.revision = UUID()
            case "revision": cache.projectionRevision = 19
            case "encrypted-record": cache.ciphers[1].name = "different-encrypted-name"
            case "duplicate": cache.ciphers.append(cache.ciphers[1])
            case "missing": cache.ciphers.removeLast()
            case "owner": cache.owner = AutoFillAccountIdentity(
                    userID: "other",
                    serverBaseURL: fixture.proof.account.serverBaseURL
                )
            default: break
            }
        }
        if mutation == "lock" { fixture.authorization.revoke() }
        let proof = mutation == "proof" ? ExtensionUnlockProof(account: fixture.proof.account) : fixture.proof
        #expect(throws: (any Error).self) { try fixture.store.requireCurrent(receipt, requiring: proof) }
    }

    @Test(arguments: ["missing-id", "protected"])
    func ineligibleRegistrationResponseCannotCommitOrYieldReceipt(_ failure: String) throws {
        let fixture = try PasskeyProjectionCacheFixture()
        defer { try? fixture.cleanup() }
        var cipher = AutoFillQuerySourceFixture.dto("saved")
        if failure == "missing-id" { cipher.id = nil } else { cipher.reprompt = 1 }
        let before = try Foundation.Data(contentsOf: fixture.cacheURL)
        #expect(throws: (any Error).self) {
            try fixture.store.upsertReturningReceipt(
                cipher,
                for: fixture.proof.account,
                requiringProof: fixture.proof,
                cacheRevision: fixture.originalRevision
            )
        }
        #expect(try Foundation.Data(contentsOf: fixture.cacheURL) == before)
    }
}
