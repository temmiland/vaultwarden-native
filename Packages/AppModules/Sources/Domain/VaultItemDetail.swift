import Foundation

public enum VaultEditRestriction: Equatable, Sendable {
    case unsupportedKind, inactiveItem, editDenied, secretsHidden, repromptRequired
    case attachmentDecryptionFailure, collectionReadOnly, unresolvedCollection, unsupportedPayload
}

public struct VaultItemPermissions: Equatable, Sendable {
    public let editRestriction: VaultEditRestriction?
    public let canDelete: Bool
    public let canViewSecrets: Bool
    public var canEdit: Bool { editRestriction == nil }

    public init(editRestriction: VaultEditRestriction?, canDelete: Bool, canViewSecrets: Bool) {
        self.editRestriction = editRestriction
        self.canDelete = canDelete
        self.canViewSecrets = canViewSecrets
    }
}

/// A detail task belongs to one selected item revision, not a global seed or an arbitrary SDK view.
public struct VaultItemContext: Hashable, Sendable {
    public let id: CipherID
    public let revision: Date
    public init(id: CipherID, revision: Date) { self.id = id; self.revision = revision }
}

/// In-memory presentation data only. No Codable conformance, encrypted keys, crypto metadata or
/// raw passkey payload. Forbidden fulfilment secrets are omitted by the adapter, not just masked.
public struct VaultItemDetail: Equatable, Sendable, Identifiable, CustomStringConvertible, CustomDebugStringConvertible {
    public let context: VaultItemContext
    public var id: CipherID { context.id }
    public let kind: VaultItemKind
    public let name: String
    public let notes: String?
    public let isFavorite: Bool
    public let organizationName: String?
    public let permissions: VaultItemPermissions
    public let payload: VaultItemPayload
    public let attachments: [VaultAttachmentSummary]

    public init(
        context: VaultItemContext, kind: VaultItemKind, name: String, notes: String?,
        isFavorite: Bool, organizationName: String?, permissions: VaultItemPermissions,
        payload: VaultItemPayload, attachments: [VaultAttachmentSummary]
    ) {
        self.context = context; self.kind = kind; self.name = name; self.notes = notes
        self.isFavorite = isFavorite; self.organizationName = organizationName
        self.permissions = permissions; self.payload = payload; self.attachments = attachments
    }

    public var description: String { "VaultItemDetail(<redacted>)" }
    public var debugDescription: String { description }
}

public enum VaultItemPayload: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    case login(VaultLoginDetail), card(VaultCardDetail), identity(VaultIdentityDetail)
    case secureNote, sshKey(VaultSSHKeyDetail), unsupported
    public var description: String { "VaultItemPayload(<redacted>)" }
    public var debugDescription: String { description }
}

public struct VaultLoginDetail: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let username: String?
    public let password: String?
    public let hasPassword: Bool
    public let uris: [String]
    /// The seed itself stays at the crypto/data boundary.
    public let hasTotp: Bool
    public let hasPasskeys: Bool
    public init(
        username: String?,
        password: String?,
        hasPassword: Bool,
        uris: [String],
        hasTotp: Bool,
        hasPasskeys: Bool
    ) {
        self.username = username; self.password = password; self.hasPassword = hasPassword
        self.uris = uris; self.hasTotp = hasTotp; self.hasPasskeys = hasPasskeys
    }

    public var description: String { "VaultLoginDetail(<redacted>)" }
    public var debugDescription: String { description }
}

public struct VaultCardDetail: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let cardholderName: String?
    public let number: String?
    public let expiration: String
    public let securityCode: String?
    public init(cardholderName: String?, number: String?, expiration: String, securityCode: String?) {
        self.cardholderName = cardholderName; self.number = number
        self.expiration = expiration; self.securityCode = securityCode
    }

    public var description: String { "VaultCardDetail(<redacted>)" }
    public var debugDescription: String { description }
}

public struct VaultIdentityDetail: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let fullName: String
    public let username: String?
    public let email: String?
    public let phone: String?
    public init(fullName: String, username: String?, email: String?, phone: String?) {
        self.fullName = fullName; self.username = username; self.email = email; self.phone = phone
    }

    public var description: String { "VaultIdentityDetail(<redacted>)" }
    public var debugDescription: String { description }
}

public struct VaultSSHKeyDetail: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let publicKey: String?
    public let privateKey: String?
    public let fingerprint: String?
    public init(publicKey: String?, privateKey: String?, fingerprint: String?) {
        self.publicKey = publicKey; self.privateKey = privateKey; self.fingerprint = fingerprint
    }

    public var description: String { "VaultSSHKeyDetail(<redacted>)" }
    public var debugDescription: String { description }
}

public struct VaultAttachmentReference: Equatable, Hashable, Sendable {
    public let cipherID: CipherID
    public let attachmentID: AttachmentID
    public init(cipherID: CipherID, attachmentID: AttachmentID) {
        self.cipherID = cipherID; self.attachmentID = attachmentID
    }
}

public struct VaultAttachmentSummary: Equatable, Sendable {
    public let reference: VaultAttachmentReference?
    public let fileName: String
    public let sizeName: String?
    public let canDownload: Bool
    public init(reference: VaultAttachmentReference?, fileName: String, sizeName: String?, canDownload: Bool) {
        self.reference = reference; self.fileName = fileName; self.sizeName = sizeName; self.canDownload = canDownload
    }
}

/// Display fields only: no credential keyValue, userHandle or SDK credential in feature state.
public struct VaultPasskeySummary: Equatable, Sendable, Identifiable {
    public let id: String
    public let relyingPartyName: String
    public let userName: String?
    public init(id: String, relyingPartyName: String, userName: String?) {
        self.id = id; self.relyingPartyName = relyingPartyName; self.userName = userName
    }
}

public struct VaultOneTimeCode: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let context: VaultItemContext
    public let code: String
    public let period: UInt32
    public init(context: VaultItemContext, code: String, period: UInt32) {
        self.context = context; self.code = code; self.period = period
    }

    public var description: String { "VaultOneTimeCode(<redacted>)" }
    public var debugDescription: String { description }
}

public struct VaultFolderSummary: Equatable, Sendable, Identifiable {
    public let id: FolderID
    public let name: String
    public init(id: FolderID, name: String) { self.id = id; self.name = name }
}

public struct VaultCollectionSummary: Equatable, Sendable, Identifiable {
    public let id: CollectionID
    public let organizationID: OrganizationID
    public let name: String
    public let isReadOnly: Bool
    public let hidesPasswords: Bool
    public init(id: CollectionID, organizationID: OrganizationID, name: String, isReadOnly: Bool, hidesPasswords: Bool) {
        self.id = id; self.organizationID = organizationID; self.name = name
        self.isReadOnly = isReadOnly; self.hidesPasswords = hidesPasswords
    }
}

public extension VaultItemSummary {
    func matches(searchQuery: String) -> Bool {
        guard !searchQuery.isEmpty else { return true }
        let query = searchQuery.lowercased()
        return ([name] + searchTerms).contains { $0.lowercased().contains(query) }
    }
}
