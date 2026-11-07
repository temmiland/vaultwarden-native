import AutoFillData
import BitwardenSdk
@testable import BitwardenSDKAdapter
import Domain
import Foundation
import Testing

@Suite
struct SDKAutoFillFidoCallbackTests {
    @Test(arguments: [Verification.preferred, .required])
    func explicitVerificationCancellationCannotFallBackOrReprompt(_ requirement: Verification) async throws {
        let verification = FidoVerificationFixture(failure: .userCanceled)
        let callback = ui(verification: verification), hint = UiHint.requestExistingCredential(
            AutoFillQuerySourceFixture.view()
        )
        await #expect(throws: PasskeyUserVerificationError.userCanceled) {
            try await callback.checkUser(
                options: CheckUserOptions(requirePresence: true, requireVerification: requirement),
                hint: hint
            )
        }
        await #expect(throws: PasskeyUserVerificationError.userCanceled) {
            try await callback.checkUser(
                options: CheckUserOptions(requirePresence: true, requireVerification: .discouraged),
                hint: hint
            )
        }
        #expect(verification.calls == 1 && !callback.isVerificationEnabled())
    }

    @Test(arguments: [false, true])
    func typedVerificationCancellationSurvivesWrappedErrorOrReturnedOutput(_ returnsOutput: Bool) async throws {
        let callback = ui(verification: FidoVerificationFixture(failure: .userCanceled))
        await #expect(throws: PasskeyUserVerificationError.userCanceled) {
            try await callback.withVerificationFailureMapping {
                do {
                    _ = try await callback.checkUser(
                        options: CheckUserOptions(requirePresence: true, requireVerification: .preferred),
                        hint: .requestExistingCredential(AutoFillQuerySourceFixture.view())
                    )
                } catch { /* emulate an FFI layer swallowing or wrapping the typed error */ }
                if returnsOutput { return 1 }
                throw PasskeyRecoveryFixtureError.storage
            }
        }
    }

    private let view = SDKAutoFillCredentialView(legacyView: AutoFillQuerySourceFixture.view(hasPasskeys: true))
    private func metadata(
        id: Foundation.Data = Foundation.Data([1]),
        cipher: String = "cipher-1",
        handle: Foundation.Data = Foundation.Data([7])
    ) -> SDKAutoFillPasskeyMetadata {
        SDKAutoFillPasskeyMetadata(legacyView: Fido2CredentialAutofillView(
            credentialId: id,
            cipherId: cipher,
            rpId: "example.com",
            userNameForUi: "user",
            userHandle: handle,
            hasCounter: false
        ))
    }

    private func ui(
        verification: any PasskeyUserVerifying = FidoVerificationFixture(),
        access: PasskeyRecoveryAccessFixture = PasskeyRecoveryAccessFixture(),
        target: SDKAutoFillCredentialView? = nil
    ) -> SDKAutoFillFidoUserInterface {
        SDKAutoFillFidoUserInterface(
            selectedForAuthentication: view,
            targetForCreation: target,
            relyingPartyIdentifier: "example.com",
            readAccess: { try Task.checkCancellation(); try access.check() },
            checkAccess: { try access.check() },
            requireCurrent: { _, _ in try access.check() },
            verification: verification
        )
    }

    @Test(arguments: ["match", "id", "rp", "handle", "nil-ids", "empty-ids", "empty-handle"])
    func findingCredentialsHonorsSDKDecodedIDsExactRPAndUserHandle(_ scenario: String) async throws {
        let credential = metadata()
        let store = SDKAutoFillFidoCredentialStore(
            views: [view],
            userID: "user-1",
            readAccess: {},
            checkAccess: {},
            metadata: { _ in [credential] }
        )
        let ids: [Foundation.Data]? = scenario == "nil-ids" ? nil : (
            scenario == "empty-ids" ? [] : [Foundation.Data([scenario == "id" ? 2 : 1])]
        )
        let handle = scenario == "empty-handle" ? Foundation.Data() : Foundation.Data([scenario == "handle" ? 8 : 7])
        let matches = try await store.findCredentials(
            ids: ids,
            ripId: scenario == "rp" ? "sub.example.com" : "example.com",
            userHandle: handle
        )
        #expect(matches.count == (["id", "rp", "handle", "empty-handle"].contains(scenario) ? 0 : 1))
    }

    @Test(arguments: ["duplicate", "foreign", "empty"])
    func ambiguousForeignOrEmptyMatchingCredentialsFailClosed(_ scenario: String) async throws {
        let first = metadata(
            id: scenario == "empty" ? Foundation.Data() : Foundation.Data([1]),
            cipher: scenario == "foreign" ? "other" : "cipher-1"
        )
        let credentials = scenario == "duplicate" ? [first, first] : [first]
        let store = SDKAutoFillFidoCredentialStore(
            views: [view],
            userID: "user-1",
            readAccess: {},
            checkAccess: {},
            metadata: { _ in credentials }
        )
        await #expect(throws: SDKAutoFillFidoError.accessDenied) { try await store.findCredentials(
            ids: nil,
            ripId: "example.com",
            userHandle: nil
        ) }
    }

    @Test(arguments: ["decode", "lock"])
    func metadataOrLateAuthorizationFailureCannotBecomeAnEmptyFallback(_ scenario: String) async throws {
        let access = PasskeyRecoveryAccessFixture(), credential = metadata()
        let store = SDKAutoFillFidoCredentialStore(views: [view], userID: "user-1", readAccess: { try access.check() }, checkAccess: { try access.check(
        ) }, metadata: { _ in
            if scenario == "decode" { throw PasskeyRecoveryFixtureError.storage }
            access.revoke(); return [credential]
        })
        await #expect(throws: (any Error).self) { try await store.findCredentials(
            ids: nil,
            ripId: "example.com",
            userHandle: nil
        ) }
    }

    @Test(arguments: ["readonly", "foreign", "protected", "valid", "late-lock"])
    func callbackSaveRequiresOwnerPolicyAndProofButNotPostCommitOriginalCache(_ scenario: String) async throws {
        let access = PasskeyRecoveryAccessFixture()
        let save: @Sendable (SDKAutoFillEncryptedCipher) async throws -> Void = { cipher in
            #expect(cipher.id == "cipher-1" && String(describing: cipher) == "SDKAutoFillEncryptedCipher(<redacted>)")
            access.project(AutoFillQuerySourceFixture.dto("saved"))
            if scenario == "late-lock" { access.revoke() }
        }
        let store = SDKAutoFillFidoCredentialStore(
            views: [view],
            userID: "user-1",
            readAccess: { Issue.record("Save must not reread its old cache UUID") },
            checkAccess: { try access.check() },
            metadata: { _ in [] },
            save: scenario == "readonly" ? nil : save
        )
        var dto = AutoFillQuerySourceFixture.dto("cipher-1")
        if scenario == "protected" { dto.reprompt = 1 }
        let context = EncryptionContext(
            encryptedFor: scenario == "foreign" ? "other" : "user-1",
            cipher: try dto.toSDKCipher()
        )
        if scenario == "valid" { try await store.saveCredential(cred: context) }
        else { await #expect(throws: (any Error).self) { try await store.saveCredential(cred: context) } }
        #expect(access.projectionCount == (["valid", "late-lock"].contains(scenario) ? 1 : 0))
    }

    @Test(arguments: [Verification.discouraged, .preferred, .required])
    func userVerificationDoesNotFabricateVerifiedStatus(_ requirement: Verification) async throws {
        let verification = FidoVerificationFixture(result: false)
        let result = try await ui(verification: verification).checkUser(
            options: CheckUserOptions(requirePresence: true, requireVerification: requirement),
            hint: .requestExistingCredential(AutoFillQuerySourceFixture.view(hasPasskeys: true))
        )
        #expect(result.userPresent && !result.userVerified)
        #expect(verification.calls == (requirement == .discouraged ? 0 : 1))
    }

    @Test(arguments: ["lock", "cancel"])
    func lateVerificationResultCannotOutliveProofOrCaller(_ scenario: String) async throws {
        let gate = AuthOperationTestGate(), access = PasskeyRecoveryAccessFixture(), verification = FidoVerificationFixture(
            gate: gate
        )
        let callback = ui(verification: verification, access: access), hint = UiHint.requestExistingCredential(
            AutoFillQuerySourceFixture.view()
        )
        let task = Task { try await callback.checkUser(
            options: CheckUserOptions(requirePresence: true, requireVerification: .required),
            hint: hint
        ) }
        await gate.waitUntilPaused()
        if scenario == "lock" { access.revoke() } else { task.cancel() }
        await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!callback.isVerificationEnabled() || scenario == "cancel")
    }

    @Test(arguments: ["one", "none", "multiple", "foreign", "protected"])
    func authenticationSelectionIsExactlyOneScopedCurrentCandidate(_ scenario: String) async throws {
        let candidate = AutoFillQuerySourceFixture.view(
            id: scenario == "foreign" ? "other" : "cipher-1",
            reprompt: scenario == "protected" ? .password : .none
        )
        let available = scenario == "none" ? [] : (scenario == "multiple" ? [candidate, candidate] : [candidate])
        if scenario == "one" {
            let selected = try await ui().pickCredentialForAuthentication(availableCredentials: available)
            #expect(selected.cipher.id == "cipher-1")
        } else { await #expect(throws: SDKAutoFillFidoError.ambiguousSelection) { try await ui().pickCredentialForAuthentication(
            availableCredentials: available
        ) } }
    }

    @Test(arguments: ["existing", "new", "foreign-rp", "readonly"])
    func creationRechecksTargetPolicyAndExactRequestedRP(_ scenario: String) async throws {
        let target = scenario == "new" ? SDKAutoFillService.newPasskeyTarget(
            relyingPartyIdentifier: "example.com",
            userName: "user"
        ) :
            SDKAutoFillCredentialView(legacyView: .fixture(edit: scenario != "readonly"))
        let newCredential = Fido2CredentialNewView(
            credentialId: "synthetic-id",
            keyType: "public-key",
            keyAlgorithm: "ECDSA",
            keyCurve: "P-256",
            rpId: scenario == "foreign-rp" ? "other.example.com" : "example.com",
            userHandle: "synthetic-handle",
            userName: "user",
            counter: "0",
            rpName: nil,
            userDisplayName: nil,
            creationDate: .distantPast
        )
        if ["existing", "new"].contains(scenario) {
            let result = try await ui(target: target).checkUserAndPickCredentialForCreation(
                options: CheckUserOptions(requirePresence: true, requireVerification: .preferred),
                newCredential: newCredential
            )
            #expect(result.cipher.cipher.id == target.id && result.checkUserResult.userVerified)
        } else { await #expect(throws: SDKAutoFillFidoError.accessDenied) { try await ui(target: target).checkUserAndPickCredentialForCreation(
            options: CheckUserOptions(requirePresence: true, requireVerification: .preferred),
            newCredential: newCredential
        ) } }
    }
}

final class FidoVerificationFixture: PasskeyUserVerifying, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    let available: Bool
    let result: Bool
    let gate: AuthOperationTestGate?
    let failure: PasskeyUserVerificationError?
    init(
        available: Bool = true,
        result: Bool = true,
        gate: AuthOperationTestGate? = nil,
        failure: PasskeyUserVerificationError? = nil
    ) {
        self.available = available; self.result = result; self.gate = gate
        self.failure = failure
    }

    var calls: Int { lock.withLock { count } }
    func isVerificationAvailable() -> Bool { available }
    func verify(reason: String) async throws -> Bool {
        lock.withLock { count += 1 }
        await gate?.pause()
        if let failure { throw failure }
        return result
    }
}
