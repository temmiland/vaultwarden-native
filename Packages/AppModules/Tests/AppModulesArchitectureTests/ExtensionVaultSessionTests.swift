import AutoFillContract
@testable import AutoFillData
import BitwardenSdk
import BitwardenSDKAdapter
import Foundation
import Testing

@Suite
struct ExtensionVaultSessionTests {
    private func make(_ source: InvocationCacheFixture) throws -> (ExtensionVaultSession, SDKSessionClient) {
        let resource = SDKSessionClient(client: Client(noHandle: Client.NoHandle()))
        let session = try ExtensionVaultSession(
            accountInfo: .fixture(),
            proof: source.originalProof,
            cacheRevision: source.originalRevision,
            resource: resource,
            currentProof: { try source.readProof() },
            readCache: { try source.readCache() }
        )
        return (session, resource)
    }

    @Test
    func invocationUsesTheInjectedReadersAndFixedCacheRevision() throws {
        let source = InvocationCacheFixture()
        let (session, resource) = try make(source)
        #expect(try session.readCache().revision == source.originalRevision)
        #expect(session.proof == source.originalProof && resource.isActive)
        session.revoke()
        #expect(throws: CancellationError.self) { try session.checkAccess() }
    }

    @Test(arguments: ["missing", "owner", "revision", "read-error", "proof", "proof-error"])
    func cacheOrProofFailurePermanentlyRevokesTheSameResource(_ failure: String) throws {
        let source = InvocationCacheFixture()
        let (session, resource) = try make(source)
        source.change(failure)
        #expect(throws: (any Error).self) { _ = try session.readCache() }
        #expect(!resource.isActive)
        source.reset()
        #expect(throws: CancellationError.self) { _ = try session.readCache() }
    }

    @Test
    func aLateNoncooperativeOperationIsDeniedAfterInvocationRevocation() async throws {
        let source = InvocationCacheFixture()
        let (session, resource) = try make(source)
        let gate = AuthOperationTestGate()
        let task = Task { try await session.perform { _ in await gate.pause(); return "late-secret" } }
        await gate.waitUntilPaused()
        session.revoke()
        await gate.release()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(!resource.isActive)
    }

    @Test
    func retainedQueryCannotOutliveItsSessionOwner() async throws {
        let source = InvocationCacheFixture()
        let resource = SDKSessionClient(client: Client(noHandle: Client.NoHandle()))
        var session: ExtensionVaultSession? = try ExtensionVaultSession(
            accountInfo: .fixture(),
            proof: source.originalProof,
            cacheRevision: source.originalRevision,
            resource: resource,
            currentProof: { try source.readProof() },
            readCache: { try source.readCache() }
        )
        let query = try #require(session?.credentials)
        session = nil
        #expect(!resource.isActive)
        await #expect(throws: CancellationError.self) { _ = try await query.logins() }
    }

    @Test
    func mismatchedMetadataCannotBindCryptoToAnotherProofOwner() {
        let source = InvocationCacheFixture()
        let resource = SDKSessionClient(client: Client(noHandle: Client.NoHandle()))
        #expect(throws: AutoFillOperationError.accessDenied) {
            _ = try ExtensionVaultSession(
                accountInfo: .fixture(userID: "foreign-user"),
                proof: source.originalProof,
                cacheRevision: source.originalRevision,
                resource: resource,
                currentProof: { try source.readProof() },
                readCache: { try source.readCache() }
            )
        }
        #expect(!resource.isActive)
    }
}

private final class InvocationCacheFixture: @unchecked Sendable {
    let originalProof = ExtensionUnlockProof(account: AutoFillAccountIdentity(
        userID: "user-1",
        serverBaseURL: URL(string: "https://vault.example.com")!
    ))
    let originalRevision = UUID()
    private let lock = NSLock()
    private var failure: String?
    func change(_ failure: String) { lock.withLock { self.failure = failure } }
    func reset() { lock.withLock { failure = nil } }
    func readProof() throws -> ExtensionUnlockProof? {
        try lock.withLock {
            if failure == "proof-error" { throw AuthFixtureError.operationFailed }
            return failure == "proof" ? nil : originalProof
        }
    }

    func readCache() throws -> SharedVaultCacheData? {
        try lock.withLock {
            if failure == "read-error" { throw AuthFixtureError.operationFailed }
            if failure == "missing" { return nil }
            return SharedVaultCacheData(
                ciphers: [],
                organizationKeys: [:],
                updatedAt: .distantPast,
                owner: failure == "owner" ? nil : originalProof.account,
                revision: failure == "revision" ? UUID() : originalRevision
            )
        }
    }
}
