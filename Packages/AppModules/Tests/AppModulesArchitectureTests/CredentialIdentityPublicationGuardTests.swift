import AutoFillData
import Data
import Domain
import Foundation
import SecurityStorage
import Testing

@Suite
struct CredentialIdentityPublicationGuardTests {
    @Test
    func staleAuthorizationBeforePublishDoesNotTouchOSIndex() async throws {
        let store = CoordinatedIdentityStoreFixture(), access = PasskeyRecoveryAccessFixture()
        access.revoke()
        let publisher = CredentialIdentityPublisher(
            store: store,
            identityMutations: IdentityMutationTestCoordinator(),
            checkProjection: { _ in try access.check() },
            checkClearAccess: { Issue.record("Pre-write guard must not compensate") }
        )
        #expect(
            await publisher.publish(revision: 1, identities: [], projectionHealth: .current(revision: 1)) == .unavailable
        )
        #expect(await store.events.isEmpty)
        #expect(await store.entries.count == 1)
    }

    @Test
    func lateCacheInvalidationClearsUncertainReplacementAndNeverClaimsCurrent() async throws {
        let store = CoordinatedIdentityStoreFixture(replaceGate: AuthOperationTestGate()), access = PasskeyRecoveryAccessFixture(
        )
        let publisher = CredentialIdentityPublisher(
            store: store,
            identityMutations: IdentityMutationTestCoordinator(),
            checkProjection: { _ in try access.check() },
            checkClearAccess: {}
        )
        let task = Task { await publisher.publish(
            revision: 1,
            identities: [PasskeyProjectionCacheFixture.identity()],
            projectionHealth: .current(revision: 1)
        ) }
        guard let gate = store.replaceGate else { Issue.record("Missing gate"); return }
        await gate.waitUntilPaused(); access.revoke(); await gate.release()
        #expect(await task.value == .unavailable)
        #expect(await store.events == ["replace-start", "replace-finish", "clear"])
        #expect(await store.entries.isEmpty)
    }

    @Test
    func retiredUnlockClearCannotRemoveSuccessorSuggestions() async throws {
        let store = CoordinatedIdentityStoreFixture(), access = PasskeyRecoveryAccessFixture()
        let publisher = CredentialIdentityPublisher(
            store: store,
            identityMutations: IdentityMutationTestCoordinator(),
            checkProjection: { _ in },
            checkClearAccess: { try access.check() }
        )
        #expect(
            await publisher.publish(
                revision: 1,
                identities: [PasskeyProjectionCacheFixture.identity()],
                projectionHealth: .current(revision: 1)
            ) == .current(revision: 1)
        )
        access.revoke() // the injected grant check now sees a successor unlock
        #expect(await publisher.lock() == .stale(lastSuccessfulRevision: 1))
        #expect(await store.events == ["replace-start", "replace-finish"])
        #expect(await store.entries == [PasskeyProjectionCacheFixture.identity()])
    }

    @Test
    func unavailableSharedCoordinatorNeverFallsBackToOSWritesOrClear() async throws {
        let store = CoordinatedIdentityStoreFixture()
        let publisher = CredentialIdentityPublisher(
            store: store,
            identityMutations: UnavailableIdentityCoordinator(),
            checkProjection: { _ in },
            checkClearAccess: {}
        )
        #expect(
            await publisher.publish(revision: 1, identities: [], projectionHealth: .current(revision: 1)) == .unavailable
        )
        #expect(await publisher.clear() == .unavailable)
        #expect(await store.events.isEmpty)
        #expect(await store.entries.count == 1)
    }

    @Test(arguments: [false, true])
    func ambiguousReplaceAndCleanupFailureStayVisibleAsStale(_ failClear: Bool) async throws {
        let store = CoordinatedIdentityStoreFixture()
        let publisher = CredentialIdentityPublisher(
            store: store,
            identityMutations: IdentityMutationTestCoordinator(),
            checkProjection: { _ in },
            checkClearAccess: {}
        )
        #expect(
            await publisher.publish(revision: 1, identities: [], projectionHealth: .current(revision: 1)) == .current(
                revision: 1
            )
        )
        await store.failures(replace: true, clear: failClear)
        #expect(
            await publisher.publish(
                revision: 2,
                identities: [PasskeyProjectionCacheFixture.identity()],
                projectionHealth: .current(revision: 2)
            ) == .stale(lastSuccessfulRevision: 1)
        )
        #expect(await store.events == ["replace-start", "replace-finish", "replace-start", "replace-finish", "clear"])
        #expect(await store.entries.count == (failClear ? 1 : 0))
    }
}

private struct UnavailableIdentityCoordinator: CredentialIdentityMutationCoordinating {
    func withExclusiveMutation(_ operation: @escaping @Sendable () async throws -> Void) async throws {
        throw CrossProcessFileLockError.missingContainer
    }
}
