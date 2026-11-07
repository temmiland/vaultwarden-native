import AutoFillContract
import AutoFillData
import Data
import Domain
import Foundation
import Testing

@Suite
struct PasskeyRegistrationRecoveryReviewTests {
    @Test
    func legacyOriginDoesNotPreventExactCredentialReconciliationAfterFullProjection() async throws {
        let fixture = try PasskeyRecoveryReviewFixture(legacy: true); defer { fixture.cleanup() }
        let recovery = fixture.recovery()
        #expect(try await recovery.reconcile(identities: [PasskeyProjectionCacheFixture.identity()], canResolve: false))
        #expect(try fixture.journal.records(requiring: fixture.fresh).first?.originatingUnlockID == nil)
        #expect(try await !recovery.reconcile(identities: [PasskeyProjectionCacheFixture.identity()], canResolve: true))
        #expect(try fixture.journal.records(requiring: fixture.fresh).isEmpty)
    }

    @Test(arguments: [false, true])
    func explicitAcknowledgmentFromAFreshUnlockRemovesOnlyTheReviewedMarker(_ confirmed: Bool) async throws {
        let fixture = try PasskeyRecoveryReviewFixture(confirmed: confirmed); defer { fixture.cleanup() }
        let service = fixture.recovery(), review = try await service.prepareReview(vaultRevision: 17)
        #expect(review.readiness == .ready && review.vaultRevision == 17 && review.serverConfirmed == confirmed)
        #expect(review.relyingPartyIdentifier == "example.com")
        #expect(String(describing: review) == "PasskeyRegistrationRecoveryReview(<redacted>)")
        #expect(try fixture.journal.records(requiring: fixture.fresh).count == 1) // review alone never clears
        #expect(try await !service.abandon(review))
        #expect(try fixture.journal.records(requiring: fixture.fresh).isEmpty)
        await #expect(throws: PasskeyRegistrationReviewError.reviewChanged) { try await service.abandon(review) }
    }

    @Test(arguments: ["same-unlock", "legacy"])
    func unsafeReviewIsInformationalAndCannotAbandonTracking(_ reason: String) async throws {
        let fixture = try PasskeyRecoveryReviewFixture(sameUnlock: reason == "same-unlock", legacy: reason == "legacy")
        defer { fixture.cleanup() }
        let service = fixture.recovery(), review = try await service.prepareReview(vaultRevision: 17)
        let error: PasskeyRegistrationReviewError = reason == "legacy" ? .legacyOriginUnknown : .freshUnlockRequired
        #expect(review.readiness == (reason == "legacy" ? .legacyOriginUnknown : .requiresFreshUnlock))
        await #expect(throws: error) { try await service.abandon(review) }
        #expect(try fixture.journal.records(requiring: fixture.fresh).count == 1)
    }

    @Test(arguments: ["new-review", "sync", "forged"])
    func oldOrForgedConsentCannotResolveTheCurrentRecord(_ reason: String) async throws {
        let fixture = try PasskeyRecoveryReviewFixture(); defer { fixture.cleanup() }
        let service = fixture.recovery(), review = try await service.prepareReview(vaultRevision: 17)
        if reason == "new-review" { _ = try await service.prepareReview(vaultRevision: 17) }
        if reason == "sync" { #expect(try await service.reconcile(identities: [], canResolve: true)) }
        let submitted = reason == "forged" ? PasskeyRegistrationRecoveryReview(
            id: review.id,
            vaultRevision: 18,
            relyingPartyIdentifier: review.relyingPartyIdentifier,
            serverConfirmed: review.serverConfirmed,
            readiness: .ready
        ) : review
        await #expect(throws: PasskeyRegistrationReviewError.reviewChanged) { try await service.abandon(submitted) }
        #expect(try fixture.journal.records(requiring: fixture.fresh).count == 1)
    }

    @Test
    func recordPhaseChangeBetweenReviewAndRemovalFailsExactCompareAndKeepsTracking() async throws {
        let fixture = try PasskeyRecoveryReviewFixture(); defer { fixture.cleanup() }
        let service = fixture.recovery(), review = try await service.prepareReview(vaultRevision: 17)
        try fixture.journal.confirm(fixture.record.mutationID, serverCipherID: "saved", requiring: fixture.fresh)
        await #expect(throws: PasskeyRegistrationReviewError.reviewChanged) { try await service.abandon(review) }
        #expect(try fixture.journal.records(requiring: fixture.fresh).first?.phase == .confirmed)
    }

    @Test(arguments: ["runtime", "grant", "future-schema"])
    func accessOrStorageFailureNeverErasesAnUnreviewedMarker(_ reason: String) async throws {
        let fixture = try PasskeyRecoveryReviewFixture(); defer { fixture.cleanup() }
        let service = fixture.recovery(), review = try await service.prepareReview(vaultRevision: 17)
        if reason == "runtime" { fixture.access.revoke() }
        if reason == "grant" { fixture.authorization.setProof(ExtensionUnlockProof(account: fixture.fresh.account)) }
        if reason == "future-schema" {
            var json = try #require(
                JSONSerialization.jsonObject(with: Foundation.Data(contentsOf: fixture.file)) as? [String: Any]
            )
            json["schemaVersion"] = 2
            try JSONSerialization.data(withJSONObject: json).write(to: fixture.file)
        }
        let before = try Foundation.Data(contentsOf: fixture.file)
        await #expect(throws: (any Error).self) { try await service.abandon(review) }
        #expect(try Foundation.Data(contentsOf: fixture.file) == before)
    }

    @Test
    func abandonmentCannotRemoveAForeignServersRecord() async throws {
        let fixture = try PasskeyRecoveryReviewFixture(); defer { fixture.cleanup() }
        let foreign = ExtensionUnlockProof(account: AutoFillAccountIdentity(
            userID: fixture.fresh.account.userID,
            serverBaseURL: URL(string: "https://foreign.example.com")!
        ))
        fixture.authorization.setProof(foreign)
        let foreignRecord = PasskeyRegistrationRecoveryRecord(
            account: foreign.account,
            credentialID: Foundation.Data([2]),
            relyingPartyIdentifier: "example.com",
            targetCipherID: nil
        )
        try fixture.journal.reserve(foreignRecord, requiring: foreign)
        fixture.authorization.setProof(fixture.fresh)
        let service = fixture.recovery(), review = try await service.prepareReview(vaultRevision: 17)
        #expect(try await !service.abandon(review))
        fixture.authorization.setProof(foreign)
        #expect(try fixture.journal.records(requiring: foreign).map(\.mutationID) == [foreignRecord.mutationID])
    }
}
