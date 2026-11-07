import AutoFillContract
import AutoFillData
import BitwardenSdk
import Foundation
import Testing

@Suite
struct PasskeyServiceTests {
    @Test
    func platformRestrictionsFilterAndBindTheSelectedCredential() async throws {
        let (_, service) = fixture()
        let first = try #require(try await service.matching(relyingPartyIdentifier: "example.com").items.first)
        let allowed = [Foundation.Data([2])]
        let list = try await service.matching(relyingPartyIdentifier: "example.com", allowedCredentials: allowed)
        #expect(list.items.map(\.fido2CredentialId) == allowed.map(Optional.some))
        await #expect(throws: AutoFillOperationError.decryptFailed) {
            _ = try await service.assertion(
                for: first,
                relyingPartyIdentifier: "example.com",
                allowedCredentials: allowed
            ) { _, _ in
                Issue.record("Disallowed credential reached authenticator"); return Self.payload()
            }
        }
    }

    @Test(arguments: [false, true])
    func requiredVerificationIsSentAndMustBePresentInAuthenticatorData(verified: Bool) async throws {
        let (_, service) = fixture()
        let match = try #require(try await service.matching(relyingPartyIdentifier: "example.com").items.first)
        let authenticate: PasskeyService.Authenticate = { _, request in
            let json = try #require(
                try JSONSerialization.jsonObject(with: Foundation.Data(request.utf8)) as? [String: Any]
            )
            let publicKey = try #require(json["publicKey"] as? [String: Any])
            #expect(publicKey["userVerification"] as? String == "required")
            var data = Foundation.Data(repeating: 0, count: 37)
            if verified { data[32] = 0x04 }
            return PasskeyAssertionPayload(
                userHandle: Foundation.Data(),
                signature: Foundation.Data([3]),
                authenticatorData: data,
                credentialID: Foundation.Data([1])
            )
        }
        if verified {
            _ = try await service.assertion(
                for: match,
                relyingPartyIdentifier: "example.com",
                userVerification: "required",
                authenticate: authenticate
            )
        } else {
            await #expect(throws: AutoFillOperationError.accessDenied) {
                _ = try await service.assertion(
                    for: match,
                    relyingPartyIdentifier: "example.com",
                    userVerification: "required",
                    authenticate: authenticate
                )
            }
        }
    }

    @Test
    func requiredVerificationRejectsShortDataAndUnknownPreferences() async throws {
        let (_, service) = fixture()
        let match = try #require(try await service.matching(relyingPartyIdentifier: "example.com").items.first)
        await #expect(throws: AutoFillOperationError.accessDenied) {
            _ = try await service.assertion(
                for: match,
                relyingPartyIdentifier: "example.com",
                userVerification: "required"
            ) { _, _ in Self.payload() }
        }
        await #expect(throws: (any Error).self) {
            _ = try await service.assertion(
                for: match,
                relyingPartyIdentifier: "example.com",
                userVerification: "unexpected"
            ) { _, _ in
                Issue.record("Unknown preference reached authenticator"); return Self.payload()
            }
        }
    }

    private func fixture(gate: AuthOperationTestGate? = nil) -> (AutoFillQuerySourceFixture, PasskeyService) {
        let source = AutoFillQuerySourceFixture(gate: gate)
        source.setView(AutoFillQuerySourceFixture.view(hasPasskeys: true))
        source.setPasskeys([AutoFillQuerySourceFixture.passkey(), AutoFillQuerySourceFixture.passkey(id: 2)])
        return (source, PasskeyService(source: source, credentials: CredentialQuery(source: source)))
    }

    private static func payload(id: UInt8 = 1) -> PasskeyAssertionPayload {
        PasskeyAssertionPayload(
            userHandle: Foundation.Data(),
            signature: Foundation.Data([3]),
            authenticatorData: Foundation.Data([4]),
            credentialID: Foundation.Data([id])
        )
    }

    @Test
    func matchingRequiresExactRPAndDistinctPasskeysHaveDistinctPickerIdentity() async throws {
        let (_, service) = fixture()
        let list = try await service.matching(relyingPartyIdentifier: "example.com")
        #expect(list.items.count == 2 && list.items[0].id != list.items[1].id)
        #expect(list.items.allSatisfy { !$0.hasTOTP && $0.uris.isEmpty && $0.fido2UserHandle?.isEmpty == true })
        #expect(try await service.matching(relyingPartyIdentifier: "sub.example.com").items.isEmpty)
    }

    @Test(arguments: [100, 1_000, 10_000])
    func largePasskeyQueryReadsCacheOnlyAtTheSnapshotAndOutputFence(itemCount: Int) async throws {
        let ids = (0 ..< itemCount).map { "cipher-\($0)" }
        let source = AutoFillQuerySourceFixture(ids: ids)
        let service = PasskeyService(source: source, credentials: CredentialQuery(source: source))
        let result = try await service.matching(relyingPartyIdentifier: "example.com")
        #expect(result.items.isEmpty)
        #expect(source.decryptedIDs.count == ids.count)
        #expect(source.cacheReads == 2)
    }

    @Test
    func partialFailureIsVisibleAndAmbiguousIDsAreDenied() async throws {
        let source = AutoFillQuerySourceFixture(ids: ["duplicate", "duplicate", "broken"])
        source.fail("broken")
        let service = PasskeyService(source: source, credentials: CredentialQuery(source: source))
        let result = try await service.matching(relyingPartyIdentifier: "example.com")
        #expect(result.items.isEmpty && result.unavailableItemCount == 3 && result.warningMessage != nil)
        #expect(source.decryptedIDs == ["broken"])
    }

    @Test
    func assertionBindsTheCurrentRPAndSelectedBytesBeforeCallingAuthenticator() async throws {
        let (_, service) = fixture()
        let match = try #require(try await service.matching(relyingPartyIdentifier: "example.com").items.first)
        let calls = AuthInvocationProbe()
        for rp in ["unrelated.com", "sub.example.com"] {
            await #expect(throws: AutoFillOperationError.accessDenied) {
                _ = try await service.assertion(for: match, relyingPartyIdentifier: rp) { _, _ in await calls.record(); return Self.payload(
                ) }
            }
        }
        #expect(await calls.count == 0)
        let withoutHandle = AutoFillLoginSummary(
            cipherId: match.cipherId,
            name: match.name,
            username: match.username,
            fido2CredentialId: match.fido2CredentialId
        )
        let result = try await service.assertion(for: withoutHandle, relyingPartyIdentifier: "example.com") { view, request in
            #expect(view.id == "cipher-1")
            let json = try #require(
                try JSONSerialization.jsonObject(with: Foundation.Data(request.utf8)) as? [String: Any]
            )
            let publicKey = try #require(json["publicKey"] as? [String: Any])
            #expect(publicKey["rpId"] as? String == "example.com")
            let allowed = try #require(publicKey["allowCredentials"] as? [[String: String]])
            #expect(allowed == [["id": "AQ", "type": "public-key"]])
            return Self.payload() // missing stored user handle stays supported
        }
        #expect(result.credentialID == Foundation.Data([1]))
    }

    @Test
    func selectedCredentialRemovedAfterListingIsNotAuthenticated() async throws {
        let (source, service) = fixture()
        let match = try #require(try await service.matching(relyingPartyIdentifier: "example.com").items.first)
        source.setPasskeys([AutoFillQuerySourceFixture.passkey(id: 2)])
        await #expect(throws: AutoFillOperationError.accessDenied) {
            _ = try await service.assertion(for: match, relyingPartyIdentifier: "example.com") { _, _ in
                Issue.record("Removed credential reached authenticator"); return Self.payload()
            }
        }
    }

    @Test(arguments: ["lock", "policy", "cancel"])
    func lateAuthenticationCannotReturnAnAssertionAfterAuthorizationChange(_ change: String) async throws {
        let (source, service) = fixture()
        let match = try #require(try await service.matching(relyingPartyIdentifier: "example.com").items.first)
        let gate = AuthOperationTestGate()
        let task = Task { try await service.assertion(for: match, relyingPartyIdentifier: "example.com") { _, _ in
            await gate.pause(); return Self.payload()
        } }
        await gate.waitUntilPaused()
        if change == "policy" { source.editCache { $0.ciphers[0].reprompt = 1 } }
        if change == "lock" { source.deny() }
        if change == "cancel" { task.cancel() }
        await gate.release()
        if change == "policy" { await #expect(throws: AutoFillOperationError.accessDenied) { _ = try await task.value } }
        else { await #expect(throws: CancellationError.self) { _ = try await task.value } }
    }

    @Test
    func duplicateAssertionIsRejectedAcrossActorReentrancyAndTheGateReopensAfterward() async throws {
        let (_, service) = fixture()
        let match = try #require(try await service.matching(relyingPartyIdentifier: "example.com").items.first)
        let gate = AuthOperationTestGate()
        let task = Task { try await service.assertion(for: match, relyingPartyIdentifier: "example.com") { _, _ in
            await gate.pause(); return Self.payload()
        } }
        await gate.waitUntilPaused()
        await #expect(throws: AutoFillOperationError.operationInProgress) {
            _ = try await service.assertion(for: match, relyingPartyIdentifier: "example.com") { _, _ in
                Issue.record("Duplicate authenticator call"); return Self.payload()
            }
        }
        await gate.release()
        _ = try await task.value
        _ = try await service.assertion(for: match, relyingPartyIdentifier: "example.com") { _, _ in Self.payload() }
    }

    @Test
    func authenticatorReturningDifferentCredentialCannotBeCompleted() async throws {
        let (_, service) = fixture()
        let match = try #require(try await service.matching(relyingPartyIdentifier: "example.com").items.first)
        await #expect(throws: AutoFillOperationError.accessDenied) {
            _ = try await service.assertion(for: match, relyingPartyIdentifier: "example.com") { _, _ in Self.payload(
                id: 2
            ) }
        }
    }

    @Test
    func invalidOrDuplicatedCredentialMetadataDoesNotProduceAmbiguousPickerRows() async throws {
        let (source, service) = fixture()
        source.setPasskeys([AutoFillQuerySourceFixture.passkey(),
                            AutoFillQuerySourceFixture.passkey(),
                            Fido2CredentialAutofillView(
                                credentialId: Foundation.Data(),
                                cipherId: "cipher-1",
                                rpId: "example.com",
                                userNameForUi: "fixture-user",
                                userHandle: Foundation.Data(),
                                hasCounter: false
                            ),
                            Fido2CredentialAutofillView(
                                credentialId: Foundation.Data([3]),
                                cipherId: "foreign-cipher",
                                rpId: "example.com",
                                userNameForUi: "fixture-user",
                                userHandle: Foundation.Data(),
                                hasCounter: false
                            ),
                            AutoFillQuerySourceFixture.passkey(id: 2)])
        let result = try await service.matching(relyingPartyIdentifier: "example.com")
        #expect(result.items.map(\.fido2CredentialId) == [Foundation.Data([2])])
        #expect(result.unavailableItemCount == 1 && result.warningMessage != nil)
    }

    @Test
    func credentialAmbiguityAppearingAfterListingDeniesAssertionBeforeSDKCallback() async throws {
        let (source, service) = fixture()
        let match = try #require(try await service.matching(relyingPartyIdentifier: "example.com").items.first)
        source.setPasskeys([AutoFillQuerySourceFixture.passkey(), AutoFillQuerySourceFixture.passkey()])
        await #expect(throws: AutoFillOperationError.accessDenied) {
            _ = try await service.assertion(for: match, relyingPartyIdentifier: "example.com") { _, _ in
                Issue.record("Ambiguous credential reached SDK callback"); return Self.payload()
            }
        }
    }

    @Test
    func directIdentityDecryptsOnlyItsCipherAndSelectsTheExactCredential() async throws {
        let source = AutoFillQuerySourceFixture(ids: ["unrelated", "cipher-1"])
        source.fail("unrelated")
        source.setView(AutoFillQuerySourceFixture.view(hasPasskeys: true))
        source.setPasskeys([AutoFillQuerySourceFixture.passkey(), AutoFillQuerySourceFixture.passkey(id: 2)])
        let service = PasskeyService(source: source, credentials: CredentialQuery(source: source))
        let match = try await service.match(
            cipherId: "cipher-1",
            credentialID: Foundation.Data([2]),
            relyingPartyIdentifier: "example.com"
        )
        #expect(match.cipherId == "cipher-1" && match.fido2CredentialId == Foundation.Data([2]))
        #expect(source.decryptedIDs == ["cipher-1"])
    }

    @Test(
        arguments: [
            "wrong-rp",
            "unknown-id",
            "duplicate-id",
            "foreign-cipher",
            "empty-id",
            "missing-cipher",
            "no-passkeys",
            "decrypt-error",
        ]
    )
    func invalidDirectIdentityCannotSubstituteAnotherCredentialOrBrowseOtherItems(_ failure: String) async throws {
        let (source, service) = fixture()
        if failure == "duplicate-id" { source.setPasskeys(
            [AutoFillQuerySourceFixture.passkey(), AutoFillQuerySourceFixture.passkey()]
        ) }
        if failure == "foreign-cipher" {
            source.setPasskeys([Fido2CredentialAutofillView(
                credentialId: Foundation.Data([1]),
                cipherId: "foreign",
                rpId: "example.com",
                userNameForUi: nil,
                userHandle: Foundation.Data(),
                hasCounter: false
            )])
        }
        if failure == "no-passkeys" { source.setView(AutoFillQuerySourceFixture.view()) }
        if failure == "decrypt-error" { source.fail("cipher-1") }
        let id = failure == "empty-id" ? Foundation.Data() : Foundation.Data([failure == "unknown-id" ? 99 : 1])
        await #expect(throws: (any Error).self) {
            _ = try await service.match(
                cipherId: failure == "missing-cipher" ? "missing" : "cipher-1",
                credentialID: id,
                relyingPartyIdentifier: failure == "wrong-rp" ? "sub.example.com" : "example.com"
            )
        }
        #expect(source.decryptedIDs.allSatisfy { $0 == "cipher-1" })
    }

    @Test(arguments: ["cancel", "lock", "policy"])
    func directIdentityDeniesLateDecryptionAfterAuthorizationChange(_ change: String) async throws {
        let gate = AuthOperationTestGate()
        let (source, service) = fixture(gate: gate)
        let task = Task { try await service.match(
            cipherId: "cipher-1",
            credentialID: Foundation.Data([1]),
            relyingPartyIdentifier: "example.com"
        ) }
        await gate.waitUntilPaused()
        if change == "cancel" { task.cancel() }
        if change == "lock" { source.deny() }
        if change == "policy" { source.editCache { $0.ciphers[0].reprompt = 1 } }
        await gate.release()
        await #expect(throws: (any Error).self) { _ = try await task.value }
        #expect(source.decryptedIDs == ["cipher-1"])
    }
}
