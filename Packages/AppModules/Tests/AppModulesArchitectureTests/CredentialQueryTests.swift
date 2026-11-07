import AutoFillContract
import AutoFillData
import BitwardenSdk
import BitwardenSDKAdapter
import Foundation
import Testing

@Suite
struct CredentialQueryTests {
    @Test
    func freshUnsupportedPayloadBlocksRetainedRegistrationSelectionWithoutBlockingPasswordReads() async throws {
        let source = AutoFillQuerySourceFixture()
        let original = SDKAutoFillCredentialView(legacyView: AutoFillQuerySourceFixture.view())
        var object = try #require(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(AutoFillQuerySourceFixture.dto("cipher-1"))
        ) as? [String: Any])
        object["futureField"] = "encrypted-future"
        var changed = try JSONDecoder().decode(
            CipherResponseDTO.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        changed.edit = true // even a stale adapter trying to restore the flag cannot bypass it
        source.editCache { $0.ciphers = [changed] }
        try CredentialQuery.requireCurrentAccess(to: original, source: source)
        #expect(throws: AutoFillOperationError.accessDenied) {
            try CredentialQuery.requireCurrentAccess(to: original, source: source, forEditing: true)
        }
        #expect(
            try await CredentialQuery(source: source).password(cipherId: "cipher-1").password == "synthetic-password"
        )
    }

    @Test
    func pickerSummaryContainsNoPasswordOrSeedAndOnlyManualBrowsingWidensMatches() async throws {
        let source = AutoFillQuerySourceFixture()
        let query = CredentialQuery(source: source)
        let manual = try await query.logins()
        let item = try #require(manual.items.first)
        #expect(item.hasTOTP && manual.unavailableItemCount == 0 && manual.warningMessage == nil)
        #expect(!Mirror(reflecting: item).children.contains { ["password", "totpSeed"].contains($0.label ?? "") })
        #expect(
            !String(reflecting: item).contains("synthetic-password") && !String(reflecting: item).contains(
                "synthetic-seed"
            )
        )
        let backing = SDKAutoFillCredentialView(legacyView: AutoFillQuerySourceFixture.view())
        #expect(!String(reflecting: backing).contains("synthetic-password"))
        #expect(!String(reflecting: backing.login).contains("synthetic-seed"))
        #expect(CredentialQuery.filter(manual.items, matching: ["https://unrelated.example.org"]).isEmpty)
        #expect(CredentialQuery.filter(manual.items, matching: ["https://sub.example.com"]).count == 1)
    }

    @Test
    func eachEligibleItemIsDecryptedOnceAndPartialFailureIsReportedWithoutLosingHealthyItems() async throws {
        let source = AutoFillQuerySourceFixture(ids: ["good", "broken", "protected"])
        source.fail("broken")
        source.editCache { $0.ciphers[2].reprompt = 1 }
        let result = try await CredentialQuery(source: source).logins()
        #expect(result.items.map(\.cipherId) == ["good"])
        #expect(source.decryptedIDs == ["good", "broken"])
        #expect(result.unavailableItemCount == 1 && result.warningMessage != nil)
    }

    @Test(arguments: [100, 1_000, 10_000])
    func largeLoginQueryReadsTheCacheOnlyAtTheSnapshotAndOutputFence(itemCount: Int) async throws {
        let ids = (0 ..< itemCount).map { "cipher-\($0)" }
        let source = AutoFillQuerySourceFixture(ids: ids)
        let result = try await CredentialQuery(source: source).logins()
        #expect(result.items.count == ids.count)
        #expect(source.decryptedIDs.count == ids.count)
        #expect(source.cacheReads == 2)
    }

    @Test
    func duplicateIDsCannotProduceAmbiguousPickerRowsOrDirectCredentials() async throws {
        let source = AutoFillQuerySourceFixture(ids: ["duplicate", "duplicate", "good"])
        let query = CredentialQuery(source: source)
        let result = try await query.logins()
        #expect(result.items.map(\.cipherId) == ["good"])
        #expect(result.unavailableItemCount == 2 && source.decryptedIDs == ["good"])
        await #expect(throws: AutoFillOperationError.accessDenied) { _ = try await query.password(cipherId: "duplicate") }
    }

    @Test
    func decryptedIdentityOrPolicyMismatchDoesNotBecomeAnAvailableCredential() async throws {
        let source = AutoFillQuerySourceFixture()
        source.setView(AutoFillQuerySourceFixture.view(id: "different"))
        let query = CredentialQuery(source: source)
        #expect(try await query.logins().unavailableItemCount == 1)
        await #expect(throws: AutoFillOperationError.accessDenied) { _ = try await query.password(cipherId: "cipher-1") }
        source.setView(AutoFillQuerySourceFixture.view(reprompt: .password))
        await #expect(throws: AutoFillOperationError.accessDenied) { _ = try await query.password(cipherId: "cipher-1") }
    }

    @Test(arguments: [false, true])
    func lateDecryptAfterCancellationOrRevocationCannotReturnListOrPassword(_ password: Bool) async throws {
        let gate = AuthOperationTestGate()
        let source = AutoFillQuerySourceFixture(gate: gate)
        let query = CredentialQuery(source: source)
        let task = Task {
            if password { _ = try await query.password(cipherId: "cipher-1") }
            else { _ = try await query.logins() }
        }
        await gate.waitUntilPaused()
        source.deny()
        task.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test
    func changedCachePolicyDuringDecryptIsCheckedBeforePublication() async throws {
        let gate = AuthOperationTestGate()
        let source = AutoFillQuerySourceFixture(gate: gate)
        let task = Task { try await CredentialQuery(source: source).password(cipherId: "cipher-1") }
        await gate.waitUntilPaused()
        source.editCache { $0.ciphers[0].reprompt = 1 }
        await gate.release()
        await #expect(throws: AutoFillOperationError.accessDenied) { _ = try await task.value }
    }

    @Test
    func changedCachePolicyDuringListDecryptCannotPublishTheOldSnapshot() async throws {
        let gate = AuthOperationTestGate()
        let source = AutoFillQuerySourceFixture(gate: gate)
        let task = Task { try await CredentialQuery(source: source).logins() }
        await gate.waitUntilPaused()
        source.editCache { $0.ciphers[0].reprompt = 1 }
        await gate.release()
        await #expect(throws: AutoFillOperationError.accessDenied) { _ = try await task.value }
    }

    @Test
    func passwordAndTOTPResolveFreshValuesRatherThanPickerSecrets() async throws {
        let source = AutoFillQuerySourceFixture()
        let query = CredentialQuery(source: source)
        let old = try #require(try await query.logins(requiringTOTP: true).items.first)
        source.setView(AutoFillQuerySourceFixture.view(seed: "new-seed", password: "new-password"))
        let password = try await query.password(cipherId: old.cipherId)
        #expect(password.password == "new-password" && password.username == "fixture-user")
        #expect(!String(reflecting: password).contains("new-password"))
        #expect(try await query.oneTimeCode(cipherId: old.cipherId).code == "123456")
        #expect(source.seeds == ["new-seed"])
    }

    @Test
    func missingTOTPIsExcludedFromListAndFailsFulfilment() async throws {
        let source = AutoFillQuerySourceFixture()
        source.setView(AutoFillQuerySourceFixture.view(seed: nil, password: nil))
        let query = CredentialQuery(source: source)
        #expect(try await query.logins(requiringTOTP: true).items.isEmpty)
        await #expect(throws: AutoFillOperationError.decryptFailed) { _ = try await query.oneTimeCode(
            cipherId: "cipher-1"
        ) }
        await #expect(throws: AutoFillOperationError.decryptFailed) { _ = try await query.password(cipherId: "cipher-1") }
    }

    @Test
    func revokedDuringCodeGenerationDoesNotReturnCode() async {
        let source = AutoFillQuerySourceFixture()
        source.onCode { source.deny() }
        await #expect(throws: CancellationError.self) { _ = try await CredentialQuery(source: source).oneTimeCode(
            cipherId: "cipher-1"
        ) }
    }
}
