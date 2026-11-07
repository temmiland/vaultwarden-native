import AutoFillContract
import AutoFillData
import Data
import Domain
import Foundation
@testable import SecurityStorage
import Testing

@Suite
struct CoordinatedCredentialIdentityTests {
    @Test
    func lateIncrementalCompensationPrecedesNewFullPublicationOfSameIdentity() async throws {
        let fixture = try PasskeyProjectionCacheFixture(), gate = AuthOperationTestGate(), waiting = IdentityMutationContentionProbe(
        )
        defer { try? fixture.cleanup() }
        let store = CoordinatedIdentityStoreFixture(addGate: gate)
        let projection = fixture.projection(identities: store, identityMutations: Self.coordinator(fixture))
        let add = Task { try await Self.project(projection) }
        await gate.waitUntilPaused()
        try fixture.edit { $0.revision = UUID(); $0.projectionRevision = 19 }
        let publisher = Self.publisher(fixture, store: store, coordinator: Self.coordinator(fixture, waiting: waiting))
        let replace = Task { await publisher.publish(
            revision: 19,
            identities: [PasskeyProjectionCacheFixture.identity()],
            projectionHealth: .current(revision: 19)
        ) }
        await waiting.wait()
        #expect(await store.events == ["add-start"])
        await gate.release()
        await #expect(throws: CancellationError.self) { try await add.value }
        #expect(await replace.value == .current(revision: 19))
        #expect(await store.events == ["add-start", "add-finish", "remove-one", "replace-start", "replace-finish"])
        #expect(await store.entries == [PasskeyProjectionCacheFixture.identity()])
    }

    @Test
    func lockClearDrainsExtensionAddAndItsCompensationBeforeClearing() async throws {
        let fixture = try PasskeyProjectionCacheFixture(), gate = AuthOperationTestGate(), waiting = IdentityMutationContentionProbe(
        )
        defer { try? fixture.cleanup() }
        let store = CoordinatedIdentityStoreFixture(addGate: gate)
        let add = Task { try await Self.project(
            fixture.projection(identities: store, identityMutations: Self.coordinator(fixture))
        ) }
        await gate.waitUntilPaused(); fixture.authorization.revoke()
        let publisher = Self.publisher(fixture, store: store, coordinator: Self.coordinator(fixture, waiting: waiting))
        let clear = Task { await publisher.lock() }
        await waiting.wait()
        #expect(await store.events == ["add-start"])
        await gate.release()
        await #expect(throws: CancellationError.self) { try await add.value }
        #expect(await clear.value == .unavailable)
        #expect(await store.events == ["add-start", "add-finish", "remove-one", "clear"])
        #expect(await store.entries.isEmpty)
    }

    @Test
    func oldAppReplacementCannotClaimCurrentAfterIncrementalCacheCommitWhileWaiting() async throws {
        let fixture = try PasskeyProjectionCacheFixture(), gate = AuthOperationTestGate(), waiting = IdentityMutationContentionProbe(
        )
        defer { try? fixture.cleanup() }
        let store = CoordinatedIdentityStoreFixture(replaceGate: gate)
        let publisher = Self.publisher(fixture, store: store, coordinator: Self.coordinator(fixture))
        let replace = Task { await publisher.publish(
            revision: 17,
            identities: [],
            projectionHealth: .current(revision: 17)
        ) }
        await gate.waitUntilPaused()
        let projection = fixture.projection(
            identities: store,
            identityMutations: Self.coordinator(fixture, waiting: waiting)
        )
        let add = Task { try await Self.project(projection) }
        await waiting.wait()
        #expect(try fixture.store.read()?.projectionRevision == 18)
        #expect(await store.events == ["replace-start"])
        await gate.release()
        #expect(await replace.value == .unavailable)
        try await add.value
        #expect(await store.events == ["replace-start", "replace-finish", "clear", "add-start", "add-finish"])
        #expect(await store.entries == [PasskeyProjectionCacheFixture.identity()])
    }

    @Test
    func incrementalWaiterRechecksReceiptBeforeAnyOSCall() async throws {
        let fixture = try PasskeyProjectionCacheFixture(), gate = AuthOperationTestGate(), waiting = IdentityMutationContentionProbe(
        )
        defer { try? fixture.cleanup() }
        let owner = Self.coordinator(fixture), store = CoordinatedIdentityStoreFixture()
        let holding = Task { try await owner.withExclusiveMutation { await gate.pause() } }
        await gate.waitUntilPaused()
        let projection = fixture.projection(
            identities: store,
            identityMutations: Self.coordinator(fixture, waiting: waiting)
        )
        let add = Task { try await Self.project(projection) }
        await waiting.wait()
        try fixture.edit { $0.revision = UUID() }
        await gate.release(); try await holding.value
        await #expect(throws: CancellationError.self) { try await add.value }
        #expect(await store.events.isEmpty)
        #expect(await store.entries == [PasskeyProjectionCacheFixture.identity(id: "existing")])
    }

    static func coordinator(_ fixture: PasskeyProjectionCacheFixture, waiting: IdentityMutationContentionProbe? = nil) -> FileIdentityMutationTestCoordinator {
        FileIdentityMutationTestCoordinator(
            lock: AsyncCrossProcessFileLock(
                containerURL: fixture.directory,
                filename: ".identities.lock",
                waitingLimit: .seconds(10),
                onContention: { waiting?.record() }
            )
        )
    }

    static func publisher(
        _ fixture: PasskeyProjectionCacheFixture,
        store: CoordinatedIdentityStoreFixture,
        coordinator: any CredentialIdentityMutationCoordinating
    ) -> CredentialIdentityPublisher {
        CredentialIdentityPublisher(store: store, identityMutations: coordinator, checkProjection: { revision in
            try fixture.authorization.check()
            let loaded = try fixture.store.read()
            let cache = try #require(loaded)
            try AutoFillIdentityMutationPolicy.requirePublication(cache: cache, proof: fixture.proof, revision: revision)
        }, checkClearAccess: {}) // revoked fixture grant permits clear; policy separately tested
    }

    private static func project(_ projection: PasskeyRegistrationProjection) async throws {
        try await projection.project(
            AutoFillQuerySourceFixture.dto("saved"),
            credentialID: Foundation.Data([1]),
            relyingPartyIdentifier: "example.com",
            makeIdentity: { _ in PasskeyProjectionCacheFixture.identity() }
        )
    }
}

actor CoordinatedIdentityStoreFixture: CredentialIdentityPublishing, PasskeyIdentityUpdating {
    private(set) var events: [String] = []
    private(set) var entries = [PasskeyProjectionCacheFixture.identity(id: "existing")]
    private var failReplace = false, failClear = false
    let addGate: AuthOperationTestGate?, replaceGate: AuthOperationTestGate?
    init(addGate: AuthOperationTestGate? = nil, replaceGate: AuthOperationTestGate? = nil) { self.addGate = addGate; self.replaceGate = replaceGate }
    func failures(replace: Bool, clear: Bool) { failReplace = replace; failClear = clear }
    func addPasskeyIdentity(_ identity: CredentialIdentityDescriptor) async throws {
        events.append("add-start"); entries.append(identity)
        await addGate?.pause(); events.append("add-finish")
    }

    func removePasskeyIdentity(_ identity: CredentialIdentityDescriptor) async throws {
        events.append("remove-one"); entries.removeAll { $0 == identity }
    }

    func replaceCredentialIdentities(_ identities: [CredentialIdentityDescriptor], revision: UInt64) async throws {
        events.append("replace-start"); await replaceGate?.pause()
        entries = identities; events.append("replace-finish")
        if failReplace { throw PasskeyRecoveryFixtureError.storage }
    }

    func removeAllCredentialIdentities() async throws {
        events.append("clear")
        if failClear { throw PasskeyRecoveryFixtureError.storage }
        entries = []
    }
}
