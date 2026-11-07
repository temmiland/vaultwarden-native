import AppFeature
import Data
import Domain
import Foundation
import Networking
import XCTest

@MainActor
final class CompositionIntegrationTests: XCTestCase {
    func testFirstRunUsesRealAuthAssemblyWithoutNetworkOrOwnerStorage() async throws {
        let fixture = try IntegrationAssembly()
        defer { fixture.cleanUp() }
        guard case .serverSetup = try await fixture.composition.authCommands.restore() else {
            return XCTFail("First run must offer server setup")
        }
        let snapshot = await fixture.composition.authRepository.currentSnapshot()
        XCTAssertEqual(snapshot.state, .signedOut)
        let model = fixture.composition.makeModel()
        await model.start()
        await waitUntil("First run publishes signed out") { model.state.isSignedOut }
        let requests = await fixture.http.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertNil(try fixture.store.loadSession())
        XCTAssertTrue(fixture.files.events.isEmpty, "No authenticated file session without a handoff")
    }

    func testReturningAccountRestoresStoredIdentityLockedWithoutUnlockOrNetwork() async throws {
        let fixture = try IntegrationAssembly()
        defer { fixture.cleanUp() }
        let saved = try fixture.saveReturningAccount()
        let account = try fixture.account
        guard case let .returningUnlock(commands) = try await fixture.composition.authCommands.restore() else {
            return XCTFail("A committed account must restore to its returning unlock route")
        }
        XCTAssertEqual(commands.account.session, account)
        XCTAssertEqual(commands.account.email, "synthetic@example.invalid")
        XCTAssertFalse(commands.account.isBiometricUnlockEnabled)
        let snapshot = await fixture.composition.authRepository.currentSnapshot()
        XCTAssertEqual(snapshot.state, .locked(account), "Displaying unlock must not begin an unlock")
        XCTAssertNil(snapshot.sessionID)

        let model = fixture.composition.makeModel()
        await model.start()
        await waitUntil("Restore publishes the stored account as locked") { model.state.lockedAccount == account }
        XCTAssertNil(model.session)
        XCTAssertEqual(try fixture.store.loadSession()?.scope, saved.scope)
        let requests = await fixture.http.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(fixture.files.events.isEmpty)
        await commands.revoke()
    }

    func testConcreteHandoffPublishesMatchingRepositorySessionThenLockRevokesIt() async throws {
        let fixture = try IntegrationAssembly()
        defer { fixture.cleanUp() }
        try await fixture.beginReturningUnlock()
        let session = try fixture.session()
        let model = fixture.composition.makeModel()
        await model.start()
        await fixture.composition.accept(session, into: model)
        XCTAssertEqual(model.session?.id, session.id)
        let unlocked = await fixture.composition.authRepository.currentSnapshot()
        XCTAssertEqual(unlocked.state, .unlocked(session.account))
        XCTAssertEqual(unlocked.sessionID, session.id)
        XCTAssertEqual(fixture.files.events, ["prepare", "prepared"])
        await model.lockNow()
        XCTAssertNil(model.session)
        XCTAssertEqual(model.state.lockedAccount, session.account)
        XCTAssertThrowsError(try session.checkAccess())
        XCTAssertNotNil(try fixture.store.loadSession(), "Lock must retain the stored account")
        let locked = await fixture.composition.authRepository.currentSnapshot()
        XCTAssertEqual(locked.state, .locked(session.account))
        XCTAssertNil(locked.sessionID)
        XCTAssertEqual(fixture.files.events, ["prepare", "prepared", "cleanup"])
    }

    func testDuplicateAndCompetingHandoffsKeepExactlyOneRuntimeOwner() async throws {
        let fixture = try IntegrationAssembly()
        defer { fixture.cleanUp() }
        try await fixture.beginReturningUnlock()
        let owner = try fixture.session()
        let model = fixture.composition.makeModel()
        await model.start()
        await fixture.composition.accept(owner, into: model)
        let unlocked = await fixture.composition.authRepository.currentSnapshot()
        XCTAssertEqual(unlocked.sessionID, owner.id)

        // A repeated delivery of the adopted capability is idempotent, not a second preparation.
        await fixture.composition.accept(owner, into: model)
        XCTAssertEqual(model.session?.id, owner.id)
        XCTAssertNoThrow(try owner.checkAccess())

        // A different runtime for the same account must not replace or share ownership.
        let competing = try fixture.session()
        await fixture.composition.accept(competing, into: model)
        XCTAssertThrowsError(try competing.checkAccess(), "The refused runtime must be retired")
        XCTAssertEqual(model.session?.id, owner.id)
        XCTAssertNoThrow(try owner.checkAccess())
        let after = await fixture.composition.authRepository.currentSnapshot()
        XCTAssertEqual(after, unlocked, "Neither delivery may re-run repository completion")
        XCTAssertEqual(fixture.files.events, ["prepare", "prepared"])
        await model.logOut()
    }

    func testRevokedHandoffCannotReopenApp() async throws {
        let fixture = try IntegrationAssembly()
        defer { fixture.cleanUp() }
        try await fixture.beginReturningUnlock()
        let session = try fixture.session()
        await session.revoke(.lock)
        let model = fixture.composition.makeModel()
        await model.start()
        await fixture.composition.accept(session, into: model)
        XCTAssertNil(model.session)
        XCTAssertEqual(model.state.lockedAccount, session.account)
        XCTAssertEqual(model.securityErrorMessage, "Couldn't prepare the unlocked session. Authenticate again.")
        let snapshot = await fixture.composition.authRepository.currentSnapshot()
        XCTAssertEqual(snapshot.state, .locked(session.account))
        XCTAssertNil(snapshot.sessionID)
        XCTAssertNotNil(try fixture.store.loadSession(), "A refused handoff locks; it does not log out")
    }

    func testLockDuringSessionPreparationWaitsForPreparationAndNeverPublishesLateRuntime() async throws {
        try await assertSecurityActionDuringPreparation(.lock)
    }

    func testLogoutDuringSessionPreparationWaitsForPreparationAndNeverPublishesLateRuntime() async throws {
        try await assertSecurityActionDuringPreparation(.logout)
    }

    func testPreparationFailureUnlocksWithFileRecoveryMessageOnly() async throws {
        let files = IntegrationFileLifecycle()
        files.failPreparation(true)
        let fixture = try IntegrationAssembly(files: files)
        defer { fixture.cleanUp() }
        try await fixture.beginReturningUnlock()
        let session = try fixture.session()
        let model = fixture.composition.makeModel()
        await model.start()
        await fixture.composition.accept(session, into: model)
        // The vault opens, but the unprepared file store keeps rejecting work until cleanup.
        XCTAssertEqual(model.session?.id, session.id)
        XCTAssertEqual(
            model.securityErrorMessage,
            "Couldn't prepare secure attachment storage. Attachment files will stay unavailable until cleanup succeeds."
        )
        let snapshot = await fixture.composition.authRepository.currentSnapshot()
        XCTAssertEqual(snapshot.sessionID, session.id)
        await model.lockNow()
        XCTAssertEqual(fixture.files.events, ["prepare", "prepared", "cleanup"])
    }

    func testCleanupFailureKeepsRevokedRuntimeInRecoveryUntilRetrySucceeds() async throws {
        let files = IntegrationFileLifecycle()
        let fixture = try IntegrationAssembly(files: files)
        defer { fixture.cleanUp() }
        try await fixture.beginReturningUnlock()
        let session = try fixture.session()
        let model = fixture.composition.makeModel()
        await model.start()
        await fixture.composition.accept(session, into: model)
        XCTAssertEqual(model.session?.id, session.id)

        files.failCleanup(true)
        await model.lockNow()
        XCTAssertEqual(model.state.recoveryAction, .lock)
        XCTAssertEqual(model.pendingSecurityAction, .lock)
        XCTAssertEqual(
            model.securityErrorMessage,
            "Sensitive attachment files couldn't be removed. Retry secure cleanup before unlocking again."
        )
        XCTAssertNil(model.session)
        XCTAssertThrowsError(try session.checkAccess())
        let locked = await fixture.composition.authRepository.currentSnapshot()
        XCTAssertEqual(locked.state, .locked(session.account))
        XCTAssertNil(locked.sessionID)

        // Neither the old capability nor a fresh one may reopen over unfinished cleanup.
        await fixture.composition.accept(session, into: model)
        let fresh = try fixture.session()
        await fixture.composition.accept(fresh, into: model)
        XCTAssertThrowsError(try fresh.checkAccess())
        XCTAssertEqual(model.state.recoveryAction, .lock)
        XCTAssertNil(model.session)

        files.failCleanup(false)
        await model.retrySecurityAction()
        XCTAssertEqual(model.state.lockedAccount, session.account)
        XCTAssertNil(model.pendingSecurityAction)
        XCTAssertNil(model.securityErrorMessage)
        XCTAssertEqual(files.events, ["prepare", "prepared", "cleanup", "cleanup"])
    }

    func testLogoutClearsConcreteStorageAndRetainedRepositoriesStayClosed() async throws {
        let fixture = try IntegrationAssembly()
        defer { fixture.cleanUp() }
        let session = try fixture.session()
        let model = fixture.composition.makeModel()
        await fixture.composition.accept(session, into: model)
        let adapter = try XCTUnwrap(model.session)
        await model.logOut()
        XCTAssertNil(try fixture.store.loadSession())
        XCTAssertNil(model.session)
        XCTAssertTrue(model.state.isSignedOut)
        do {
            try await adapter.vaultRepository.sync()
            XCTFail("A retained vault repository must not issue requests after logout")
        } catch is CancellationError {}
        do {
            _ = try await adapter.sendRepository.load()
            XCTFail("A retained send repository must not issue requests after logout")
        } catch is CancellationError {} // the revoked runtime refuses before the closed repository
        let snapshot = await adapter.vaultRepository.currentSnapshot()
        XCTAssertTrue(snapshot.items.isEmpty)
        let requests = await fixture.http.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testComposedVaultTransportPreservesProxyRouteAndDoesNotPublishFailedSync() async throws {
        let fixture = try IntegrationAssembly()
        defer { fixture.cleanUp() }
        let model = fixture.composition.makeModel()
        let session = try fixture.session()
        await fixture.composition.accept(session, into: model)
        let adapter = try XCTUnwrap(model.session)
        do {
            try await adapter.vaultRepository.sync()
            XCTFail("503 must not become a successful sync")
        } catch let error as HTTPStatusError { XCTAssertEqual(error.statusCode, 503) }
        let requests = await fixture.http.requests
        XCTAssertEqual(requests.count, 1, "A failed sync must not be retried implicitly")
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url.absoluteString, "https://vault.example.invalid/proxy/api/sync?excludeDomains=true")
        XCTAssertEqual(request.headers["Authorization"], "Bearer synthetic-access")
        let snapshot = await adapter.vaultRepository.currentSnapshot()
        XCTAssertTrue(snapshot.items.isEmpty)
        XCTAssertTrue(snapshot.isStale)
        await model.logOut()
    }

    private func assertSecurityActionDuringPreparation(_ action: AppModelSecurityAction) async throws {
        let files = IntegrationFileLifecycle()
        let gate = IntegrationGate()
        files.holdPreparation(at: gate)
        let fixture = try IntegrationAssembly(files: files)
        defer {
            gate.open()
            fixture.cleanUp()
        }
        try await fixture.beginReturningUnlock()
        let account = try fixture.account
        let session = try fixture.session()
        let model = fixture.composition.makeModel()
        await model.start()
        let repositoryStates = await fixture.composition.authRepository.sessionStates()
        let repositoryClosed = XCTestExpectation(description: "Repository applied the security action")
        let expectedTransition: AuthSessionTransition = action == .lock ? .locked : .loggedOut
        let watcher = Task {
            for await snapshot in repositoryStates where snapshot.transition == expectedTransition {
                repositoryClosed.fulfill()
                return
            }
        }
        defer { watcher.cancel() }

        let handoff = Task { await fixture.composition.accept(session, into: model) }
        await fulfillment(of: [gate.entered], timeout: 5)
        guard case .preparingSession = model.state else { return XCTFail("Handoff must be preparing") }
        let security = Task {
            if action == .lock { await model.lockNow() } else { await model.logOut() }
        }
        await fulfillment(of: [repositoryClosed], timeout: 5)

        // The runtime is already revoked and hidden while preparation is still running.
        XCTAssertEqual(model.state.recoveryAction, action)
        XCTAssertNil(model.session)
        XCTAssertThrowsError(try session.checkAccess())
        XCTAssertEqual(files.events, ["prepare"], "Final cleanup must wait for the running preparation")

        gate.open()
        await handoff.value
        await security.value
        XCTAssertEqual(files.events, ["prepare", "prepared", "cleanup"])
        XCTAssertNil(model.session, "The late preparation must not reopen the app")
        XCTAssertNil(model.pendingSecurityAction)
        XCTAssertNil(model.securityErrorMessage)
        let snapshot = await fixture.composition.authRepository.currentSnapshot()
        XCTAssertNil(snapshot.sessionID)
        switch action {
        case .lock:
            XCTAssertEqual(model.state.lockedAccount, account)
            XCTAssertEqual(snapshot.state, .locked(account))
            XCTAssertNotNil(try fixture.store.loadSession())
        case .logout:
            XCTAssertTrue(model.state.isSignedOut)
            XCTAssertEqual(snapshot.state, .signedOut)
            XCTAssertNil(try fixture.store.loadSession())
        }
    }
}

extension AppModelState {
    var isSignedOut: Bool {
        if case .signedOut = self { return true }
        return false
    }

    var lockedAccount: AccountSession? {
        if case let .locked(account) = self { return account }
        return nil
    }

    var recoveryAction: AppModelSecurityAction? {
        if case let .securityRecovery(action) = self { return action }
        return nil
    }
}
