@testable import Data
import Domain
import Foundation
import Testing

@Suite
struct CredentialIdentityPublisherTests {
    @Test
    func mapperPublishesDeduplicatedDomainIdentitiesOnlyForExplicitlyEligibleURIs() {
        let source = VaultLoginIdentitySource(
            cipherID: CipherID(rawValue: "login"), displayName: "Login", username: "alice",
            serviceIdentifiers: ["https://strict.example.org/path"], hasOneTimeCode: true, passkeys: [],
            isEligibleForAutoFill: true,
            domainMatchingURIs: ["https://login.example.com", "https://example.com/path", "https://alice.github.io"]
        )
        let identities = CredentialIdentityMapper.makeIdentities(from: [source])
        #expect(identities.count == 4)
        #expect(Set(identities.map(\.serviceIdentifier)) == ["example.com", "alice.github.io"])
        #expect(identities.filter { $0.kind == .password }.count == 2)
        #expect(identities.filter { $0.kind == .oneTimeCode }.count == 2)
    }

    @Test
    func mapperPublishesOnlyPasskeysWithoutSecretsUntilURLScopeCanBeProven() {
        let source = VaultLoginIdentitySource(
            cipherID: CipherID(rawValue: "cipher-1"),
            displayName: "Example account",
            username: "alice",
            serviceIdentifiers: ["https://example.com", "https://example.com", ""],
            hasOneTimeCode: true,
            passkeys: [PasskeyIdentitySource(
                relyingPartyIdentifier: "example.com",
                userName: nil,
                credentialID: Foundation.Data([1, 2]),
                userHandle: Foundation.Data([3])
            )],
            isEligibleForAutoFill: true
        )

        let identities = CredentialIdentityMapper.makeIdentities(from: [source])

        #expect(identities.map(\.kind) == [.passkey])
        #expect(identities.filter { $0.kind == .passkey }.first?.credentialID == Foundation.Data([1, 2]))
        #expect(identities.allSatisfy { $0.recordIdentifier == CipherID(rawValue: "cipher-1") })
    }

    @Test
    func mapperExcludesIneligibleAndMalformedSuggestionSources() {
        let excluded = VaultLoginIdentitySource(
            cipherID: CipherID(rawValue: "excluded"), displayName: "Excluded", username: "user",
            serviceIdentifiers: ["https://example.com"], hasOneTimeCode: true, passkeys: [],
            isEligibleForAutoFill: false
        )
        let malformed = VaultLoginIdentitySource(
            cipherID: CipherID(rawValue: "malformed"), displayName: "Malformed", username: nil,
            serviceIdentifiers: [""], hasOneTimeCode: true,
            passkeys: [
                PasskeyIdentitySource(
                    relyingPartyIdentifier: "",
                    userName: nil,
                    credentialID: Foundation.Data(),
                    userHandle: nil
                ),
            ],
            isEligibleForAutoFill: true
        )

        #expect(CredentialIdentityMapper.makeIdentities(from: [excluded, malformed]).isEmpty)
    }

    @Test
    func publisherUsesTheSameRevisionAsTheCommittedProjection() async throws {
        let store = RecordingIdentityStore()
        let publisher = CredentialIdentityPublisher(
            store: store,
            identityMutations: IdentityMutationTestCoordinator(),
            checkProjection: { _ in },
            checkClearAccess: {}
        )
        let identities = [identity()]

        let health = await publisher.publish(
            revision: 5,
            identities: identities,
            projectionHealth: .current(revision: 5)
        )

        #expect(health == .current(revision: 5))
        let published = try #require(store.published.first)
        #expect(store.published.count == 1)
        #expect(published.0 == identities)
        #expect(published.1 == 5)
    }

    @Test
    func staleProjectionNeverPublishesNewSystemIdentities() async {
        let store = RecordingIdentityStore()
        let publisher = CredentialIdentityPublisher(
            store: store,
            identityMutations: IdentityMutationTestCoordinator(),
            checkProjection: { _ in },
            checkClearAccess: {}
        )

        let health = await publisher.publish(
            revision: 5,
            identities: [identity()],
            projectionHealth: .stale(lastSuccessfulRevision: 4)
        )

        #expect(health == .unavailable)
        #expect(store.published.isEmpty)
    }

    @Test
    func publisherFailureIsVisibleWithoutChangingProjectionOutcome() async {
        let store = RecordingIdentityStore()
        store.replaceError = TestIdentityStoreError.replaceFailed
        let publisher = CredentialIdentityPublisher(
            store: store,
            identityMutations: IdentityMutationTestCoordinator(),
            checkProjection: { _ in },
            checkClearAccess: {}
        )

        let health = await publisher.publish(
            revision: 3,
            identities: [identity()],
            projectionHealth: .current(revision: 3)
        )

        #expect(health == .unavailable)
        #expect(store.published.isEmpty)
    }

    @Test
    func lockRemovesAllSystemIdentities() async {
        let store = RecordingIdentityStore()
        let publisher = CredentialIdentityPublisher(
            store: store,
            identityMutations: IdentityMutationTestCoordinator(),
            checkProjection: { _ in },
            checkClearAccess: {}
        )
        _ = await publisher.publish(revision: 1, identities: [identity()], projectionHealth: .current(revision: 1))

        let health = await publisher.lock()

        #expect(health == .unavailable)
        #expect(store.removeAllCalls == 1)
    }

    @Test
    func lockDrainsALateOSReplacementBeforeRemovingIdentities() async throws {
        let store = SuspendedIdentityStore()
        let publisher = CredentialIdentityPublisher(
            store: store,
            identityMutations: IdentityMutationTestCoordinator(),
            checkProjection: { _ in },
            checkClearAccess: {}
        )
        let replacement = Task { await publisher.publish(
            revision: 1,
            identities: [identity()],
            projectionHealth: .current(revision: 1)
        ) }
        await store.waitUntilReplacing()
        let lock = Task { await publisher.lock() }
        for _ in 0 ..< 200 {
            if await publisher.isClosed { break }
            await Task.yield()
        }
        #expect(await publisher.isClosed)
        #expect(await store.events == ["replace-started"])
        await store.finishReplacement()
        _ = await replacement.value; _ = await lock.value
        #expect(await store.events == ["replace-started", "replace-finished", "clear"])
        #expect(await publisher.currentHealth() == .unavailable)
        _ = await publisher.publish(revision: 2, identities: [identity()], projectionHealth: .current(revision: 2))
        #expect(await store.events.count == 3)
    }

    @Test
    func routineClearDoesNotPermanentlyClosePublication() async {
        let store = RecordingIdentityStore(); let publisher = CredentialIdentityPublisher(
            store: store,
            identityMutations: IdentityMutationTestCoordinator(),
            checkProjection: { _ in },
            checkClearAccess: {}
        )
        _ = await publisher.publish(revision: 1, identities: [identity()], projectionHealth: .current(revision: 1))
        _ = await publisher.clear()
        #expect(
            await publisher.publish(revision: 2, identities: [identity()], projectionHealth: .current(revision: 2)) == .current(
                revision: 2
            )
        )
        #expect(store.published.count == 2)
    }

    private func identity() -> CredentialIdentityDescriptor {
        CredentialIdentityDescriptor(
            id: "identity", kind: .password, serviceIdentifier: "https://example.com", user: "alice",
            label: nil, credentialID: nil, userHandle: nil, recordIdentifier: CipherID(rawValue: "cipher-1")
        )
    }
}

private actor SuspendedIdentityStore: CredentialIdentityPublishing {
    private var started = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var events: [String] = []
    func replaceCredentialIdentities(_ identities: [CredentialIdentityDescriptor], revision: UInt64) async {
        events.append("replace-started"); started = true
        waiters.forEach { $0.resume() }; waiters.removeAll()
        await withCheckedContinuation { continuation = $0 }
        events.append("replace-finished")
    }

    func removeAllCredentialIdentities() { events.append("clear") }
    func waitUntilReplacing() async { if !started { await withCheckedContinuation { waiters.append($0) } } }
    func finishReplacement() { continuation?.resume(); continuation = nil }
}

private enum TestIdentityStoreError: Error {
    case replaceFailed
}

private final class RecordingIdentityStore: CredentialIdentityPublishing, @unchecked Sendable {
    var published: [([CredentialIdentityDescriptor], UInt64)] = []
    var replaceError: Error?
    private(set) var removeAllCalls = 0

    func replaceCredentialIdentities(_ identities: [CredentialIdentityDescriptor], revision: UInt64) async throws {
        if let replaceError { throw replaceError }
        published.append((identities, revision))
    }

    func removeAllCredentialIdentities() async throws {
        removeAllCalls += 1
    }
}
