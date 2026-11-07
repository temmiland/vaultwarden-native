import Foundation

public enum SendContentKind: Sendable, Equatable {
    case text
    case file
}

/// Display-safe row data. Names can still be user-sensitive, so accidental debug logging is
/// deliberately uninformative.
public struct SendSummary: Sendable, Equatable, Identifiable, CustomStringConvertible, CustomDebugStringConvertible {
    public let id: SendID
    public let name: String
    public let contentKind: SendContentKind
    public let isDisabled: Bool
    public let expirationDate: Date?
    public let deletionDate: Date
    public let canOpen: Bool

    public init(
        id: SendID,
        name: String,
        contentKind: SendContentKind,
        isDisabled: Bool,
        expirationDate: Date?,
        deletionDate: Date,
        canOpen: Bool = true
    ) {
        self.id = id
        self.name = name
        self.contentKind = contentKind
        self.isDisabled = isDisabled
        self.expirationDate = expirationDate
        self.deletionDate = deletionDate
        self.canOpen = canOpen
    }

    public var description: String { "SendSummary(<redacted>)" }
    public var debugDescription: String { description }
}

/// Opaque, encrypted wire record held by Data. Only the SDK adapter may decode its payload.
public struct SendRecord: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let id: SendID
    public let encryptedPayload: Data
    public let summary: SendSummary

    public init(id: SendID, encryptedPayload: Data, summary: SendSummary) {
        self.id = id
        self.encryptedPayload = encryptedPayload
        self.summary = summary
    }

    public var description: String { "SendRecord(<redacted>)" }
    public var debugDescription: String { description }
}

/// Decrypted metadata used by the detail screen. Secret text, passwords, access IDs and keys are
/// intentionally not part of this projection.
public struct SendDetails: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let id: SendID
    public let name: String
    public let contentKind: SendContentKind
    public let notes: String?
    public let fileName: String?
    public let textHidden: Bool
    public let accessCount: UInt32
    public let maxAccessCount: UInt32?
    public let hasPassword: Bool
    public let hidesEmail: Bool
    public let isDisabled: Bool
    public let expirationDate: Date?
    public let deletionDate: Date

    public init(
        id: SendID,
        name: String,
        contentKind: SendContentKind,
        notes: String?,
        fileName: String?,
        textHidden: Bool,
        accessCount: UInt32,
        maxAccessCount: UInt32?,
        hasPassword: Bool,
        hidesEmail: Bool,
        isDisabled: Bool,
        expirationDate: Date?,
        deletionDate: Date
    ) {
        self.id = id
        self.name = name
        self.contentKind = contentKind
        self.notes = notes
        self.fileName = fileName
        self.textHidden = textHidden
        self.accessCount = accessCount
        self.maxAccessCount = maxAccessCount
        self.hasPassword = hasPassword
        self.hidesEmail = hidesEmail
        self.isDisabled = isDisabled
        self.expirationDate = expirationDate
        self.deletionDate = deletionDate
    }

    public var description: String { "SendDetails(<redacted>)" }
    public var debugDescription: String { description }
}

/// Editable presentation input. This can contain plaintext text/password; never log or persist it.
public struct SendDraft: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public var editingID: SendID?
    public var contentKind: SendContentKind
    public var name: String
    public var notes: String
    public var text: String
    public var textHidden: Bool
    public var pickedFileName: String?
    public var hasPasswordProtection: Bool
    public var password: String
    public var hadExistingPassword: Bool
    public var deletionDate: Date
    public var hasExpirationDate: Bool
    public var expirationDate: Date
    public var hasMaxAccessCount: Bool
    public var maxAccessCount: Int
    public var hidesEmail: Bool
    public var isDisabled: Bool

    public init(contentKind: SendContentKind) {
        editingID = nil
        self.contentKind = contentKind
        name = ""
        notes = ""
        text = ""
        textHidden = false
        pickedFileName = nil
        hasPasswordProtection = false
        password = ""
        hadExistingPassword = false
        deletionDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        hasExpirationDate = false
        expirationDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        hasMaxAccessCount = false
        maxAccessCount = 1
        hidesEmail = false
        isDisabled = false
    }

    public var shouldRemovePassword: Bool {
        editingID != nil && hadExistingPassword && !hasPasswordProtection
    }

    public var description: String { "SendDraft(<redacted>)" }
    public var debugDescription: String { description }
}

public enum SendItemFailure: Sendable, Equatable {
    case cannotDecrypt
}

public enum SendRepositoryError: Error, Sendable, Equatable {
    case sessionUnavailable
    case invalidResponse
    case mutationOutcomeUnknown
    case mutationOutcomeUnknownAndCleanupFailed
    case server(statusCode: Int)
    case itemUnavailable
    case invalidDraft
    case cryptoFailure
    case fileUploadFailed
    case committedButFollowUpFailed
    case temporaryCleanupFailed
    case committedButCleanupFailed
    case fileUploadAndCleanupFailed
    case filePreparationFailed
}

public struct PreparedSendMutation: Sendable {
    public let requestBody: Data

    public init(requestBody: Data) {
        self.requestBody = requestBody
    }
}

/// Transient file capability for one repository-owned upload. No file bytes cross this port.
public struct PreparedSendFileMutation: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let requestBody: Data
    public let encryptedFileURL: URL
    public let byteCount: UInt64

    public init(requestBody: Data, encryptedFileURL: URL, byteCount: UInt64) {
        self.requestBody = requestBody
        self.encryptedFileURL = encryptedFileURL
        self.byteCount = byteCount
    }

    public var description: String { "PreparedSendFileMutation(<redacted>)" }
    public var debugDescription: String { description }
}

public enum SendUploadKind: Int, Sendable, Equatable {
    case direct = 0
    case azure = 1
}

public struct SendFileUploadTicket: Sendable {
    public let record: SendRecord
    public let uploadURL: URL
    public let uploadKind: SendUploadKind
    public let fileID: String
    public let encryptedFileName: String

    public init(
        record: SendRecord,
        uploadURL: URL,
        uploadKind: SendUploadKind,
        fileID: String,
        encryptedFileName: String
    ) {
        self.record = record
        self.uploadURL = uploadURL
        self.uploadKind = uploadKind
        self.fileID = fileID
        self.encryptedFileName = encryptedFileName
    }
}

/// SDK boundary used by the Data repository. Its public surface contains only Domain values and
/// opaque encrypted metadata. File contents cross only a scoped URL/file capability, not Data.
public protocol SendCryptography: Sendable {
    func decodeList(_ response: Data) throws -> [SendRecord]
    func decodeResponse(_ response: Data) throws -> SendRecord
    func decodeFileUploadTicket(_ response: Data) throws -> SendFileUploadTicket
    func details(for record: SendRecord) throws -> SendDetails
    func editDraft(for record: SendRecord) throws -> SendDraft
    func prepare(_ draft: SendDraft, existing: SendRecord?) throws -> PreparedSendMutation
    func prepareFile(_ draft: SendDraft, plaintextURL: URL, encryptedURL: URL) throws -> PreparedSendFileMutation
    func shareLink(for record: SendRecord, webVaultURL: URL) throws -> URL
}

/// Every mutation returns the authoritative repository projection. Presentation never patches a
/// second, potentially stale copy of the server list.
public protocol SendRepository: Sendable {
    func load() async throws -> [SendSummary]
    func details(for id: SendID) async throws -> SendDetails
    func editDraft(for id: SendID) async throws -> SendDraft
    func save(_ draft: SendDraft, file: (any ImportedFile)?) async throws -> [SendSummary]
    func delete(id: SendID) async throws -> [SendSummary]
    func shareLink(for id: SendID) async throws -> URL
    func lock() async
}
