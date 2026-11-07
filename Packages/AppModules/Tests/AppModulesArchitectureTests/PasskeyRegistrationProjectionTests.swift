import AutoFillContract
import AutoFillData
import Domain
import Foundation
import Testing

@Suite
struct PasskeyRegistrationProjectionTests {
    @Test
    func encryptedCacheCommitPrecedesSingleIncrementalPublication() async throws {
        let fixture = try PasskeyProjectionCacheFixture(), identities = PasskeyIdentityProbe()
        defer { try? fixture.cleanup() }
        try await fixture.projection(identities: identities).project(
            AutoFillQuerySourceFixture.dto("saved"),
            credentialID: Foundation.Data([1]),
            relyingPartyIdentifier: "example.com",
            makeIdentity: { _ in
                let cache = try #require(
                    try fixture.store.read()
                )
                #expect(
                    cache.ciphers.map(\.id) == [
                        "existing",
                        "saved",
                    ]
                )
                #expect(
                    cache.revision != fixture.originalRevision && cache.projectionRevision == 18
                )
                #expect(await identities.added.isEmpty)
                return PasskeyProjectionCacheFixture.identity()
            }
        )
        #expect(await identities.added == [PasskeyProjectionCacheFixture.identity()])
        #expect(await identities.removed.isEmpty)
        #expect(await identities.entries.count == 2)
    }

    @Test(arguments: ["lock", "cache"])
    func invalidationDuringMetadataAwaitNeverTouchesSystemIndex(_ failure: String) async throws {
        let fixture = try PasskeyProjectionCacheFixture(), identities = PasskeyIdentityProbe(), gate = AuthOperationTestGate(
        )
        defer { try? fixture.cleanup() }
        let projection = fixture.projection(identities: identities)
        let task = Task { try await projection.project(
            AutoFillQuerySourceFixture.dto("saved"),
            credentialID: Foundation.Data([1]),
            relyingPartyIdentifier: "example.com",
            makeIdentity: { _ in await gate.pause(); return PasskeyProjectionCacheFixture.identity() }
        ) }
        await gate.waitUntilPaused()
        if failure == "lock" { fixture.authorization.revoke() } else { try fixture.edit { $0.revision = UUID() } }
        await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await identities.added.isEmpty)
        #expect(await identities.removed.isEmpty)
    }

    @Test(arguments: ["lock", "cache"])
    func invalidationDuringSystemAwaitRemovesOnlyNewIdentity(_ failure: String) async throws {
        let fixture = try PasskeyProjectionCacheFixture(), gate = AuthOperationTestGate()
        defer { try? fixture.cleanup() }
        let identities = PasskeyIdentityProbe(gate: gate), projection = fixture.projection(identities: identities)
        let task = Task { try await projection.project(
            AutoFillQuerySourceFixture.dto("saved"),
            credentialID: Foundation.Data([1]),
            relyingPartyIdentifier: "example.com",
            makeIdentity: { _ in PasskeyProjectionCacheFixture.identity() }
        ) }
        await gate.waitUntilPaused()
        if failure == "lock" { fixture.authorization.revoke() } else { try fixture.edit { $0.projectionRevision = 19 } }
        await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await identities.removed == [PasskeyProjectionCacheFixture.identity()])
        #expect(await identities.entries.map(\.recordIdentifier.rawValue) == ["existing"])
    }

    @Test(arguments: [false, true])
    func uncertainAddFailureIsCompensatedAndCleanupFailureIsExplicit(_ failRemove: Bool) async throws {
        let fixture = try PasskeyProjectionCacheFixture(), identities = PasskeyIdentityProbe(
            failAdd: true,
            failRemove: failRemove
        )
        defer { try? fixture.cleanup() }
        do {
            try await fixture.projection(identities: identities).project(
                AutoFillQuerySourceFixture.dto("saved"),
                credentialID: Foundation.Data([1]),
                relyingPartyIdentifier: "example.com",
                makeIdentity: { _ in PasskeyProjectionCacheFixture.identity() }
            )
            Issue.record("Expected failed identity publication")
        } catch {
            if failRemove { #expect(error as? PasskeyRegistrationProjectionError == .identityCleanupFailed) }
            else { #expect(error is PasskeyRecoveryFixtureError) }
        }
        #expect(await identities.added.count == 1)
        #expect(await identities.removed.count == 1)
        #expect(await identities.entries.count == (failRemove ? 2 : 1))
        #expect(try fixture.store.read()?.ciphers.map(\.id) == ["existing", "saved"])
    }

    @Test(arguments: ["cipher", "credential", "rp"])
    func metadataMustMatchTheConfirmedCipherCredentialAndRelyingParty(_ mismatch: String) async throws {
        let fixture = try PasskeyProjectionCacheFixture(), identities = PasskeyIdentityProbe()
        defer { try? fixture.cleanup() }
        await #expect(throws: PasskeyRegistrationProjectionError.invalidIdentity) {
            try await fixture.projection(identities: identities).project(
                AutoFillQuerySourceFixture.dto("saved"),
                credentialID: Foundation.Data([1]),
                relyingPartyIdentifier: "example.com",
                makeIdentity: { _ in
                    PasskeyProjectionCacheFixture.identity(
                        id: mismatch == "cipher" ? "other" : "saved",
                        credentialID: Foundation.Data(
                            [mismatch == "credential" ? 2 : 1]
                        ),
                        rp: mismatch == "rp" ? "other.example.com" : "example.com"
                    )
                }
            )
        }
        #expect(await identities.added.isEmpty)
        #expect(await identities.removed.isEmpty)
    }

    @Test
    func legacyCacheWithoutMonotonicRevisionRequiresFullAppRepair() async throws {
        let fixture = try PasskeyProjectionCacheFixture(revision: nil), identities = PasskeyIdentityProbe()
        defer { try? fixture.cleanup() }
        await #expect(throws: CancellationError.self) {
            try await fixture.projection(identities: identities).project(
                AutoFillQuerySourceFixture.dto("saved"),
                credentialID: Foundation.Data([1]),
                relyingPartyIdentifier: "example.com",
                makeIdentity: { _ in
                    Issue.record(
                        "Legacy cache must not reach SDK/OS projection"
                    ); return PasskeyProjectionCacheFixture.identity(
                    )
                }
            )
        }
        #expect(try fixture.store.read()?.ciphers.last?.id == "saved")
        #expect(await identities.added.isEmpty)
    }

    @Test
    func parallelProjectionCannotStartAnotherCacheCommit() async throws {
        let fixture = try PasskeyProjectionCacheFixture(), identities = PasskeyIdentityProbe(), gate = AuthOperationTestGate(
        )
        defer { try? fixture.cleanup() }
        let projection = fixture.projection(identities: identities)
        let task = Task { try await projection.project(
            AutoFillQuerySourceFixture.dto("saved"),
            credentialID: Foundation.Data([1]),
            relyingPartyIdentifier: "example.com",
            makeIdentity: { _ in await gate.pause(); return PasskeyProjectionCacheFixture.identity() }
        ) }
        await gate.waitUntilPaused()
        await #expect(throws: AutoFillOperationError.operationInProgress) {
            try await projection.project(
                AutoFillQuerySourceFixture.dto("other"),
                credentialID: Foundation.Data([1]),
                relyingPartyIdentifier: "example.com",
                makeIdentity: { _ in PasskeyProjectionCacheFixture.identity() }
            )
        }
        await gate.release(); try await task.value
        #expect(try fixture.store.read()?.ciphers.map(\.id) == ["existing", "saved"])
    }
}
