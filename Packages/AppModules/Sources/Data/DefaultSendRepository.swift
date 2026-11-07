import Domain
import Foundation
import Networking
import SecurityStorage

/// Session-scoped Send data authority. It owns the encrypted server snapshot, cancellation
/// lifetime, file upload choreography and post-mutation projection; presentation only receives
/// Domain summaries/details.
public actor DefaultSendRepository: SendRepository {
    private let runtime: SessionRuntime
    private let http: any HTTPClient
    private let cryptography: any SendCryptography
    private let temporaryFiles: any SensitiveFileWorking
    private var records: [SendID: SendRecord] = [:]
    private var summaries: [SendSummary] = []
    private var isClosed = false
    private var operationActive = false
    private var operationWaiters: [CheckedContinuation<Void, Never>] = []

    // Read-only, module-internal queue inspection for deterministic gated regression fixtures.
    // No caller can mutate the queue or release an operation through this seam.
    var queuedOperationCount: Int { operationWaiters.count }

    public init(
        runtime: SessionRuntime,
        cryptography: any SendCryptography,
        http: any HTTPClient,
        temporaryFiles: any SensitiveFileWorking = SensitiveTemporaryFileStore.shared
    ) {
        self.runtime = runtime
        self.cryptography = cryptography
        self.http = http
        self.temporaryFiles = temporaryFiles
    }

    public func load() async throws -> [SendSummary] {
        await acquireOperation()
        defer { releaseOperation() }
        try checkOpen()
        let response = try await authorizedRequest(path: "sends", method: .get)
        let loaded: [SendRecord]
        do { loaded = try cryptography.decodeList(response.body) }
        catch let error as SendRepositoryError { throw error }
        catch { throw SendRepositoryError.invalidResponse }
        try checkOpen()
        records.removeAll(keepingCapacity: true)
        for record in loaded { records[record.id] = record }
        summaries = Self.makeSnapshot(records.values)
        return summaries
    }

    public func details(for id: SendID) async throws -> SendDetails {
        try checkOpen()
        guard let record = records[id] else { throw SendRepositoryError.itemUnavailable }
        do {
            let value = try cryptography.details(for: record)
            try checkOpen()
            return value
        } catch let error as SendRepositoryError { throw error }
        catch { throw SendRepositoryError.cryptoFailure }
    }

    public func editDraft(for id: SendID) async throws -> SendDraft {
        try checkOpen()
        guard let record = records[id] else { throw SendRepositoryError.itemUnavailable }
        do {
            let value = try cryptography.editDraft(for: record)
            try checkOpen()
            return value
        } catch let error as SendRepositoryError { throw error }
        catch { throw SendRepositoryError.cryptoFailure }
    }

    public func save(_ draft: SendDraft, file: (any ImportedFile)?) async throws -> [SendSummary] {
        try checkOpen()
        // Once submitted, caller/UI cancellation cannot abandon a server-acknowledged mutation
        // before repository state is projected. Runtime revocation still cancels scoped I/O.
        let operation = Task { try await self.performSave(draft, file: file) }
        let result = try await operation.value
        try checkSessionActive()
        return result
    }

    public func delete(id: SendID) async throws -> [SendSummary] {
        try checkOpen()
        guard records[id] != nil, Self.isSafeIdentifier(id.rawValue) else {
            throw SendRepositoryError.itemUnavailable
        }
        let operation = Task { try await self.performDelete(id: id) }
        let result = try await operation.value
        try checkSessionActive()
        return result
    }

    public func shareLink(for id: SendID) async throws -> URL {
        try checkOpen()
        guard let record = records[id] else { throw SendRepositoryError.itemUnavailable }
        do {
            let url = try cryptography.shareLink(for: record, webVaultURL: runtime.account.environment.webVaultURL)
            try checkOpen()
            return url
        } catch let error as SendRepositoryError { throw error }
        catch { throw SendRepositoryError.cryptoFailure }
    }

    public func lock() async {
        isClosed = true
        records.removeAll(keepingCapacity: false)
        summaries.removeAll(keepingCapacity: false)
    }

    private func performSave(_ draft: SendDraft, file: (any ImportedFile)?) async throws -> [SendSummary] {
        await acquireOperation()
        defer { releaseOperation() }
        try checkOpen()
        let existing: SendRecord?
        if let id = draft.editingID {
            guard Self.isSafeIdentifier(id.rawValue), let value = records[id] else {
                throw SendRepositoryError.itemUnavailable
            }
            existing = value
        } else {
            existing = nil
        }

        if draft.contentKind == .file, draft.editingID == nil {
            guard let file else { throw SendRepositoryError.invalidDraft }
            return try await performFileSave(draft, file: file)
        }
        try checkOpen()

        let prepared: PreparedSendMutation
        do { prepared = try cryptography.prepare(draft, existing: existing) }
        catch let error as SendRepositoryError { throw error }
        catch { throw SendRepositoryError.cryptoFailure }
        try checkOpen()

        let response: HTTPResponse
        if let id = draft.editingID {
            response = try await authorizedRequest(
                path: "sends/\(id.rawValue)", method: .put, body: prepared.requestBody, mutation: true
            )
        } else {
            response = try await authorizedRequest(
                path: "sends",
                method: .post,
                body: prepared.requestBody,
                mutation: true
            )
        }
        let updated: SendRecord
        do { updated = try cryptography.decodeResponse(response.body) }
        catch { throw SendRepositoryError.mutationOutcomeUnknown }
        try checkOpen()
        records[updated.id] = updated
        summaries = Self.makeSnapshot(records.values)

        if let id = draft.editingID, draft.shouldRemovePassword {
            do {
                let removed = try await authorizedRequest(
                    path: "sends/\(id.rawValue)/remove-password", method: .put
                )
                let finalRecord = try cryptography.decodeResponse(removed.body)
                try checkOpen()
                records[finalRecord.id] = finalRecord
                summaries = Self.makeSnapshot(records.values)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try checkOpen()
                throw SendRepositoryError.committedButFollowUpFailed
            }
        }
        return summaries
    }

    private func performDelete(id: SendID) async throws -> [SendSummary] {
        await acquireOperation()
        defer { releaseOperation() }
        try checkOpen()
        guard records[id] != nil else { throw SendRepositoryError.itemUnavailable }
        _ = try await authorizedRequest(path: "sends/\(id.rawValue)", method: .delete)
        try checkOpen()
        records.removeValue(forKey: id)
        summaries = Self.makeSnapshot(records.values)
        return summaries
    }

    private func performFileSave(_ draft: SendDraft, file: any ImportedFile) async throws -> [SendSummary] {
        let directory: URL
        do { directory = try await temporaryFiles.makeWorkDirectory() }
        catch is CancellationError { throw CancellationError() }
        catch { throw SendRepositoryError.filePreparationFailed }
        var registered = false
        var uploaded = false
        let result: [SendSummary]
        do {
            try checkOpen()
            let encryptedURL = try await temporaryFiles.makeSensitiveFile(in: directory, suggestedName: "encrypted.data")
            try checkOpen()
            let cryptography = cryptography
            let runtime = runtime
            let prepared = try await file.withSecurityScopedAccess { inputURL in
                try runtime.checkAccess()
                let prepared = try cryptography.prepareFile(draft, plaintextURL: inputURL, encryptedURL: encryptedURL)
                try runtime.checkAccess()
                return prepared
            }
            try checkOpen()
            guard prepared.encryptedFileURL.standardizedFileURL == encryptedURL.standardizedFileURL else {
                throw SendRepositoryError.invalidResponse
            }
            try await temporaryFiles.protectFile(at: encryptedURL)
            try checkOpen()
            let response = try await authorizedRequest(
                path: "sends/file/v2",
                method: .post,
                body: prepared.requestBody,
                mutation: true
            )
            registered = true
            let ticket = try cryptography.decodeFileUploadTicket(response.body)
            try checkOpen()
            records[ticket.record.id] = ticket.record
            summaries = Self.makeSnapshot(records.values)
            try await upload(prepared, using: ticket, directory: directory)
            uploaded = true
            try checkOpen()
            result = summaries
        } catch let operationError {
            do { try await temporaryFiles.removeWorkDirectory(directory) }
            catch {
                if registered {
                    throw uploaded ? SendRepositoryError.committedButCleanupFailed : .fileUploadAndCleanupFailed
                }
                if operationError as? SendRepositoryError == .mutationOutcomeUnknown {
                    throw SendRepositoryError.mutationOutcomeUnknownAndCleanupFailed
                }
                throw SendRepositoryError.temporaryCleanupFailed
            }
            if operationError is CancellationError { throw CancellationError() }
            if registered { throw SendRepositoryError.fileUploadFailed }
            if let error = operationError as? SendRepositoryError { throw error }
            throw SendRepositoryError.filePreparationFailed
        }
        do { try await temporaryFiles.removeWorkDirectory(directory) }
        catch { throw SendRepositoryError.committedButCleanupFailed }
        return result
    }

    private func upload(_ prepared: PreparedSendFileMutation, using ticket: SendFileUploadTicket, directory: URL) async throws {
        switch ticket.uploadKind {
        case .direct:
            guard Self.isSafeIdentifier(ticket.record.id.rawValue), Self.isSafeIdentifier(ticket.fileID),
                  Self.isSafeMultipartFilename(ticket.encryptedFileName)
            else { throw SendRepositoryError.invalidResponse }
            let runtime = runtime
            let body = try MultipartFileBody.prepare(
                inputURL: prepared.encryptedFileURL,
                outputURL: directory.appendingPathComponent("multipart.data"),
                fileName: ticket.encryptedFileName,
                boundary: "Boundary-\(UUID().uuidString)",
                preserveSlashesInFileName: true,
                checkAccess: { try runtime.checkAccess() }
            )
            let path = "sends/\(ticket.record.id.rawValue)/file/\(ticket.fileID)"
            let http = http
            try await runtime.perform {
                let token = try await runtime.requireAccessToken()
                let request = HTTPRequest(
                    url: runtime.account.environment.apiURL.appendingPathComponent(path), method: .post,
                    headers: ["Authorization": "Bearer \(token)", "Accept": "application/json",
                              "Content-Type": body.contentType, "Content-Length": String(body.byteCount)],
                    redirectPolicy: .reject
                )
                try runtime.checkAccess()
                let response = try await http.upload(request, fromFile: body.fileURL)
                try runtime.checkAccess()
                guard response.isSuccess else { throw SendRepositoryError.server(statusCode: response.statusCode) }
            }
        case .azure:
            guard ticket.uploadURL.scheme?.lowercased() == "https", ticket.uploadURL.host?.isEmpty == false,
                  ticket.uploadURL.user == nil, ticket.uploadURL.password == nil, ticket.uploadURL.fragment == nil else {
                throw SendRepositoryError.invalidResponse
            }
            var headers = ["x-ms-blob-type": "BlockBlob", "Content-Type": "application/octet-stream",
                           "Content-Length": String(prepared.byteCount)]
            if let version = URLComponents(url: ticket.uploadURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "sv" })?.value,
                Self.isSafeHeaderValue(version) {
                headers["x-ms-version"] = version
            }
            let request = HTTPRequest(
                url: ticket.uploadURL, method: .put, headers: headers, redirectPolicy: .reject
            )
            let runtime = runtime
            let http = http
            try await runtime.perform {
                try runtime.checkAccess()
                let response = try await http.upload(request, fromFile: prepared.encryptedFileURL)
                try runtime.checkAccess()
                guard response.isSuccess else { throw SendRepositoryError.server(statusCode: response.statusCode) }
            }
        }
    }

    private func authorizedRequest(
        path: String,
        method: HTTPRequest.Method,
        body: Data? = nil,
        contentType: String? = nil,
        mutation: Bool = false
    ) async throws -> HTTPResponse {
        guard path.split(separator: "/").allSatisfy({ Self.isSafeIdentifier(String($0)) }) else {
            throw SendRepositoryError.invalidResponse
        }
        let runtime = runtime
        let http = http
        return try await runtime.perform {
            let token = try await runtime.requireAccessToken()
            var headers = ["Authorization": "Bearer \(token)", "Accept": "application/json"]
            if body != nil {
                headers["Content-Type"] = contentType ?? "application/json"
            }
            let url = runtime.account.environment.apiURL.appendingPathComponent(path)
            try runtime.checkAccess()
            let response: HTTPResponse
            do {
                response = try await http.send(HTTPRequest(
                    url: url, method: method, headers: headers, body: body, redirectPolicy: .reject
                ))
            } catch {
                try runtime.checkAccess()
                if mutation { throw SendRepositoryError.mutationOutcomeUnknown }
                throw error
            }
            try runtime.checkAccess()
            if mutation, !response.isSuccess,
               !(400 ... 499).contains(response.statusCode) || [408, 409, 429].contains(response.statusCode) {
                throw SendRepositoryError.mutationOutcomeUnknown
            }
            guard response.isSuccess else { throw SendRepositoryError.server(statusCode: response.statusCode) }
            return response
        }
    }

    private func checkOpen() throws {
        try runtime.checkAccess()
        guard !isClosed else { throw SendRepositoryError.sessionUnavailable }
    }

    private func checkSessionActive() throws {
        try runtime.checkSessionActive()
        guard !isClosed else { throw SendRepositoryError.sessionUnavailable }
    }

    private func acquireOperation() async {
        if !operationActive { operationActive = true; return }
        await withCheckedContinuation { operationWaiters.append($0) }
    }

    private func releaseOperation() {
        if operationWaiters.isEmpty { operationActive = false }
        else { operationWaiters.removeFirst().resume() }
    }

    private static func makeSnapshot<S: Sequence>(_ records: S) -> [SendSummary] where S.Element == SendRecord {
        records.map(\.summary).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func isSafeIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy {
            (0x30 ... 0x39).contains($0) || (0x41 ... 0x5A).contains($0)
                || (0x61 ... 0x7A).contains($0) || $0 == 0x2D || $0 == 0x5F
        }
    }

    private static func isSafeMultipartFilename(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (0x21 ... 0x7E).contains($0) && $0 != 0x22 && $0 != 0x5C }
    }

    private static func isSafeHeaderValue(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (0x20 ... 0x7E).contains($0) }
    }
}
