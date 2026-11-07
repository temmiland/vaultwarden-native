import BitwardenSdk
import Domain
import Foundation

/// Maps opaque server ciphertext records to the SDK's Send model and keeps all plaintext
/// encryption/decryption on the SDK side of the application boundary.
public struct SDKSendCryptography: SendCryptography, Sendable {
    private let crypto: any SendCryptoServicing

    public init(crypto: any SendCryptoServicing) { self.crypto = crypto }

    public func decodeList(_ response: Data) throws -> [SendRecord] {
        let envelope: SendListResponseDTO
        do { envelope = try JSONDecoder().decode(SendListResponseDTO.self, from: response) }
        catch { throw SendRepositoryError.invalidResponse }
        return try (envelope.data ?? []).map(makeRecord)
    }

    public func decodeResponse(_ response: Data) throws -> SendRecord {
        let dto: SendResponseDTO
        do { dto = try JSONDecoder().decode(SendResponseDTO.self, from: response) }
        catch { throw SendRepositoryError.invalidResponse }
        return try makeRecord(dto)
    }

    public func decodeFileUploadTicket(_ response: Data) throws -> SendFileUploadTicket {
        let dto: SendFileUploadDataResponseDTO
        do { dto = try JSONDecoder().decode(SendFileUploadDataResponseDTO.self, from: response) }
        catch { throw SendRepositoryError.invalidResponse }
        guard let uploadURLString = dto.url, let uploadURL = URL(string: uploadURLString),
              let type = dto.fileUploadType, let uploadKind = Domain.SendUploadKind(rawValue: type),
              let sendResponse = dto.sendResponse
        else { throw SendRepositoryError.invalidResponse }
        if uploadKind == .azure,
           uploadURL.scheme?.lowercased() != "https" || uploadURL.host?.isEmpty != false ||
           uploadURL.user != nil || uploadURL.password != nil || uploadURL.fragment != nil {
            throw SendRepositoryError.invalidResponse
        }
        let record = try makeRecord(sendResponse)
        let encryptedFileName = sendResponse.file?.fileName
        guard let fileID = sendResponse.file?.id, let encryptedFileName else {
            throw SendRepositoryError.invalidResponse
        }
        return SendFileUploadTicket(
            record: record, uploadURL: uploadURL, uploadKind: uploadKind,
            fileID: fileID, encryptedFileName: encryptedFileName
        )
    }

    public func details(for record: SendRecord) throws -> SendDetails {
        let view = try decrypt(record)
        guard let rawID = view.id, !rawID.isEmpty else { throw SendRepositoryError.invalidResponse }
        return SendDetails(
            id: SendID(rawValue: rawID),
            name: view.name,
            contentKind: view.type == .file ? .file : .text,
            notes: view.notes,
            fileName: view.file?.fileName,
            textHidden: view.text?.hidden ?? false,
            accessCount: view.accessCount,
            maxAccessCount: view.maxAccessCount,
            hasPassword: view.hasPassword,
            hidesEmail: view.hideEmail,
            isDisabled: view.disabled,
            expirationDate: view.expirationDate,
            deletionDate: view.deletionDate
        )
    }

    public func editDraft(for record: SendRecord) throws -> SendDraft {
        let view = try decrypt(record)
        guard let rawID = view.id, !rawID.isEmpty else { throw SendRepositoryError.invalidResponse }
        var draft = SendDraft(contentKind: view.type == .file ? .file : .text)
        draft.editingID = SendID(rawValue: rawID)
        draft.name = view.name
        draft.notes = view.notes ?? ""
        draft.text = view.text?.text ?? ""
        draft.textHidden = view.text?.hidden ?? false
        draft.pickedFileName = view.file?.fileName
        draft.hasPasswordProtection = view.hasPassword
        draft.hadExistingPassword = view.hasPassword
        draft.deletionDate = view.deletionDate
        draft.hasExpirationDate = view.expirationDate != nil
        draft.expirationDate = view.expirationDate ?? Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date(
        )
        draft.hasMaxAccessCount = view.maxAccessCount != nil
        draft.maxAccessCount = view.maxAccessCount.map(Int.init) ?? 1
        draft.hidesEmail = view.hideEmail
        draft.isDisabled = view.disabled
        return draft
    }

    public func prepare(_ draft: SendDraft, existing record: SendRecord?) throws -> PreparedSendMutation {
        guard draft.contentKind != .file || record != nil else { throw SendRepositoryError.invalidDraft }
        let existingView: SendView?
        if let record { existingView = try decrypt(record) }
        else { existingView = nil }
        let sendView = try Self.sdkView(from: draft, existing: existingView)
        let encrypted: Send
        do { encrypted = try crypto.encrypt(sendView) }
        catch { throw SendRepositoryError.cryptoFailure }

        do {
            let body = try JSONEncoder().encode(SendRequestDTO(send: encrypted, fileLength: nil))
            return PreparedSendMutation(requestBody: body)
        } catch {
            throw SendRepositoryError.invalidResponse
        }
    }

    public func prepareFile(_ draft: SendDraft, plaintextURL: URL, encryptedURL: URL) throws -> PreparedSendFileMutation {
        try Task.checkCancellation()
        guard draft.contentKind == .file, draft.editingID == nil,
              plaintextURL.isFileURL, encryptedURL.isFileURL,
              plaintextURL.standardizedFileURL != encryptedURL.standardizedFileURL else {
            throw SendRepositoryError.invalidDraft
        }
        // The importer retains scoped access through the synchronous SDK call. Reject obvious
        // symlink/nonregular sources/destinations; the upstream SDK still reopens paths and reads
        // whole files. This validation is not an atomic FD handoff or a constant-heap guarantee.
        _ = try Self.regularFileSize(at: plaintextURL)
        _ = try Self.regularFileSize(at: encryptedURL)
        let sendView = try Self.sdkView(from: draft, existing: nil)
        let encrypted: Send
        do {
            encrypted = try crypto.encrypt(sendView)
            try Task.checkCancellation()
            try crypto.encryptFile(send: encrypted, plaintextURL: plaintextURL, encryptedURL: encryptedURL)
        } catch is CancellationError { throw CancellationError() }
        catch { throw SendRepositoryError.cryptoFailure }
        try Task.checkCancellation()
        let byteCount = try Self.regularFileSize(at: encryptedURL)
        do {
            return try PreparedSendFileMutation(
                requestBody: JSONEncoder().encode(SendRequestDTO(send: encrypted, fileLength: byteCount)),
                encryptedFileURL: encryptedURL,
                byteCount: byteCount
            )
        } catch { throw SendRepositoryError.invalidResponse }
    }

    private static func regularFileSize(at url: URL) throws -> UInt64 {
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: url.path) }
        catch { throw SendRepositoryError.invalidDraft }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber else { throw SendRepositoryError.invalidDraft }
        return size.uint64Value
    }

    public func shareLink(for record: SendRecord, webVaultURL: URL) throws -> URL {
        let view = try decrypt(record)
        guard let accessID = view.accessId, !accessID.isEmpty,
              let key = view.key, !key.isEmpty,
              let components = URLComponents(url: webVaultURL, resolvingAgainstBaseURL: false)
        else { throw SendRepositoryError.invalidResponse }
        var normalized = components
        if normalized.path.isEmpty {
            normalized.path = "/"
        } else if normalized.path != "/", normalized.path.hasSuffix("/") {
            normalized.path.removeLast()
        }
        normalized.fragment = "/send/\(accessID)/\(Self.urlSafeBase64(key))"
        guard let url = normalized.url else { throw SendRepositoryError.invalidResponse }
        return url
    }

    private func makeRecord(_ dto: SendResponseDTO) throws -> SendRecord {
        let send: Send
        do { send = try dto.toSDKSend() }
        catch { throw SendRepositoryError.invalidResponse }
        guard let rawID = send.id, !rawID.isEmpty else { throw SendRepositoryError.invalidResponse }
        let summary: SendSummary
        do {
            let view = try crypto.decrypt(send)
            summary = SendSummary(
                id: SendID(rawValue: rawID), name: view.name,
                contentKind: view.type == .file ? .file : .text,
                isDisabled: view.disabled, expirationDate: view.expirationDate,
                deletionDate: view.deletionDate
            )
        } catch {
            summary = SendSummary(
                id: SendID(rawValue: rawID), name: "Unable to decrypt Send",
                contentKind: send.type == .file ? .file : .text,
                isDisabled: send.disabled, expirationDate: send.expirationDate,
                deletionDate: send.deletionDate, canOpen: false
            )
        }
        let payload: Data
        do { payload = try JSONEncoder().encode(dto) }
        catch { throw SendRepositoryError.invalidResponse }
        return SendRecord(id: SendID(rawValue: rawID), encryptedPayload: payload, summary: summary)
    }

    private func decrypt(_ record: SendRecord) throws -> SendView {
        let dto: SendResponseDTO
        let send: Send
        do {
            dto = try JSONDecoder().decode(SendResponseDTO.self, from: record.encryptedPayload)
            send = try dto.toSDKSend()
        } catch {
            throw SendRepositoryError.invalidResponse
        }
        do { return try crypto.decrypt(send) }
        catch { throw SendRepositoryError.cryptoFailure }
    }

    private static func sdkView(from draft: SendDraft, existing: SendView?) throws -> SendView {
        let maxAccessCount: UInt32?
        if draft.hasMaxAccessCount {
            guard draft.maxAccessCount > 0, let value = UInt32(exactly: draft.maxAccessCount) else {
                throw SendRepositoryError.invalidDraft
            }
            maxAccessCount = value
        } else { maxAccessCount = nil }
        if let existing, (existing.type == .file) != (draft.contentKind == .file) {
            throw SendRepositoryError.invalidDraft
        }
        guard draft.deletionDate.timeIntervalSince1970.isFinite,
              !draft.hasExpirationDate || draft.expirationDate.timeIntervalSince1970.isFinite else {
            throw SendRepositoryError.invalidDraft
        }
        let file = draft.contentKind == .file
            ? SendFileView(
                id: existing?.file?.id,
                fileName: draft.pickedFileName ?? existing?.file?.fileName ?? "",
                size: existing?.file?.size,
                sizeName: existing?.file?.sizeName
            )
            : nil
        let text = draft.contentKind == .text ? SendTextView(text: draft.text, hidden: draft.textHidden) : nil
        return SendView(
            id: existing?.id,
            accessId: existing?.accessId,
            name: draft.name,
            notes: draft.notes.isEmpty ? nil : draft.notes,
            key: existing?.key,
            newPassword: draft.hasPasswordProtection && !draft.password.isEmpty ? draft.password : nil,
            hasPassword: existing?.hasPassword ?? false,
            type: draft.contentKind == .file ? .file : .text,
            file: file,
            text: text,
            maxAccessCount: maxAccessCount,
            accessCount: existing?.accessCount ?? 0,
            disabled: draft.isDisabled,
            hideEmail: draft.hidesEmail,
            revisionDate: existing?.revisionDate ?? Date(),
            deletionDate: draft.deletionDate,
            expirationDate: draft.hasExpirationDate ? draft.expirationDate : nil,
            emails: existing?.emails ?? [],
            authType: existing?.authType ?? .none
        )
    }

    private static func urlSafeBase64(_ value: String) -> String {
        value.replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private struct SendFileResponseDTO: Codable {
    var id: String?
    var fileName: String?
    var size: String?
    var sizeName: String?
}

private struct SendTextResponseDTO: Codable {
    var text: String?
    var hidden: Bool?
}

private struct SendResponseDTO: Codable {
    var object: String?
    var id: String?
    var accessId: String?
    var type: Int?
    var authType: Int?
    var name: String?
    var notes: String?
    var file: SendFileResponseDTO?
    var text: SendTextResponseDTO?
    var data: String?
    var key: String?
    var maxAccessCount: Int?
    var accessCount: Int?
    var password: String?
    var emails: String?
    var disabled: Bool?
    var revisionDate: String?
    var expirationDate: String?
    var deletionDate: String?
    var hideEmail: Bool?

    func toSDKSend() throws -> Send {
        guard let id, let name else { throw SendRepositoryError.invalidResponse }
        guard let rawType = type, let rawTypeByte = UInt8(exactly: rawType),
              let type = SendType(rawValue: rawTypeByte), type != .item
        else { throw SendRepositoryError.invalidResponse }
        guard let key else { throw SendRepositoryError.invalidResponse }
        guard let revisionDate = revisionDate.flatMap(Self.parseDate) else {
            throw SendRepositoryError.invalidResponse
        }
        guard let deletionDate = deletionDate.flatMap(Self.parseDate) else {
            throw SendRepositoryError.invalidResponse
        }
        let parsedExpirationDate: Date?
        if let expirationDate {
            guard let parsed = Self.parseDate(expirationDate) else { throw SendRepositoryError.invalidResponse }
            parsedExpirationDate = parsed
        } else {
            parsedExpirationDate = nil
        }
        let decodedAuthType: AuthType
        if let rawAuthType = authType {
            guard let rawAuthTypeByte = UInt8(exactly: rawAuthType),
                  let value = AuthType(rawValue: rawAuthTypeByte)
            else { throw SendRepositoryError.invalidResponse }
            decodedAuthType = value
        } else {
            decodedAuthType = .none
        }
        guard let accessCount = UInt32(exactly: accessCount ?? 0) else {
            throw SendRepositoryError.invalidResponse
        }
        let parsedMaxAccessCount = try Self.uint32(maxAccessCount)
        return Send(
            id: id, accessId: accessId, name: name, notes: notes, key: key, password: password,
            type: type,
            file: file.flatMap { value in
                guard let fileName = value.fileName else { return nil }
                return SendFile(id: value.id, fileName: fileName, size: value.size, sizeName: value.sizeName)
            },
            text: text.map { SendText(text: $0.text, hidden: $0.hidden ?? false) },
            maxAccessCount: parsedMaxAccessCount, accessCount: accessCount,
            disabled: disabled ?? false, hideEmail: hideEmail ?? false,
            revisionDate: revisionDate, deletionDate: deletionDate,
            expirationDate: parsedExpirationDate, emails: emails, authType: decodedAuthType
        )
    }

    private static func uint32(_ value: Int?) throws -> UInt32? {
        guard let value else { return nil }
        guard let result = UInt32(exactly: value) else { throw SendRepositoryError.invalidResponse }
        return result
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}

private struct SendListResponseDTO: Decodable {
    var object: String?
    var data: [SendResponseDTO]?
    var continuationToken: String?
}

private struct SendFileUploadDataResponseDTO: Decodable {
    var object: String?
    var url: String?
    var fileUploadType: Int?
    var sendResponse: SendResponseDTO?
}

private struct SendRequestDTO: Encodable {
    var type: Int
    var authType: Int
    var fileLength: UInt64?
    var name: String
    var notes: String?
    var key: String
    var maxAccessCount: Int?
    var expirationDate: String?
    var deletionDate: String
    var file: SendFileRequestDTO?
    var text: SendTextRequestDTO?
    var password: String?
    var emails: String?
    var disabled: Bool
    var hideEmail: Bool?

    init(send: Send, fileLength: UInt64?) {
        type = Int(send.type.rawValue)
        authType = send.password != nil ? Int(AuthType.password.rawValue) : Int(AuthType.none.rawValue)
        self.fileLength = fileLength
        name = send.name
        notes = send.notes
        key = send.key
        maxAccessCount = send.maxAccessCount.map(Int.init)
        expirationDate = send.expirationDate.map(Self.formatDate)
        deletionDate = Self.formatDate(send.deletionDate)
        file = send.file.map { SendFileRequestDTO(fileName: $0.fileName, size: nil, sizeName: nil) }
        text = send.text.map { SendTextRequestDTO(text: $0.text, hidden: $0.hidden) }
        password = send.password
        emails = send.emails
        disabled = send.disabled
        hideEmail = send.hideEmail
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

private struct SendFileRequestDTO: Encodable {
    var fileName: String?
    var size: String?
    var sizeName: String?
}

private struct SendTextRequestDTO: Encodable {
    var text: String?
    var hidden: Bool
}
