@testable import Data
import Domain
import Foundation
import Testing

@Suite
struct SessionPinUnlockSettingsTests {
    private struct Fixture {
        let store: AuthCredentialStore
        let keychain: AuthKeychainFixture
        let saved: PersistedAuthSession
        let runtime: SessionRuntime
    }

    private func fixture() throws -> Fixture {
        let keychain = AuthKeychainFixture()
        let store = AuthCredentialStore(
            keychain: keychain,
            sharedKeychain: AuthKeychainFixture(),
            sharedLockPolicy: .processOnly
        )
        let saved = try store.saveSession(
            account: .fixture(),
            tokens: TokenPair(
                accessToken: "fixture-access",
                refreshToken: "fixture-refresh",
                expiresAt: .distantFuture
            )
        )
        let provider = try store.makeTokenProvider(
            identityURL: saved.account.serverBaseURL.appendingPathComponent("identity"),
            restoringAccount: saved.account,
            expectedScope: saved.scope,
            tokenService: AuthRefreshFixture()
        )
        let runtime = SessionRuntime(
            account: try AccountSession(storedAccount: saved.account),
            resource: AuthResourceFixture(),
            tokens: provider
        )
        return Fixture(store: store, keychain: keychain, saved: saved, runtime: runtime)
    }

    @Test
    func enrollReadAndRemoveUseTheSameStoreWithoutPersistingThePIN() async throws {
        let f = try fixture()
        let calls = AuthInvocationProbe()
        let settings = SessionPinUnlockSettings(runtime: f.runtime, store: f.store) { pin in
            #expect(pin == "fixture-pin")
            await calls.record()
            return "fixture-protected-key"
        }
        #expect(try await !settings.isEnabled())
        try await settings.enroll(pin: "fixture-pin")
        #expect(try await settings.isEnabled())
        #expect(try f.store.readPinProtectedUserKey(requiringScope: f.saved.scope) == "fixture-protected-key")
        #expect(try f.store.pinFailureCount() == 0)
        #expect(try f.store.loadSession()?.tokens == f.saved.tokens)
        #expect(await calls.count == 1)
        try await settings.remove()
        #expect(try await !settings.isEnabled())
        #expect(try f.store.readPinProtectedUserKey() == nil)
        #expect(try f.store.loadSession()?.scope == f.saved.scope)
    }

    @Test
    func aCryptoFailureCannotEnablePINOrChangeTheCredentialRecord() async throws {
        let f = try fixture()
        let settings = SessionPinUnlockSettings(runtime: f.runtime, store: f.store) { _ in
            throw AuthFixtureError.operationFailed
        }
        await #expect(throws: AuthFixtureError.self) { try await settings.enroll(pin: "fixture-pin") }
        try f.store.expectPersistedSession(f.saved)
        #expect(try f.store.readPinProtectedUserKey() == nil)
    }

    @Test(arguments: ["runtime", "epoch", "lineage"])
    func aLateNoncooperativeDerivationCannotEnrollAfterRevocation(_ transition: String) async throws {
        let f = try fixture()
        let gate = AuthOperationTestGate()
        let settings = SessionPinUnlockSettings(runtime: f.runtime, store: f.store) { _ in
            await gate.pause()
            return "fixture-late-protected-key"
        }
        let task = Task { try await settings.enroll(pin: "fixture-pin") }
        await gate.waitUntilPaused()
        switch transition {
        case "runtime": await f.runtime.revoke(.lock)
        case "epoch": try f.store.lockSession()
        default:
            try f.store.saveSession(
                account: .fixture(),
                tokens: TokenPair(
                    accessToken: "fixture-new-access",
                    refreshToken: "fixture-new-refresh",
                    expiresAt: .distantFuture
                )
            )
        }
        let current = try #require(try f.store.loadSession())
        await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        try f.store.expectPersistedSession(current)
        #expect(try f.store.readPinProtectedUserKey() == nil)
        #expect(try f.store.pinFailureCount() == 0)
    }

    @Test
    func failedCounterPersistenceRollsBackTheDerivedKey() async throws {
        let f = try fixture()
        f.keychain.accountsFailingWrites = ["auth.pinFailureCount"]
        let settings = SessionPinUnlockSettings(runtime: f.runtime, store: f.store) { _ in "fixture-protected-key" }
        await #expect(throws: AuthFixtureError.self) { try await settings.enroll(pin: "fixture-pin") }
        #expect(try f.store.readPinProtectedUserKey() == nil)
        try f.store.expectPersistedSession(f.saved)
    }

    @Test(arguments: ["runtime", "epoch", "lineage"])
    func aRevokedSettingsConsumerCannotInspectOrRemoveCurrentEnrollment(_ transition: String) async throws {
        let f = try fixture()
        let settings = SessionPinUnlockSettings(runtime: f.runtime, store: f.store) { _ in "fixture-protected-key" }
        try await settings.enroll(pin: "fixture-pin")
        switch transition {
        case "runtime": await f.runtime.revoke(.lock)
        case "epoch": try f.store.lockSession()
        default:
            let current = try f.store.saveSession(
                account: .fixture(),
                tokens: TokenPair(
                    accessToken: "fixture-new-access",
                    refreshToken: "fixture-new-refresh",
                    expiresAt: .distantFuture
                )
            )
            try f.store.enrollPinProtectedUserKey(
                "fixture-current-key",
                requiringScope: current.scope,
                publicationEpoch: f.store.autofillPublicationEpoch()
            )
        }
        let before = try #require(try f.store.loadSession())
        let key = try f.store.readPinProtectedUserKey()
        await #expect(throws: CancellationError.self) { try await settings.isEnabled() }
        await #expect(throws: CancellationError.self) { try await settings.remove() }
        #expect(try f.store.readPinProtectedUserKey() == key)
        try f.store.expectPersistedSession(before)
    }

    @Test
    func atomicEnrollmentAndRemovalRejectAnEpochCapturedBeforeLock() throws {
        let f = try fixture()
        let epoch = try f.store.autofillPublicationEpoch()
        try f.store.enrollPinProtectedUserKey(
            "fixture-current-key",
            requiringScope: f.saved.scope,
            publicationEpoch: epoch
        )
        try f.store.lockSession()
        #expect(throws: CancellationError.self) {
            try f.store.enrollPinProtectedUserKey(
                "fixture-stale-key",
                requiringScope: f.saved.scope,
                publicationEpoch: epoch
            )
        }
        #expect(throws: CancellationError.self) {
            try f.store.removePinUnlock(requiringScope: f.saved.scope, publicationEpoch: epoch)
        }
        #expect(try f.store.readPinProtectedUserKey() == "fixture-current-key")
        #expect(try f.store.loadSession()?.account.isPinUnlockEnabled == true)
    }

    @Test
    func aCancelledConsumerCannotStartDerivationOrPersistKeys() async throws {
        let f = try fixture()
        let gate = AuthOperationTestGate()
        let calls = AuthInvocationProbe()
        let settings = SessionPinUnlockSettings(runtime: f.runtime, store: f.store) { _ in
            await calls.record()
            return "fixture-protected-key"
        }
        let task = Task { await gate.pause(); try await settings.enroll(pin: "fixture-pin") }
        await gate.waitUntilPaused()
        task.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await calls.count == 0)
        try f.store.expectPersistedSession(f.saved)
        #expect(try f.store.readPinProtectedUserKey() == nil)
    }
}
