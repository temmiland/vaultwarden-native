import Foundation

// MARK: - Stable identifiers

public protocol DomainIdentifier: RawRepresentable, Codable, Hashable, Sendable where RawValue == String {}

public struct AccountID: DomainIdentifier { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }
public struct CipherID: DomainIdentifier { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }
public struct FolderID: DomainIdentifier { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }
public struct CollectionID: DomainIdentifier { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }
public struct OrganizationID: DomainIdentifier { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }
public struct SendID: DomainIdentifier { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }
public struct AttachmentID: DomainIdentifier { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }

// MARK: - Non-secret session state

public struct ServerEnvironment: Equatable, Hashable, Sendable, Codable {
    public let baseURL: URL
    public let apiURL: URL
    public let identityURL: URL
    public let webVaultURL: URL

    public init(baseURL: URL) throws {
        guard let scheme = baseURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = baseURL.host, !host.isEmpty,
              baseURL.user == nil, baseURL.password == nil,
              baseURL.query == nil, baseURL.fragment == nil,
              baseURL.port.map({ (1 ... 65_535).contains($0) }) ?? true
        else { throw ServerEnvironmentError.invalidBaseURL }

        // Remove a trailing slash but preserve a reverse-proxy path such as `/vault`.
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        if components?.path.hasSuffix("/") == true, components?.path != "/" {
            components?.path.removeLast()
        }
        guard let normalizedBase = components?.url else { throw ServerEnvironmentError.invalidBaseURL }
        self.baseURL = normalizedBase
        apiURL = normalizedBase.appendingPathComponent("api")
        identityURL = normalizedBase.appendingPathComponent("identity")
        webVaultURL = normalizedBase
    }

    /// Preserve existing explicitly configured service routes during the runtime migration.
    public init(baseURL: URL, apiURL: URL, identityURL: URL, webVaultURL: URL) throws {
        let normalized = try Self(baseURL: baseURL)
        for url in [apiURL, identityURL, webVaultURL] {
            _ = try Self(baseURL: url)
        }
        self.baseURL = normalized.baseURL
        self.apiURL = apiURL
        self.identityURL = identityURL
        self.webVaultURL = webVaultURL
    }

    /// Decoding must not bypass the same validation as explicitly constructed environments.
    private enum CodingKeys: String, CodingKey { case baseURL, apiURL, identityURL, webVaultURL }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            baseURL: values.decode(URL.self, forKey: .baseURL),
            apiURL: values.decode(URL.self, forKey: .apiURL),
            identityURL: values.decode(URL.self, forKey: .identityURL),
            webVaultURL: values.decode(URL.self, forKey: .webVaultURL)
        )
    }
}

public enum ServerEnvironmentError: Error, Equatable, Sendable {
    case invalidBaseURL
}

public struct AccountSession: Sendable, Equatable {
    public let accountID: AccountID
    public let email: String
    public let environment: ServerEnvironment

    public init(accountID: AccountID, email: String, environment: ServerEnvironment) {
        self.accountID = accountID
        self.email = email
        self.environment = environment
    }
}

public enum SessionState: Sendable, Equatable {
    case signedOut
    case locked(AccountSession)
    case unlocking(AccountSession)
    case unlocked(AccountSession)
    case expiring(AccountSession)
}

public enum AuthSessionTransition: Sendable, Equatable {
    case initial, restored, unlockStarted, unlockCompleted, unlockFailed, expiring, locked, loggedOut
}

/// Ordered auth events contain account metadata only. The runtime ID identifies the accepted
/// capability; revision prevents a queued event from replacing a later app-model handoff.
public struct AuthSessionSnapshot: Sendable, Equatable {
    public let state: SessionState
    public let sessionID: UUID?
    public let revision: UInt64
    public let transition: AuthSessionTransition

    public init(state: SessionState, sessionID: UUID?, revision: UInt64, transition: AuthSessionTransition) {
        self.state = state
        self.sessionID = sessionID
        self.revision = revision
        self.transition = transition
    }
}

// MARK: - Presentation-safe domain values

public enum VaultItemKind: String, Codable, Sendable, CaseIterable {
    case login, secureNote, card, identity, sshKey
    case bankAccount, driversLicense, passport, unknown
}

public struct VaultItemSummary: Sendable, Equatable, Identifiable, CustomStringConvertible, CustomDebugStringConvertible {
    public let id: CipherID
    public let kind: VaultItemKind
    public let name: String
    public let subtitle: String?
    public let isFavorite: Bool
    public let isEditable: Bool
    public let canDelete: Bool
    public let hasPasskeys: Bool
    public let folderID: FolderID?
    public let collectionIDs: [CollectionID]
    /// Only the existing name/username/URI search inputs; never passwords, TOTP or private keys.
    public let searchTerms: [String]

    public init(
        id: CipherID, kind: VaultItemKind, name: String, subtitle: String?, isFavorite: Bool, isEditable: Bool,
        canDelete: Bool = false, hasPasskeys: Bool = false, folderID: FolderID? = nil,
        collectionIDs: [CollectionID] = [], searchTerms: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.subtitle = subtitle
        self.isFavorite = isFavorite
        self.isEditable = isEditable
        self.canDelete = canDelete
        self.hasPasskeys = hasPasskeys
        self.folderID = folderID
        self.collectionIDs = collectionIDs
        self.searchTerms = searchTerms
    }

    public var description: String { "VaultItemSummary(<redacted>)" }
    public var debugDescription: String { description }
}

public struct VaultSnapshot: Sendable, Equatable {
    public let revision: UInt64
    public let items: [VaultItemSummary]
    public let lastSuccessfulSync: Date?
    public let isStale: Bool
    public let details: [CipherID: VaultItemDetail]
    public let folders: [VaultFolderSummary]
    public let collections: [VaultCollectionSummary]
    public let organizationNames: [OrganizationID: String]
    public let warnings: [VaultLoadWarning]
    public let projectionStatus: VaultProjectionStatus

    public init(
        revision: UInt64,
        items: [VaultItemSummary],
        lastSuccessfulSync: Date?,
        isStale: Bool,
        details: [CipherID: VaultItemDetail] = [:],
        folders: [VaultFolderSummary] = [],
        collections: [VaultCollectionSummary] = [],
        organizationNames: [OrganizationID: String] = [:],
        warnings: [VaultLoadWarning] = [],
        projectionStatus: VaultProjectionStatus = .unavailable
    ) {
        self.revision = revision
        self.items = items
        self.lastSuccessfulSync = lastSuccessfulSync
        self.isStale = isStale
        self.details = details
        self.folders = folders
        self.collections = collections
        self.organizationNames = organizationNames
        self.warnings = warnings
        self.projectionStatus = projectionStatus
    }
}

// MARK: - AutoFill identity projection

/// The non-secret input needed to publish system AutoFill suggestions. It deliberately carries no
/// password, TOTP seed, encrypted vault key or passkey private key.
public struct VaultLoginIdentitySource: Sendable, Equatable {
    public let cipherID: CipherID
    public let displayName: String
    public let username: String?
    public let serviceIdentifiers: [String]
    /// Only URIs whose effective policy is Base Domain; stricter modes cannot use OS suggestions.
    public let domainMatchingURIs: [String]
    /// Digest of opaque password ciphertext for confirmed-write reconciliation.
    public let passwordCiphertextHash: Data?
    public let hasOneTimeCode: Bool
    public let passkeys: [PasskeyIdentitySource]
    public let isEligibleForAutoFill: Bool

    public init(
        cipherID: CipherID,
        displayName: String,
        username: String?,
        serviceIdentifiers: [String],
        hasOneTimeCode: Bool,
        passkeys: [PasskeyIdentitySource],
        isEligibleForAutoFill: Bool,
        domainMatchingURIs: [String] = [],
        passwordCiphertextHash: Data? = nil
    ) {
        self.cipherID = cipherID
        self.displayName = displayName
        self.username = username
        self.serviceIdentifiers = serviceIdentifiers
        self.domainMatchingURIs = domainMatchingURIs
        self.passwordCiphertextHash = passwordCiphertextHash
        self.hasOneTimeCode = hasOneTimeCode
        self.passkeys = passkeys
        self.isEligibleForAutoFill = isEligibleForAutoFill
    }
}

public struct PasskeyIdentitySource: Sendable, Equatable {
    public let relyingPartyIdentifier: String
    public let userName: String?
    public let credentialID: Data
    public let userHandle: Data?

    public init(relyingPartyIdentifier: String, userName: String?, credentialID: Data, userHandle: Data?) {
        self.relyingPartyIdentifier = relyingPartyIdentifier
        self.userName = userName
        self.credentialID = credentialID
        self.userHandle = userHandle
    }
}

public enum CredentialIdentityKind: String, Sendable, Equatable {
    case password
    case oneTimeCode
    case passkey
}

/// Platform-neutral descriptor passed to the iOS/macOS credential-identity adapter. It contains
/// exactly the metadata the OS needs to display and resolve a suggestion, never a fulfilment
/// secret.
public struct CredentialIdentityDescriptor: Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: CredentialIdentityKind
    public let serviceIdentifier: String
    public let user: String?
    public let label: String?
    public let credentialID: Data?
    public let userHandle: Data?
    public let recordIdentifier: CipherID

    public init(
        id: String,
        kind: CredentialIdentityKind,
        serviceIdentifier: String,
        user: String?,
        label: String?,
        credentialID: Data?,
        userHandle: Data?,
        recordIdentifier: CipherID
    ) {
        self.id = id
        self.kind = kind
        self.serviceIdentifier = serviceIdentifier
        self.user = user
        self.label = label
        self.credentialID = credentialID
        self.userHandle = userHandle
        self.recordIdentifier = recordIdentifier
    }
}

public enum Loadable<Value: Sendable>: Sendable {
    case idle
    case loading
    case loaded(Value)
    case failed(UserFacingError)
}

public struct UserFacingError: Error, Sendable, Equatable {
    public let message: String
    public let isRetryable: Bool

    public init(message: String, isRetryable: Bool) {
        self.message = message
        self.isRetryable = isRetryable
    }
}

// MARK: - Ports

public protocol AuthRepository: Sendable {
    func sessionStates() async -> AsyncStream<AuthSessionSnapshot>
    func currentSnapshot() async -> AuthSessionSnapshot
    func restore() async throws -> SessionState
    func beginUnlock(account: AccountSession) async throws
    @discardableResult
    func completeUnlock(_ account: AccountSession, sessionID: UUID) async throws -> AuthSessionSnapshot
    func unlockFailed(account: AccountSession) async
    func markExpiring(sessionID: UUID) async
    func lock() async throws
    func logout() async throws
}

public enum AuthRepositoryError: Error, Sendable, Equatable {
    case invalidTransition
    case accountChanged
    case staleSession
}

public protocol VaultRepository: Sendable {
    func observeVault() async -> AsyncStream<VaultSnapshot>
    func sync() async throws
    func currentSnapshot() async -> VaultSnapshot
    func makeDraft(for id: CipherID) async throws -> VaultItemDraft
    func save(_ draft: VaultItemDraft) async throws -> CipherID
    func delete(_ context: VaultItemContext) async throws
    func oneTimeCode(for context: VaultItemContext) async throws -> VaultOneTimeCode
    func passkeys(for context: VaultItemContext) async throws -> [VaultPasskeySummary]
    func preparePasskeyRegistrationRecoveryReview() async throws -> PasskeyRegistrationRecoveryReview
    /// Call only after explicit user acknowledgment/inspection; abandons local tracking only.
    func abandonPasskeyRegistrationRecovery(_ review: PasskeyRegistrationRecoveryReview) async throws
    func uploadAttachment(to context: VaultItemContext, file: any ImportedFile) async throws
    func downloadAttachment(_ reference: VaultAttachmentReference, context: VaultItemContext) async throws -> URL
    func deleteAttachment(_ reference: VaultAttachmentReference, context: VaultItemContext) async throws
    func lock() async
}

public enum CredentialIdentityPublishingError: Error, Sendable, Equatable {
    /// The user has not enabled this provider in the operating system.
    case disabled
}

/// Implemented by a platform adapter around `ASCredentialIdentityStore`. Its revision must match
/// the AutoFill file projection revision supplied by Data, so identity suggestions never claim a
/// newer vault than the extension can actually fulfil.
public protocol CredentialIdentityPublishing: Sendable {
    func replaceCredentialIdentities(_ identities: [CredentialIdentityDescriptor], revision: UInt64) async throws
    func removeAllCredentialIdentities() async throws
}

/// Incremental registration projection must never replace the entire system index. Unsupported
/// incremental stores must fail so the authoritative full-vault app sync can repair instead.
public protocol PasskeyIdentityUpdating: Sendable {
    func addPasskeyIdentity(_ identity: CredentialIdentityDescriptor) async throws
    func removePasskeyIdentity(_ identity: CredentialIdentityDescriptor) async throws
}

public struct RegisteredDevice: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let isTrusted: Bool
    public let lastActivityDate: Date?

    public init(id: String, name: String, isTrusted: Bool, lastActivityDate: Date?) {
        self.id = id
        self.name = name
        self.isTrusted = isTrusted
        self.lastActivityDate = lastActivityDate
    }
}

public enum SettingsRepositoryError: Error, Equatable, Sendable {
    case sessionUnavailable
    case invalidResponse
    case server(statusCode: Int)
}

public protocol SettingsRepository: Sendable {
    func fetchDevices() async throws -> [RegisteredDevice]
    func revokeDevice(id: String) async throws
}

/// PIN settings scoped by app composition to one authenticated session. Implementations must
/// revalidate session lineage around crypto and persistence; presentation receives neither a
/// session, a Keychain store, nor a PIN-derived key.
public protocol PinUnlockSettings: Sendable {
    func isEnabled() async throws -> Bool
    func enroll(pin: String) async throws
    func remove() async throws
}

/// A user-interface-bound capability for copying a secret. The platform implementation must keep
/// the value local, mark it as concealed where the operating system supports that and clear it
/// only when the pasteboard was not subsequently changed by the user or another app.
@MainActor
public protocol PasteboardClient: AnyObject, Sendable {
    func copySecret(_ value: String)
}

public enum BiometryKind: Sendable, Equatable {
    case touchID
    case faceID
    case opticID
    case unknown
    public var displayName: String {
        switch self {
        case .touchID: "Touch ID"
        case .faceID: "Face ID"
        case .opticID: "Optic ID"
        case .unknown: "Biometrics"
        }
    }
}

public enum BiometricUnavailableReason: Sendable, Equatable {
    case notAvailable
    case notEnrolled
    case lockedOut
    case passcodeNotSet
    case unknown
}

public enum BiometricAvailability: Sendable, Equatable {
    case available(BiometryKind)
    case unavailable(BiometricUnavailableReason)
}

/// Evaluation deliberately reports cancellation separately from a failed match or unavailable
/// sensor. The Auth feature can then return quietly from a user cancel, offer password fallback on
/// lockout/enrollment changes, and reserve error UI for actual failures.
public enum BiometricEvaluationResult: Sendable, Equatable {
    case succeeded
    case cancelled
    case unavailable(BiometricUnavailableReason)
    case failed
}

@MainActor
public protocol BiometricClient: AnyObject, Sendable {
    func availability() -> BiometricAvailability
    func evaluate(reason: String) async -> BiometricEvaluationResult
}

/// Supplies the user-visible name for the current device without exposing Apple frameworks to the
/// authentication feature. The app still owns the stable installation identifier in Keychain.
@MainActor
public protocol DeviceNameClient: AnyObject, Sendable {
    func currentDeviceName() -> String
}

/// Selected file metadata plus a scoped access operation. The importer owns security-scoped access
/// and keeps it alive for exactly the duration of the caller's read or transfer.
public protocol ImportedFile: Sendable {
    var fileName: String { get }
    func withSecurityScopedAccess<Value: Sendable>(
        _ operation: @Sendable (URL) async throws -> Value
    ) async throws -> Value
}

public enum FileImportClientError: Error, Sendable, Equatable {
    case presentationUnavailable
    case pickerAlreadyPresented
    case failed
}

@MainActor
public protocol FileImportClient: AnyObject {
    /// Returns `nil` when the user dismisses the picker.
    func pickFile() async throws -> (any ImportedFile)?
}

public enum OpenURLClientError: Error, Sendable, Equatable {
    case unableToOpen
}

@MainActor
public protocol OpenURLClient: AnyObject {
    func open(_ url: URL) async throws
}
