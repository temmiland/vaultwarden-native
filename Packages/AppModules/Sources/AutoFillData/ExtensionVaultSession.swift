import AutoFillContract
import BitwardenSDKAdapter
import Domain
import Foundation

/// One invocation assembly. Immutable shared source + separate query/passkey actors; neither
/// actor caches decrypted results. Synchronous SDK callbacks use the same revocable lease.
public final class ExtensionVaultSession: Sendable {
    public let credentials: CredentialQuery
    public let passkeys: PasskeyService
    public let registrationWrites = PasskeyRegistrationWriter()
    public let registrations: PasskeyRegistrationCoordinator
    public var accountInfo: SharedAccountInfo { source.accountInfo }
    public var proof: ExtensionUnlockProof { source.lease.proof }
    public var cacheRevision: UUID { source.cacheRevision }
    private let source: LiveAutoFillCredentialSource

    public convenience init(
        accountInfo: SharedAccountInfo,
        proof: ExtensionUnlockProof,
        cacheRevision: UUID,
        applicationVersion: String,
        currentProof: @escaping @Sendable () throws -> ExtensionUnlockProof?,
        readCache: @escaping @Sendable () throws -> SharedVaultCacheData?
    ) throws {
        try self.init(
            accountInfo: accountInfo,
            proof: proof,
            cacheRevision: cacheRevision,
            resource: SDKAutoFillService.makeExtensionResource(
                account: accountInfo,
                applicationVersion: applicationVersion
            ),
            currentProof: currentProof,
            readCache: readCache
        )
    }

    /// Internal resource injection for no-handle source tests, not a live raw-client factory.
    init(
        accountInfo: SharedAccountInfo,
        proof: ExtensionUnlockProof,
        cacheRevision: UUID,
        resource: SDKSessionClient,
        currentProof: @escaping @Sendable () throws -> ExtensionUnlockProof?,
        readCache: @escaping @Sendable () throws -> SharedVaultCacheData?
    ) throws {
        guard proof.account.userID == accountInfo.userId, proof.account.serverBaseURL == accountInfo.serverBaseURL else {
            resource.revoke()
            throw AutoFillOperationError.accessDenied
        }
        let source = LiveAutoFillCredentialSource(
            accountInfo: accountInfo,
            cacheRevision: cacheRevision,
            resource: resource,
            lease: ExtensionSession(proof: proof, resource: resource, currentProof: currentProof),
            readCache: readCache
        )
        self.source = source
        let query = CredentialQuery(source: source)
        credentials = query
        passkeys = PasskeyService(source: source, credentials: query)
        registrations = PasskeyRegistrationCoordinator(writer: registrationWrites)
    }

    deinit { source.lease.revoke() }
    public func revoke() { source.lease.revoke() }
    public func checkAccess() throws { try source.lease.checkAccess() }
    public func readCache() throws -> SharedVaultCacheData { try source.readCache() }
    public func requireCurrentAccess(to view: SDKAutoFillCredentialView, forEditing: Bool = false) throws {
        try CredentialQuery.requireCurrentAccess(to: view, source: source, forEditing: forEditing)
    }

    public func initialize(userKey: String, organizationKeys: [String: String]) async throws {
        do {
            try await perform { try await $0.initializeUser(account: self.accountInfo, userKey: userKey) }
            try await perform { try await $0.initializeOrganizations(organizationKeys) }
            _ = try readCache()
        } catch { revoke(); throw error }
    }

    /// Lease-checked typed adapter operations for callbacks/registration, never a raw SDK client.
    public func perform<Value>(_ operation: (SDKAutoFillService) throws -> Value) throws -> Value {
        try source.perform(operation)
    }

    public func perform<Value>(_ operation: (SDKAutoFillService) async throws -> Value) async throws -> Value {
        try await source.perform(operation)
    }
}

private final class LiveAutoFillCredentialSource: AutoFillCredentialSource {
    let accountInfo: SharedAccountInfo
    let cacheRevision: UUID
    let lease: ExtensionSession
    private let resource: SDKSessionClient
    private let crypto: SDKAutoFillService
    private let cache: @Sendable () throws -> SharedVaultCacheData?
    init(
        accountInfo: SharedAccountInfo,
        cacheRevision: UUID,
        resource: SDKSessionClient,
        lease: ExtensionSession,
        readCache: @escaping @Sendable () throws -> SharedVaultCacheData?
    ) {
        self.accountInfo = accountInfo; self.cacheRevision = cacheRevision; self.resource = resource
        self.lease = lease; crypto = SDKAutoFillService(session: resource); cache = readCache
    }

    deinit { resource.revoke() }
    func readCache() throws -> SharedVaultCacheData {
        do {
            try lease.checkAccess()
            guard let value = try cache() else { throw AutoFillOperationError.noCache }
            try value.validate(for: lease.proof.account)
            guard value.revision == cacheRevision else { throw CancellationError() }
            try lease.checkAccess()
            return value
        } catch { lease.revoke(); throw error }
    }

    func checkAccess() throws { try lease.checkAccess() }

    func perform<Value>(_ operation: (SDKAutoFillService) throws -> Value) throws -> Value {
        try lease.checkAccess()
        do { let result = try operation(crypto); try lease.checkAccess(); return result }
        catch { try lease.checkAccess(); throw error }
    }

    func perform<Value>(_ operation: (SDKAutoFillService) async throws -> Value) async throws -> Value {
        try lease.checkAccess()
        do { let result = try await operation(crypto); try lease.checkAccess(); return result }
        catch { try lease.checkAccess(); throw error }
    }

    func decrypt(_ cipher: CipherResponseDTO) async throws -> SDKAutoFillCredentialView { try await perform { try await $0.decryptView(
        cipher
    ) } }
    func oneTimeCode(seed: String, at date: Date) throws -> TimeBasedOneTimeCode { try perform { try $0.oneTimeCode(
        seed: seed,
        at: date
    ) } }
    func passkeys(in view: SDKAutoFillCredentialView) throws -> [SDKAutoFillPasskeyMetadata] { try perform { try $0.passkeyMetadata(
        in: view
    ) } }
}
