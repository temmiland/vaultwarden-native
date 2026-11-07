import AutoFillContract
import AutoFillData
import Domain
import Foundation

/// Real encrypted cache files; fake authorization and OS index. No FFI or signed OS calls.
struct PasskeyProjectionCacheFixture: Sendable {
    let directory: URL
    let proof = PasskeyRecoveryJournalFixture.proof
    let originalRevision = UUID()
    let authorization = PasskeyProjectionAuthorization()
    var cacheURL: URL { directory.appendingPathComponent("autofill-cache.json") }
    var store: LegacyAutoFillCacheStore { LegacyAutoFillCacheStore(directoryURL: directory, authorization: authorization) }

    init(revision: UInt64? = 17) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("passkey-projection-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cache = SharedVaultCacheData(
            ciphers: [AutoFillQuerySourceFixture.dto("existing")],
            organizationKeys: [:],
            updatedAt: .distantPast,
            owner: proof.account,
            revision: originalRevision,
            projectionRevision: revision
        )
        try JSONEncoder().encode(cache).write(to: cacheURL)
    }

    func edit(_ body: (inout SharedVaultCacheData) -> Void) throws {
        try authorization.withAuthorizedCacheMutation(requiring: proof) {
            var cache = try JSONDecoder().decode(SharedVaultCacheData.self, from: Foundation.Data(contentsOf: cacheURL))
            body(&cache)
            try JSONEncoder().encode(cache).write(to: cacheURL)
        }
    }

    func cleanup() throws { try FileManager.default.removeItem(at: directory) }
    static func identity(
        id: String = "saved",
        credentialID: Foundation.Data = Foundation.Data([1]),
        rp: String = "example.com"
    ) -> CredentialIdentityDescriptor {
        CredentialIdentityDescriptor(
            id: "\(id)|passkey|\(rp)|\(credentialID.base64EncodedString())",
            kind: .passkey,
            serviceIdentifier: rp,
            user: "fixture-user",
            label: "Example",
            credentialID: credentialID,
            userHandle: Foundation.Data(),
            recordIdentifier: CipherID(rawValue: id)
        )
    }

    func projection(
        identities: any PasskeyIdentityUpdating,
        identityMutations: any CredentialIdentityMutationCoordinating = IdentityMutationTestCoordinator()
    ) -> PasskeyRegistrationProjection {
        PasskeyRegistrationProjection(
            cache: store,
            proof: proof,
            cacheRevision: originalRevision,
            identities: identities,
            identityMutations: identityMutations,
            checkAccess: { try authorization.check() }
        )
    }
}

final class PasskeyProjectionAuthorization: AutoFillCacheMutationAuthorizing, @unchecked Sendable {
    private let lock = NSLock()
    private var revoked = false
    func revoke() { lock.withLock { revoked = true } }
    func check() throws { try lock.withLock { if revoked { throw CancellationError() } } }
    func withAuthorizedCacheMutation<Value>(requiring proof: ExtensionUnlockProof, _ operation: () throws -> Value) throws -> Value {
        try lock.withLock {
            guard !revoked, proof == PasskeyRecoveryJournalFixture.proof else { throw CancellationError() }
            return try operation()
        }
    }
}

actor PasskeyIdentityProbe: PasskeyIdentityUpdating {
    private(set) var added: [CredentialIdentityDescriptor] = []
    private(set) var removed: [CredentialIdentityDescriptor] = []
    private(set) var entries = [
        PasskeyProjectionCacheFixture.identity(id: "existing", credentialID: Foundation.Data([99])),
    ]
    let gate: AuthOperationTestGate?
    let failAdd: Bool
    let failRemove: Bool
    init(gate: AuthOperationTestGate? = nil, failAdd: Bool = false, failRemove: Bool = false) {
        self.gate = gate; self.failAdd = failAdd; self.failRemove = failRemove
    }

    func addPasskeyIdentity(_ identity: CredentialIdentityDescriptor) async throws {
        added.append(identity); entries.append(identity)
        await gate?.pause()
        if failAdd { throw PasskeyRecoveryFixtureError.storage }
    }

    func removePasskeyIdentity(_ identity: CredentialIdentityDescriptor) async throws {
        removed.append(identity)
        if failRemove { throw PasskeyRecoveryFixtureError.storage }
        entries.removeAll { $0 == identity }
    }
}
