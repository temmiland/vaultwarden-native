import BitwardenSdk
import Foundation

// Wire-format DTOs mirroring the Bitwarden server's `AttachmentResponseModel` /
// `AttachmentRequestModel` / `AttachmentUploadDataResponseModel` (see bitwarden-api-api's generated
// Rust models). As with `CipherDTO.swift`, these only ever move still-encrypted bytes/metadata
// between the wire and the SDK's domain types - no attachment plaintext is ever represented here.

/// Mirrors `AttachmentResponseModel`. Appears both nested in `CipherResponseDTO.attachments` and as
/// the response of the single-attachment `GET /ciphers/{id}/attachment/{attachmentId}` endpoint
/// (used to fetch a fresh download `url` right before pulling the encrypted bytes).
public struct AttachmentResponseDTO: Codable, Sendable {
    public var id: String?
    public var url: String?
    public var fileName: String?
    public var key: String?
    public var size: String?
    public var sizeName: String?

    public init(id: String?, url: String?, fileName: String?, key: String?, size: String?, sizeName: String?) {
        self.id = id
        self.url = url
        self.fileName = fileName
        self.key = key
        self.size = size
        self.sizeName = sizeName
    }
}

/// Mirrors `AttachmentRequestModel` - the body of `POST /ciphers/{id}/attachment/v2`, which creates
/// the attachment's metadata record and hands back an upload target before any file bytes move.
public struct AttachmentRequestDTO: Codable, Sendable {
    public var key: String?
    public var fileName: String?
    public var fileSize: UInt64?

    public init(key: String?, fileName: String?, fileSize: UInt64?) {
        self.key = key
        self.fileName = fileName
        self.fileSize = fileSize
    }
}

/// Mirrors `AttachmentUploadDataResponseModel`. `fileUploadType` is `0` (Direct) or `1` (Azure) -
/// Vaultwarden, since it stores files itself rather than proxying to Azure Blob Storage like
/// bitwarden.com, always returns `0`. `url` is where the encrypted bytes get POSTed next.
public struct AttachmentUploadDataResponseDTO: Codable, Sendable {
    public var attachmentId: String?
    public var url: String?
    public var fileUploadType: Int?

    public init(attachmentId: String?, url: String?, fileUploadType: Int?) {
        self.attachmentId = attachmentId
        self.url = url
        self.fileUploadType = fileUploadType
    }
}

public enum AttachmentFileUploadType: Int {
    case direct = 0
    case azure = 1
}

public extension AttachmentResponseDTO {
    /// Maps into the SDK's `Attachment` (server-layer domain type, still fully encrypted) so it can
    /// be handed to `AttachmentsClient.decryptFile`. `EncString` is a plain `String` wire alias, so
    /// this is a direct field-for-field copy - no crypto happens here.
    func toSDKAttachment() -> Attachment {
        Attachment(id: id, url: url, size: size, sizeName: sizeName, fileName: fileName, key: key)
    }
}
