import BitwardenSDKAdapter
@testable import Data
import Domain
import Foundation
import Testing

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct ReturningUnlockServiceTests {
    @Test
    func leftoverBiometricKeyCannotAuthorizeADisabledEnrollment() async throws {
        let fixture = try ReturningFlowFixture()
        try fixture.store.saveBiometricUserKey("leftover-fixture-key")
        guard case .rejected(.biometricNotSetup(_, cleanupFailed: false)) = await fixture.commands.unlock(
            using: .biometric
        )
        else { Issue.record("Disabled enrollment was used"); return }
        #expect(fixture.biometric.evaluations == 0)
        #expect(await fixture.crypto.calls.isEmpty)
        #expect(try fixture.store.loadAccount()?.isBiometricUnlockEnabled == false)
    }

    @Test
    func cancellationReportedByBeginUnlockReconcilesTheRequestedTransition() async throws {
        let fixture = try ReturningFlowFixture(beginCancelled: true)
        guard case .cancelled = await fixture.commands.unlock(using: .password("fixture-password"))
        else { Issue.record("Expected cancelled transition"); return }
        #expect(await fixture.begin.count == 1)
        #expect(await fixture.failed.count == 1)
        #expect(await fixture.crypto.calls.isEmpty)
    }

    @Test(arguments: ["password", "pin", "biometric"])
    func eachReturningMethodPublishesAutoFillAndTransfersOneResource(_ method: String) async throws {
        let fixture = try ReturningFlowFixture(method: method)
        _ = fixture.commands.availability()
        guard case let .unlocked(pending, offer) = await fixture.commands.unlock(using: fixture.request(method))
        else { Issue.record("Expected pending unlock"); return }
        #expect(offer == (method != "biometric"))
        #expect(await fixture.crypto.calls == [method])
        #expect(fixture.store.loadSharedAutofillUserKeyForTesting() == "returning-decrypted-key")
        #expect(await fixture.begin.count == 1)
        #expect(await fixture.failed.count == 0)
        await fixture.commands.revoke()
        try await pending.validateAuthorization() // old route retirement must not kill successor
        let session = try await PendingAuthSession.prepareHandoff(pending, onExpired: { _ in })
        await session.revoke(.lock)
        #expect(!fixture.crypto.resource.isActive)
    }

    @Test(arguments: ["password", "pin", "biometric"])
    func lockDuringNoncooperativeCryptoPreventsPublicationAndCounterMutation(_ method: String) async throws {
        let gate = AuthOperationTestGate()
        let fixture = try ReturningFlowFixture(method: method, cryptoGate: gate)
        if method == "pin" { _ = try fixture.store.recordPinFailure(requiringScope: fixture.scope) }
        let operation = Task { await fixture.commands.unlock(using: fixture.request(method)) }
        await gate.waitUntilPaused()
        try fixture.store.lockSession()
        await gate.release()
        guard case .cancelled = await operation.value else { Issue.record("Expected stale unlock denial"); return }
        #expect(fixture.store.loadSharedAutofillUserKeyForTesting() == nil)
        if method == "pin" { #expect(try fixture.store.pinUnlockState(requiringScope: fixture.scope).failureCount == 1) }
        #expect(!fixture.crypto.resource.isActive)
        #expect(await fixture.failed.count == 1)
    }

    @Test
    func lateNonCancellationPINFailureAfterLockConsumesNoAttempt() async throws {
        let gate = AuthOperationTestGate()
        let fixture = try ReturningFlowFixture(method: "pin", cryptoGate: gate, fails: true)
        let operation = Task { await fixture.commands.unlock(using: .pin("1234")) }
        await gate.waitUntilPaused()
        try fixture.store.lockSession()
        await gate.release()
        guard case .cancelled = await operation.value else { Issue.record("Expected silent cancellation"); return }
        #expect(try fixture.store.pinUnlockState(requiringScope: fixture.scope).failureCount == 0)
        #expect(try fixture.store.readPinProtectedUserKey(requiringScope: fixture.scope) != nil)
    }

    @Test(arguments: ["password", "pin", "biometric"])
    func cancellationDuringCryptoLeavesNoActiveCandidate(_ method: String) async throws {
        let gate = AuthOperationTestGate()
        let fixture = try ReturningFlowFixture(method: method, cryptoGate: gate)
        let operation = Task { await fixture.commands.unlock(using: fixture.request(method)) }
        await gate.waitUntilPaused()
        operation.cancel()
        await gate.release()
        guard case .cancelled = await operation.value else { Issue.record("Expected cancellation"); return }
        #expect(!fixture.crypto.resource.isActive)
        #expect(fixture.store.loadSharedAutofillUserKeyForTesting() == nil)
        #expect(await fixture.failed.count == 1)
    }

    @Test
    func revokingDuringBeginUnlockPreventsPlatformPromptAndResourceCreation() async throws {
        let gate = AuthOperationTestGate()
        let fixture = try ReturningFlowFixture(method: "biometric", beginGate: gate)
        let operation = Task { await fixture.commands.unlock(using: .biometric) }
        await gate.waitUntilPaused()
        await fixture.commands.revoke()
        await gate.release()
        guard case .cancelled = await operation.value else { Issue.record("Expected revocation"); return }
        #expect(fixture.biometric.evaluations == 0)
        #expect(await fixture.crypto.calls.isEmpty)
        #expect(await fixture.failed.count == 1)
    }

    @Test
    func unavailableBiometryArrivingAfterLockCannotClearAnEnrollment() async throws {
        let gate = AuthOperationTestGate()
        let fixture = try ReturningFlowFixture(method: "biometric")
        fixture.biometric.gate = gate
        fixture.biometric.evaluationResult = .unavailable(.notEnrolled)
        let operation = Task { await fixture.commands.unlock(using: .biometric) }
        await gate.waitUntilPaused()
        try fixture.store.lockSession()
        await gate.release()
        guard case .cancelled = await operation.value else { Issue.record("Expected stale OS response denial"); return }
        #expect(try fixture.store.loadAccount()?.isBiometricUnlockEnabled == true)
        #expect(try fixture.store.readBiometricUserKey(requiringScope: fixture.scope) != nil)
        #expect(await fixture.crypto.calls.isEmpty)
    }

    @Test
    func changedAccountDuringCryptoCannotDisableOrOverwriteTheReplacement() async throws {
        let gate = AuthOperationTestGate()
        let fixture = try ReturningFlowFixture(method: "pin", cryptoGate: gate, fails: true)
        let operation = Task { await fixture.commands.unlock(using: .pin("1234")) }
        await gate.waitUntilPaused()
        var account = StoredAuthAccount.fixture(userID: "replacement")
        account.isPinUnlockEnabled = true
        let replacement = try fixture.store.saveSession(
            account: account,
            tokens: TokenPair(
                accessToken: "new-access",
                refreshToken: "new-refresh",
                expiresAt: .distantFuture
            )
        )
        try fixture.store.savePinProtectedUserKey("replacement-protected-key")
        await gate.release()
        guard case .cancelled = await operation.value else { Issue.record("Expected lineage denial"); return }
        try fixture.store.expectPersistedSession(replacement)
        #expect(
            try fixture.store.readPinProtectedUserKey(requiringScope: replacement.scope) == "replacement-protected-key"
        )
        #expect(try fixture.store.pinUnlockState(requiringScope: replacement.scope).failureCount == 0)
    }

    @Test
    func exhaustedPersistentPINBudgetIsCheckedEvenWithoutAvailabilityRendering() async throws {
        let fixture = try ReturningFlowFixture(method: "pin")
        for _ in 0 ..< AuthCredentialStore.maxPinAttempts { _ = try fixture.store.recordPinFailure(
            requiringScope: fixture.scope
        ) }
        guard case .rejected(.pinLimit(cleanupConfirmed: true, atAppearance: false)) = await fixture.commands.unlock(
            using: .pin("1234")
        )
        else { Issue.record("Expected persisted budget denial"); return }
        #expect(await fixture.crypto.calls.isEmpty)
        #expect(try fixture.store.loadAccount()?.isPinUnlockEnabled == false)
        #expect(try fixture.store.readPinProtectedUserKey(requiringScope: fixture.scope) == nil)
    }

    @Test
    func acceptedPINWhoseResetWriteFailsCannotPublishOrHandOff() async throws {
        let fixture = try ReturningFlowFixture(method: "pin")
        fixture.keychain.accountsFailingWrites = ["auth.pinFailureCount"]
        guard case .rejected(.pinResetFailed(cleanupConfirmed: true)) = await fixture.commands.unlock(
            using: .pin("1234")
        )
        else { Issue.record("Expected reset recovery"); return }
        #expect(!fixture.crypto.resource.isActive)
        #expect(fixture.store.loadSharedAutofillUserKeyForTesting() == nil)
        #expect(try fixture.store.loadAccount()?.isPinUnlockEnabled == false)
        #expect(await fixture.failed.count == 1)
    }

    @Test
    func counterAndCleanupFailuresAreDistinctFromAnIncorrectPIN() async throws {
        let fixture = try ReturningFlowFixture(method: "pin", fails: true)
        fixture.keychain.accountsFailingWrites = ["auth.pinFailureCount", PrivateAuthSessionStore.key]
        fixture.keychain.accountsFailingRemoval = ["auth.pinProtectedUserKey"]
        guard case let .rejected(failure) = await fixture.commands.unlock(using: .pin("1234"))
        else { Issue.record("Expected fail-closed rejection"); return }
        #expect(failure == .pinCounterFailed(cleanupConfirmed: false))
        #expect(failure.localizedDescription.contains("do not retry PIN unlock"))
        #expect(!fixture.commands.account.isPinUnlockEnabled)
        #expect(fixture.store.loadSharedAutofillUserKeyForTesting() == nil)
    }

    @Test
    func lockDuringBestEffortPublicationDeniesTheFinalHandoff() async throws {
        let gate = AuthOperationTestGate()
        let fixture = try ReturningFlowFixture(keyGate: gate)
        let operation = Task { await fixture.commands.unlock(using: .password("fixture-password")) }
        await gate.waitUntilPaused()
        try fixture.store.lockSession()
        await gate.release()
        guard case .cancelled = await operation.value else { Issue.record("Expected final denial"); return }
        #expect(!fixture.crypto.resource.isActive)
        #expect(fixture.store.loadSharedAutofillUserKeyForTesting() == nil)
    }

    @Test(arguments: ["counter", "reset", "pin-cleanup", "biometric-cleanup"])
    func everyReturningMutationChecksItsCapturedEpochInsideTheWriteTransaction(_ operation: String) throws {
        let fixture = try ReturningFlowFixture(method: "pin")
        try fixture.store.saveBiometricUserKey("fixture-biometric-key")
        let epoch = try fixture.store.returningUnlockEpoch(requiringScope: fixture.scope)
        _ = try fixture.store.recordPinFailure(requiringScope: fixture.scope)
        try fixture.store.lockSession()
        #expect(throws: CancellationError.self) {
            switch operation {
            case "counter": _ = try fixture.store.recordPinFailure(
                    requiringScope: fixture.scope,
                    publicationEpoch: epoch
                )
            case "reset": try fixture.store.resetPinFailureCount(requiringScope: fixture.scope, publicationEpoch: epoch)
            case "pin-cleanup": _ = try fixture.store.disablePinUnlock(
                    requiringScope: fixture.scope,
                    publicationEpoch: epoch
                )
            default: try fixture.store.disableBiometricUnlock(requiringScope: fixture.scope, publicationEpoch: epoch)
            }
        }
        #expect(try fixture.store.pinUnlockState(requiringScope: fixture.scope).failureCount == 1)
        #expect(try fixture.store.readPinProtectedUserKey(requiringScope: fixture.scope) != nil)
        #expect(try fixture.store.readBiometricUserKey(requiringScope: fixture.scope) != nil)
    }
}
