import AutoFillContract
import AutoFillData
import Domain
import Foundation
import Testing

/// Source fixtures only: no SDK Client, Keychain, OS extension context or network.
@Suite
struct ExtensionSessionTests {
    @Test
    func lockAndReunlockTheSameAccountCannotReopenAnOldLease() throws {
        let proof = makeProof()
        let source = ProofSource(proof)
        let resource = ExtensionResource()
        let session = ExtensionSession(proof: proof, resource: resource, currentProof: { try source.read() })
        try session.checkAccess()
        source.set(nil)
        #expect(throws: CancellationError.self) { try session.checkAccess() }
        source.set(proof) // even restoring the same bytes cannot reopen the local resource
        #expect(throws: CancellationError.self) { try session.checkAccess() }
        #expect(!resource.isActive)
    }

    @Test
    func aDifferentUnlockOrAccountRevokesTheRetainedResource() {
        let proof = makeProof()
        for replacement in [
            makeProof(),
            makeProof(userID: "another-account"),
            makeProof(server: "https://other.example.com"),
        ] {
            let source = ProofSource(proof)
            let resource = ExtensionResource()
            let session = ExtensionSession(proof: proof, resource: resource, currentProof: { try source.read() })
            source.set(replacement)
            #expect(throws: CancellationError.self) { try session.checkAccess() }
            #expect(!resource.isActive)
        }
    }

    @Test
    func aKeychainFailureIsNotTreatedAsPermissionToUseCachedCrypto() {
        let proof = makeProof()
        let source = ProofSource(proof)
        let resource = ExtensionResource()
        let session = ExtensionSession(proof: proof, resource: resource, currentProof: { try source.read() })
        source.failReads()
        #expect(throws: ProofSource.Unavailable.self) { try session.checkAccess() }
        #expect(!resource.isActive)
    }

    @MainActor
    @Test
    func completionCancellationAndOldCallbacksShareOneInvocationGate() {
        let lifecycle = ExtensionRequestLifecycle()
        let first = lifecycle.begin()
        #expect(lifecycle.beginAction(first))
        #expect(!lifecycle.beginAction(first)) // double tap cannot start a second write
        let second = lifecycle.begin()
        #expect(!lifecycle.isActive(first))
        #expect(!lifecycle.claimCompletion(first))
        #expect(lifecycle.beginAction(second))
        lifecycle.endAction(first) // old completion cannot release the new write's busy guard
        #expect(!lifecycle.beginAction(second))
        lifecycle.endAction(second)
        #expect(lifecycle.beginAction(second))
        #expect(lifecycle.claimCompletion(second))
        #expect(!lifecycle.claimCompletion(second))
        #expect(!lifecycle.beginAction(second))
    }

    private func makeProof(userID: String = "account-1", server: String = "https://vault.example.com") -> ExtensionUnlockProof {
        ExtensionUnlockProof(account: AutoFillAccountIdentity(userID: userID, serverBaseURL: URL(string: server)!))
    }
}

private final class ExtensionResource: SessionResource, @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    var isActive: Bool { lock.withLock { active } }
    func revoke() { lock.withLock { active = false } }
}

private final class ProofSource: @unchecked Sendable {
    struct Unavailable: Error {}
    private let lock = NSLock()
    private var proof: ExtensionUnlockProof?
    private var readsFail = false
    init(_ proof: ExtensionUnlockProof) { self.proof = proof }
    func set(_ proof: ExtensionUnlockProof?) { lock.withLock { self.proof = proof } }
    func failReads() { lock.withLock { readsFail = true } }
    func read() throws -> ExtensionUnlockProof? {
        try lock.withLock { if readsFail { throw Unavailable() }; return proof }
    }
}
