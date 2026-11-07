import BitwardenSDKAdapter
@testable import Data
import Domain
import Foundation
import Testing

/// Production orchestration with real in-memory credential transactions, opaque no-handle
/// resources and controlled suspension points. No SDK crypto, OS Keychain, network or sleeps.
@MainActor
@Suite
struct PasswordSignInServiceTests {
    @Test
    func freshLoginNormalizesEmailCommitsCanonicalAccountAndPublishesOnlyExplicitly() async throws {
        let fixture = PasswordFlowFixture(outcomes: [.success(try passwordTokenResponse())])
        guard case let .unlocked(pending) = try await fixture.signIn() else { Issue.record("Expected unlock"); return }
        #expect(await fixture.probe.calls == [.prelogin, .hash, .token, .unlock])
        #expect(await fixture.crypto.hashEmail == "fixture@example.com")
        #expect(await fixture.crypto.unlockPassword == "fixture-password")
        let requests = await fixture.tokens.requests
        #expect(requests.count == 1 && requests[0].email == "fixture@example.com")
        #expect(requests[0].hash == "fixture-hash" && requests[0].twoFactor == nil)
        let saved = try #require(try fixture.store.loadSession())
        #expect(saved.account.userId == "fixture-user" && saved.account.email == pending.account.email)
        #expect(saved.account.kdfType == 0 && saved.account.kdfIterations == 600_000)
        #expect(fixture.store.loadSharedAutofillUserKeyForTesting() == nil)
        try await pending.validateAuthorization()
        await pending.publishAutoFillUnlock()
        #expect(fixture.store.loadSharedAutofillUserKeyForTesting() == "fixture-decrypted-key")
        #expect(fixture.store.loadSharedAccountInfoForTesting()?.kdfIterations == 600_000)
        await pending.revoke()
        #expect(!fixture.crypto.resource.isActive)
    }

    @Test
    func TOTPAllowsRetryTransfersAuthorityAndLateChallengeRevocationCannotKillItsSuccessor() async throws {
        let fixture = PasswordFlowFixture(outcomes: [.twoFactorRequired(providers: [0, 1]),
                                                     .twoFactorRequired(providers: [0]),
                                                     .success(try passwordTokenResponse())])
        guard case let .twoFactorRequired(challenge) = try await fixture.signIn() else { Issue.record(
            "Expected challenge"
        ); return }
        #expect(challenge.availableProviders == [0, 1])
        #expect(try fixture.store.loadSession() == nil)
        guard case .rejected(.invalidTwoFactor) = try await challenge.submitTOTP(code: "111111", remember: false)
        else { Issue.record("Expected retryable code rejection"); return }
        guard case let .unlocked(pending) = try await challenge.submitTOTP(code: " 222222 ", remember: true)
        else { Issue.record("Expected unlock"); return }
        #expect(pending.id == challenge.id)
        let requests = await fixture.tokens.requests
        #expect(
            requests.count == 3 && requests[2].twoFactor == TwoFactorSubmission(
                code: "222222",
                provider: 0,
                remember: true
            )
        )
        let session = try await PendingAuthSession.prepareHandoff(pending, onExpired: { _ in })
        await challenge.revoke() // includes UI retirement during forward navigation
        try await pending.validateAuthorization()
        try session.checkAccess()
        await #expect(throws: CancellationError.self) { _ = try await challenge.submitTOTP(
            code: "333333",
            remember: false
        ) }
        #expect(await fixture.tokens.requests.count == 3)
        await session.revoke(.lock)
    }

    @Test(arguments: [[1], [7], []])
    func unsupportedProvidersCannotAccidentallySubmitAnAuthenticatorCode(_ providers: [Int]) async throws {
        let fixture = PasswordFlowFixture(outcomes: [.twoFactorRequired(providers: providers)])
        guard case let .twoFactorRequired(challenge) = try await fixture.signIn() else { Issue.record(
            "Expected challenge"
        ); return }
        guard case .rejected(.invalidTwoFactor) = try await challenge.submitTOTP(code: "123456", remember: true)
        else { Issue.record("Unsupported provider was submitted"); return }
        #expect(await fixture.tokens.requests.count == 1)
        await challenge.revoke()
    }

    @Test
    func concurrentTOTPSubmissionDoesNotDuplicateTheGrant() async throws {
        let fixture = PasswordFlowFixture(
            outcomes: [.twoFactorRequired(providers: [0]), .twoFactorRequired(providers: [0])]
        )
        guard case let .twoFactorRequired(challenge) = try await fixture.signIn() else { Issue.record(
            "Expected challenge"
        ); return }
        let gate = AuthOperationTestGate()
        await fixture.tokens.pauseNextRequest(at: gate)
        let submission = Task { try await challenge.submitTOTP(code: "123456", remember: false) }
        await gate.waitUntilPaused()
        await #expect(throws: AuthRepositoryError.invalidTransition) { _ = try await challenge.submitTOTP(
            code: "654321",
            remember: true
        ) }
        await gate.release()
        _ = try await submission.value
        #expect(await fixture.tokens.requests.count == 2)
        await challenge.revoke()
    }

    @Test
    func lockedChallengeIsDeniedBeforeSendingAnotherCode() async throws {
        let fixture = PasswordFlowFixture(outcomes: [.twoFactorRequired(providers: [0])])
        guard case let .twoFactorRequired(challenge) = try await fixture.signIn() else { Issue.record(
            "Expected challenge"
        ); return }
        try fixture.store.lockSession()
        await #expect(throws: CancellationError.self) { _ = try await challenge.submitTOTP(
            code: "123456",
            remember: false
        ) }
        #expect(await fixture.tokens.requests.count == 1)
        #expect(try fixture.store.loadSession() == nil)
        await challenge.revoke()
    }

    @Test
    func challengeRevocationDuringNonCooperativeTokenRequestPreventsCryptoAndCommit() async throws {
        let fixture = PasswordFlowFixture(
            outcomes: [.twoFactorRequired(providers: [0]), .success(try passwordTokenResponse())]
        )
        guard case let .twoFactorRequired(challenge) = try await fixture.signIn() else { Issue.record(
            "Expected challenge"
        ); return }
        let gate = AuthOperationTestGate()
        await fixture.tokens.pauseNextRequest(at: gate)
        let submission = Task { try await challenge.submitTOTP(code: "123456", remember: false) }
        await gate.waitUntilPaused()
        await challenge.revoke()
        await gate.release()
        await #expect(throws: CancellationError.self) { _ = try await submission.value }
        #expect(await fixture.probe.calls == [.prelogin, .hash, .token, .token])
        #expect(try fixture.store.loadSession() == nil)
        #expect(!fixture.crypto.resource.isActive)
    }

    @Test(arguments: PasswordFlowStage.allCases)
    func cancellationAfterEverySuspendedStageDeniesAllLaterWorkAndCommit(_ stage: PasswordFlowStage) async throws {
        let gate = AuthOperationTestGate()
        let fixture = PasswordFlowFixture(
            outcomes: [.success(try passwordTokenResponse())],
            pausedStage: stage,
            gate: gate
        )
        let signIn = Task { try await fixture.signIn() }
        await gate.waitUntilPaused()
        signIn.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { _ = try await signIn.value }
        let index = try #require(PasswordFlowStage.allCases.firstIndex(of: stage))
        #expect(await fixture.probe.calls == Array(PasswordFlowStage.allCases.prefix(index + 1)))
        #expect(try fixture.store.loadSession() == nil)
        if stage != .prelogin { #expect(!fixture.crypto.resource.isActive) }
    }

    @Test(arguments: PasswordFlowStage.allCases)
    func lockWhileLoginIsSuspendedInvalidatesEvenAnUnchangedAccountLineage(_ stage: PasswordFlowStage) async throws {
        let gate = AuthOperationTestGate()
        let fixture = PasswordFlowFixture(
            outcomes: [.success(try passwordTokenResponse())],
            pausedStage: stage,
            gate: gate
        )
        let saved = try fixture.store.saveSession(
            account: .fixture(),
            tokens: TokenPair(
                accessToken: "old-access",
                refreshToken: "old-refresh",
                expiresAt: .distantFuture
            )
        )
        let signIn = Task { try await fixture.signIn() }
        await gate.waitUntilPaused()
        try fixture.store.lockSession()
        await gate.release()
        await #expect(throws: CancellationError.self) { _ = try await signIn.value }
        try fixture.store.expectPersistedSession(saved)
        #expect(fixture.store.loadSharedAutofillUserKeyForTesting() == nil)
    }

    @Test(arguments: PasswordFlowStage.allCases)
    func replacingTheAccountWhileLoginIsSuspendedPreservesTheNewSession(_ stage: PasswordFlowStage) async throws {
        let gate = AuthOperationTestGate()
        let fixture = PasswordFlowFixture(
            outcomes: [.success(try passwordTokenResponse())],
            pausedStage: stage,
            gate: gate
        )
        let signIn = Task { try await fixture.signIn() }
        await gate.waitUntilPaused()
        let replacement = try fixture.store.saveSession(
            account: .fixture(userID: "replacement"),
            tokens: TokenPair(accessToken: "new-access", refreshToken: "new-refresh", expiresAt: .distantFuture)
        )
        await gate.release()
        await #expect(throws: CancellationError.self) { _ = try await signIn.value }
        try fixture.store.expectPersistedSession(replacement)
    }

    /// Ported from AuthFeature: this assertion belongs to the production Data credential flow.
    @Test(arguments: [-1, 1, 2])
    func badTokenKDFMetadataIsRejectedBeforeCryptoOrSessionCommit(_ type: Int) async throws {
        let fixture = PasswordFlowFixture(outcomes: [.success(try passwordTokenResponse(kdf: type))])
        await #expect(throws: AuthFlowError.invalidEncryptionParameters) { _ = try await fixture.signIn() }
        #expect(await fixture.probe.calls == [.prelogin, .hash, .token])
        #expect(try fixture.store.loadSession() == nil)
        #expect(!fixture.crypto.resource.isActive)
    }

    @Test(arguments: ["empty-subject", "empty-refresh", "invalid-expiry", "empty-user-key"])
    func incompleteTokenResponsesCannotReachSDKUnlockOrPersistence(_ variant: String) async throws {
        let response = try passwordTokenResponse(
            subject: variant == "empty-subject" ? "" : "fixture-user",
            refresh: variant == "empty-refresh" ? "" : "fixture-refresh",
            expires: variant == "invalid-expiry" ? 0 : 3600,
            userKey: variant == "empty-user-key" ? "" : "wrapped-user"
        )
        let fixture = PasswordFlowFixture(outcomes: [.success(response)])
        await #expect(throws: AuthFlowError.self) { _ = try await fixture.signIn() }
        #expect(await fixture.probe.calls == [.prelogin, .hash, .token])
        #expect(try fixture.store.loadSession() == nil)
        #expect(!fixture.crypto.resource.isActive)
    }

    @Test
    func unknownWireDiagnosticsDoNotEscapeIntoDomainRejectionText() async throws {
        let secret = "secret-password/token/raw-server-diagnostic"
        let fixture = PasswordFlowFixture(outcomes: [.failure(message: secret)])
        guard case let .rejected(reason) = try await fixture.signIn() else { Issue.record("Expected rejection"); return }
        #expect(reason == .failed && !reason.localizedDescription.contains(secret))
        #expect(try fixture.store.loadSession() == nil && !fixture.crypto.resource.isActive)
    }

    @Test(arguments: [false, true])
    func pendingKeyOperationCannotPublishOrEnrollAfterLock(_ biometric: Bool) async throws {
        let gate = AuthOperationTestGate()
        let fixture = PasswordFlowFixture(outcomes: [.success(try passwordTokenResponse())], keyGate: gate)
        guard case let .unlocked(pending) = try await fixture.signIn() else { Issue.record("Expected unlock"); return }
        let operation = Task { if biometric { try await pending.enableBiometricUnlock() } else { await pending.publishAutoFillUnlock(
        ) } }
        await gate.waitUntilPaused()
        try fixture.store.lockSession()
        await gate.release()
        if biometric { await #expect(throws: CancellationError.self) { try await operation.value } }
        else { try await operation.value }
        #expect(fixture.store.loadSharedAutofillUserKeyForTesting() == nil)
        #expect(try fixture.store.loadAccount()?.isBiometricUnlockEnabled == false)
        await pending.revoke()
    }

    @Test
    func pendingCapabilityCanPrepareOnlyOneRuntimeAndSharesItsRevocationBoundary() async throws {
        let fixture = PasswordFlowFixture(outcomes: [.success(try passwordTokenResponse())])
        guard case let .unlocked(pending) = try await fixture.signIn() else { Issue.record("Expected unlock"); return }
        let session = try await PendingAuthSession.prepareHandoff(pending, onExpired: { _ in })
        await #expect(throws: AuthRepositoryError.invalidTransition) {
            _ = try await PendingAuthSession.prepareHandoff(pending, onExpired: { _ in })
        }
        try session.checkAccess()
        #expect(String(reflecting: pending) == "PendingAuthSession(<redacted>)")
        await session.revoke(.lock)
        await #expect(throws: CancellationError.self) { try await pending.validateAuthorization() }
        #expect(!fixture.crypto.resource.isActive)
    }

    @Test
    func failedHandoffRevokesTheCandidateEvenBeforeRuntimeConstruction() async throws {
        let fixture = PasswordFlowFixture(outcomes: [.success(try passwordTokenResponse())])
        guard case let .unlocked(pending) = try await fixture.signIn() else { Issue.record("Expected unlock"); return }
        try fixture.store.lockSession()
        await #expect(throws: CancellationError.self) { _ = try await PendingAuthSession.prepareHandoff(
            pending,
            onExpired: { _ in }
        ) }
        #expect(!fixture.crypto.resource.isActive)
        await #expect(throws: AuthRepositoryError.invalidTransition) {
            _ = try await PendingAuthSession.prepareHandoff(pending, onExpired: { _ in })
        }
    }

    @Test
    func preparedHandoffInstallsExpiryBeforeSessionEscapesAndRevokesTheSameResource() async throws {
        let fixture = PasswordFlowFixture(outcomes: [.success(try passwordTokenResponse())])
        guard case let .unlocked(pending) = try await fixture.signIn() else { Issue.record("Expected unlock"); return }
        let signal = PasswordExpirySignal()
        let session = try await PendingAuthSession.prepareHandoff(pending, onExpired: { await signal.receive($0) })
        _ = try fixture.store.save(
            tokens: TokenPair(accessToken: "expired-access", refreshToken: "fixture-refresh", expiresAt: .distantPast)
        )
        #expect(await session.runtime.getAccessToken() == nil)
        #expect(await signal.waitForExpiry() == session.id)
        #expect(!fixture.crypto.resource.isActive)
        #expect(throws: CancellationError.self) { try session.checkAccess() }
    }
}

private actor PasswordExpirySignal {
    private var value: UUID?
    private var continuation: CheckedContinuation<UUID, Never>?
    func receive(_ id: UUID) { value = id; continuation?.resume(returning: id); continuation = nil }
    func waitForExpiry() async -> UUID {
        if let value { return value }
        return await withCheckedContinuation { continuation = $0 }
    }
}
