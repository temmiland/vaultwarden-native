import AutoFillContract
import AutoFillData
import Foundation
import Testing

@Suite
struct AutoFillIdentityMutationPolicyTests {
    @Test(arguments: ["current", "old", "new", "legacy", "foreign", "foreign-server", "missing-owner", "missing-uuid"])
    func publicationRequiresExactOwnerAndMonotonicCacheRevision(_ scenario: String) throws {
        let proof = PasskeyRecoveryJournalFixture.proof
        var cache = SharedVaultCacheData(
            ciphers: [],
            organizationKeys: [:],
            updatedAt: .distantPast,
            owner: scenario == "foreign" ? AutoFillAccountIdentity(
                userID: "other",
                serverBaseURL: proof.account.serverBaseURL
            ) :
                (
                    scenario == "foreign-server" ? AutoFillAccountIdentity(
                        userID: proof.account.userID,
                        serverBaseURL: URL(string: "https://other.example.com")!
                    ) : proof.account
                ),
            revision: UUID(),
            projectionRevision: scenario == "legacy" ? nil : (scenario == "old" ? 16 : (scenario == "new" ? 18 : 17))
        )
        if scenario == "missing-owner" { cache.owner = nil }
        if scenario == "missing-uuid" { cache.revision = nil }
        if scenario == "current" { try AutoFillIdentityMutationPolicy.requirePublication(
            cache: cache,
            proof: proof,
            revision: 17
        ) } else { #expect(throws: (any Error).self) { try AutoFillIdentityMutationPolicy.requirePublication(
            cache: cache,
            proof: proof,
            revision: 17
        ) } }
    }

    @Test(arguments: ["same", "revoked", "successor", "missing-origin", "no-grant"])
    func clearAllowsRevokedOrSameUnlockButNeverAnOlderSessionOverSuccessor(_ scenario: String) throws {
        let proof = PasskeyRecoveryJournalFixture.proof
        let captured = ["missing-origin", "no-grant"].contains(scenario) ? nil : proof
        let current = ["revoked", "no-grant"].contains(scenario) ? nil : (
            scenario == "successor" ? ExtensionUnlockProof(account: proof.account) : proof
        )
        if ["successor", "missing-origin"].contains(scenario) {
            #expect(throws: CancellationError.self) { try AutoFillIdentityMutationPolicy.requireClear(
                capturedProof: captured,
                currentProof: current
            ) }
        } else { try AutoFillIdentityMutationPolicy.requireClear(capturedProof: captured, currentProof: current) }
    }
}
