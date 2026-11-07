import AutoFillContract
import Data
import Domain
import Foundation
import Testing

@Suite
struct PasskeyRegistrationRecoveryReconcilerTests {
    private func identity(
        id: UInt8 = 1,
        rp: String = "example.com",
        cipher: String = "saved",
        kind: CredentialIdentityKind = .passkey
    ) -> CredentialIdentityDescriptor {
        CredentialIdentityDescriptor(
            id: "fixture",
            kind: kind,
            serviceIdentifier: rp,
            user: "fixture-user",
            label: nil,
            credentialID: Foundation.Data([id]),
            userHandle: Foundation.Data(),
            recordIdentifier: CipherID(rawValue: cipher)
        )
    }

    private func make(
        _ journal: PasskeyRecoveryJournalFixture,
        access: PasskeyRecoveryAccessFixture = PasskeyRecoveryAccessFixture()
    ) -> PasskeyRegistrationRecoveryReconciler {
        PasskeyRegistrationRecoveryReconciler(
            journal: journal,
            proof: PasskeyRecoveryJournalFixture.proof,
            checkAccess: { try access.check() }
        )
    }

    @Test(arguments: [false, true])
    func onlyObservedCredentialWithSuccessfulProjectionAndOSPublicationCanClearTheMarker(_ confirmed: Bool) async throws {
        let journal = PasskeyRecoveryJournalFixture(), record = PasskeyRecoveryJournalFixture.record()
        try journal.reserve(record, requiring: PasskeyRecoveryJournalFixture.proof)
        if confirmed { try journal.confirm(
            record.mutationID,
            serverCipherID: "saved",
            requiring: PasskeyRecoveryJournalFixture.proof
        ) }
        let recovery = make(journal)
        #expect(try await recovery.reconcile(identities: [identity()], canResolve: false))
        #expect(journal.entries.count == 1)
        #expect(try await !recovery.reconcile(identities: [identity()], canResolve: true))
        #expect(journal.entries.isEmpty)
    }

    @Test(arguments: ["wrong-id", "wrong-rp", "foreign-cipher", "wrong-kind", "duplicate", "missing"])
    func aSyncWithoutExactUniqueIdentityKeepsRecoveryBlocked(_ failure: String) async throws {
        let journal = PasskeyRecoveryJournalFixture(), record = PasskeyRecoveryJournalFixture.record(target: "saved")
        try journal.reserve(record, requiring: PasskeyRecoveryJournalFixture.proof)
        var identities = [
            identity(
                id: failure == "wrong-id" ? 2 : 1,
                rp: failure == "wrong-rp" ? "sub.example.com" : "example.com",
                cipher: failure == "foreign-cipher" ? "other" : "saved",
                kind: failure == "wrong-kind" ? .password : .passkey
            ),
        ]
        if failure == "duplicate" { identities.append(identity()) }
        if failure == "missing" { identities = [] }
        #expect(try await make(journal).reconcile(identities: identities, canResolve: true))
        #expect(journal.entries.count == 1)
    }

    @Test
    func unknownCreateDoesNotResolveWhenItsCredentialAppearsInMultipleCiphers() async throws {
        let journal = PasskeyRecoveryJournalFixture()
        try journal.reserve(PasskeyRecoveryJournalFixture.record(), requiring: PasskeyRecoveryJournalFixture.proof)
        #expect(try await make(journal).reconcile(identities: [identity(), identity(cipher: "other")], canResolve: true))
        #expect(journal.entries.count == 1)
    }

    @Test(arguments: ["read", "remove", "lock"])
    func cleanupOrAuthorizationFailureNeverClaimsRecoveryIsFinished(_ failure: String) async throws {
        let journal = PasskeyRecoveryJournalFixture(), access = PasskeyRecoveryAccessFixture()
        try journal.reserve(PasskeyRecoveryJournalFixture.record(), requiring: PasskeyRecoveryJournalFixture.proof)
        if failure == "lock" { access.revoke() } else { journal.fail(failure) }
        await #expect(throws: (any Error).self) { _ = try await make(journal, access: access).reconcile(
            identities: [identity()],
            canResolve: true
        ) }
        #expect(journal.entries.count == 1)
    }
}
