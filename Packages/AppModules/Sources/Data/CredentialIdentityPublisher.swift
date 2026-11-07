import AutoFillData
import Domain
import Foundation

/// Pure, platform-independent mapping from decrypted login metadata to non-secret system
/// suggestion descriptors. The SDK adapter is responsible for supplying decrypted passkey public
/// identifiers; this mapper neither imports the SDK nor decrypts anything.
public enum CredentialIdentityMapper {
    public static func makeIdentities(from sources: [VaultLoginIdentitySource]) -> [CredentialIdentityDescriptor] {
        sources.flatMap { source -> [CredentialIdentityDescriptor] in
            guard source.isEligibleForAutoFill else { return [] }

            var identities: [CredentialIdentityDescriptor] = []
            let domains = Set(source.domainMatchingURIs.compactMap {
                QuickTypeIdentityPolicy.domain(for: $0, matchType: .domain)
            })
            for domain in domains.sorted() {
                let kinds: [CredentialIdentityKind] = source.hasOneTimeCode ? [.password, .oneTimeCode] : [.password]
                for kind in kinds {
                    guard kind != .password || source.username?.isEmpty == false else { continue }
                    identities.append(CredentialIdentityDescriptor(
                        id: descriptorID(
                            cipherID: source.cipherID,
                            kind: kind,
                            serviceIdentifier: domain,
                            credentialID: nil
                        ),
                        kind: kind, serviceIdentifier: domain, user: source.username, label: source.displayName,
                        credentialID: nil, userHandle: nil, recordIdentifier: source.cipherID
                    ))
                }
            }
            for passkey in source.passkeys where !passkey.relyingPartyIdentifier.isEmpty {
                identities.append(CredentialIdentityDescriptor(
                    id: descriptorID(
                        cipherID: source.cipherID,
                        kind: .passkey,
                        serviceIdentifier: passkey.relyingPartyIdentifier,
                        credentialID: passkey.credentialID
                    ),
                    kind: .passkey,
                    serviceIdentifier: passkey.relyingPartyIdentifier,
                    user: passkey.userName ?? source.username,
                    label: source.displayName,
                    credentialID: passkey.credentialID,
                    userHandle: passkey.userHandle,
                    recordIdentifier: source.cipherID
                ))
            }
            return identities
        }
    }

    private static func descriptorID(
        cipherID: CipherID,
        kind: CredentialIdentityKind,
        serviceIdentifier: String,
        credentialID: Data?
    ) -> String {
        [cipherID.rawValue, kind.rawValue, serviceIdentifier, credentialID?.base64EncodedString() ?? ""].joined(
            separator: "|"
        )
    }
}

/// Health of the platform suggestion store. It is intentionally separate from a successful vault
/// mutation: an OS-store failure must not cause a second server write, but must be visible to the
/// repository as stale rather than being silently treated as current.
public enum CredentialIdentityHealth: Sendable, Equatable {
    case current(revision: UInt64)
    case stale(lastSuccessfulRevision: UInt64)
    case unavailable
}

/// Publishes platform identities only after `AutoFillProjectionWriter` has committed the same
/// revision. This is the ordering boundary that prevents QuickType from selecting a record absent
/// from the extension's on-disk cache.
public actor CredentialIdentityPublisher {
    private let store: CredentialIdentityPublishing
    private let identityMutations: any CredentialIdentityMutationCoordinating
    private let checkProjection: @Sendable (UInt64) throws -> Void
    private let checkClearAccess: @Sendable () throws -> Void
    private var lastSuccessfulRevision: UInt64?
    private var health: CredentialIdentityHealth = .unavailable
    private(set) var isClosed = false
    private var operationActive = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(
        store: CredentialIdentityPublishing,
        identityMutations: any CredentialIdentityMutationCoordinating,
        checkProjection: @escaping @Sendable (UInt64) throws -> Void,
        checkClearAccess: @escaping @Sendable () throws -> Void
    ) {
        self.store = store
        self.identityMutations = identityMutations; self.checkProjection = checkProjection; self.checkClearAccess = checkClearAccess
    }

    public func currentHealth() -> CredentialIdentityHealth {
        health
    }

    @discardableResult
    public func publish(
        revision: UInt64,
        identities: [CredentialIdentityDescriptor],
        projectionHealth: AutoFillProjectionHealth
    ) async -> CredentialIdentityHealth {
        await acquireOperation()
        defer { releaseOperation() }
        guard !isClosed else { return health }
        guard projectionHealth == .current(revision: revision) else {
            health = lastSuccessfulRevision.map(CredentialIdentityHealth.stale(lastSuccessfulRevision:)) ?? .unavailable
            return health
        }
        guard revision >= (lastSuccessfulRevision ?? 0) else { return health }

        do {
            try await identityMutations.withExclusiveMutation {
                try await self.replace(revision: revision, identities: identities)
            }
        } catch {
            health = lastSuccessfulRevision.map(CredentialIdentityHealth.stale(lastSuccessfulRevision:)) ?? .unavailable
        }
        return health
    }

    private func replace(revision: UInt64, identities: [CredentialIdentityDescriptor]) async throws {
        guard !isClosed else { throw CancellationError() }
        try checkProjection(revision)
        do {
            try await store.replaceCredentialIdentities(identities, revision: revision)
            try checkProjection(revision)
            guard !isClosed else { return } // this publisher's queued lock owns the final clear
            lastSuccessfulRevision = revision
            health = .current(revision: revision)
        } catch {
            // An uncertain replacement/obsolete cache must not stay advertised as current.
            // Compensation is ordered before a newer OS batch, never after its publication.
            let failure = error
            try checkClearAccess()
            try await store.removeAllCredentialIdentities()
            throw failure
        }
    }

    /// Lock has a stricter contract than a routine publish: suggestions must be removed so the OS
    /// cannot route a credential request into a vault that is no longer allowed to fulfil it.
    @discardableResult
    public func lock() async -> CredentialIdentityHealth {
        isClosed = true
        return await clear()
    }

    /// Routine projection repair clears suggestions but allows a later successful sync.
    @discardableResult
    public func clear() async -> CredentialIdentityHealth {
        await acquireOperation()
        defer { releaseOperation() }
        do {
            try await identityMutations.withExclusiveMutation {
                try self.checkClearAccess()
                try await self.store.removeAllCredentialIdentities()
            }
            lastSuccessfulRevision = nil
            health = .unavailable
        } catch {
            health = lastSuccessfulRevision.map(CredentialIdentityHealth.stale(lastSuccessfulRevision:)) ?? .unavailable
        }
        return health
    }

    private func acquireOperation() async {
        if operationActive { await withCheckedContinuation { waiters.append($0) } }
        else { operationActive = true }
    }

    private func releaseOperation() {
        if waiters.isEmpty { operationActive = false }
        else { waiters.removeFirst().resume() }
    }
}
