import Foundation

public extension VaultItemKind {
    static var editableKinds: [Self] { [.login, .secureNote, .card, .identity, .sshKey] }

    var supportsEditing: Bool { Self.editableKinds.contains(self) }
}

/// The values the existing form can edit. Hidden payloads, encryption keys, SDK values and
/// server DTOs deliberately stay in the adapter/repository rather than in this presentation model.
/// `baseRevision` protects against replacing locally refreshed data with an older open form;
/// it is not a server-side conditional-write guarantee.
public struct VaultItemDraft: Identifiable, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let editingID: CipherID?
    public let kind: VaultItemKind
    public let baseRevision: Date?
    public var id: String { editingID?.rawValue ?? "new" }

    public var name = ""
    public var notes = ""
    public var favorite = false
    public var folderID: FolderID?

    public var username = ""
    public var password = ""
    public var totpSeed = ""
    public var uris = [""]

    public var cardholderName = ""
    public var cardNumber = ""
    public var cardBrand = ""
    public var cardExpMonth = ""
    public var cardExpYear = ""
    public var cardCode = ""

    public var firstName = ""
    public var lastName = ""
    public var identityUsername = ""
    public var identityEmail = ""
    public var identityPhone = ""

    public var sshPrivateKey = ""
    public var sshPublicKey = ""
    public var sshFingerprint = ""

    public init(kind: VaultItemKind, folderID: FolderID? = nil) {
        self.init(editingID: nil, kind: kind, baseRevision: nil, folderID: folderID)
    }

    public init(editingID: CipherID?, kind: VaultItemKind, baseRevision: Date?, folderID: FolderID? = nil) {
        self.editingID = editingID
        self.kind = kind
        self.baseRevision = baseRevision
        self.folderID = folderID
    }

    // Swift's default struct descriptions reflect stored properties, including secrets. Neither
    // normal interpolation nor debug printing should accidentally log a form's contents.
    public var description: String { "VaultItemDraft(<redacted>)" }
    public var debugDescription: String { description }
}

public enum VaultItemDraftError: Error, Equatable, Sendable {
    case unsupportedItemKind
    case missingItem
    case draftMismatch
    case staleDraft
    case readOnly
}
