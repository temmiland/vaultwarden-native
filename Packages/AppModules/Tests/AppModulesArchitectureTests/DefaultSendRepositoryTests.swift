@testable import Data
import Domain
import Foundation
import Networking
@_spi(Testing) import SecurityStorage
import Testing

@Suite
struct DefaultSendRepositoryTests {
    @Test(arguments: [200, 302, 408, 409, 429, 500, 502])
    func unreadableSuccessOrAmbiguousStatusNeverInvitesBlindCreateRetry(status: Int) async throws {
        let http = SendHTTPFixture(responses: [response(status, "unreadable")])
        let repository = DefaultSendRepository(
            runtime: try makeRuntime(),
            cryptography: TestSendCryptography(),
            http: http
        )
        var draft = SendDraft(contentKind: .text)
        draft.name = "Synthetic"; draft.text = "Synthetic"
        await #expect(throws: SendRepositoryError.mutationOutcomeUnknown) {
            _ = try await repository.save(draft, file: nil)
        }
        #expect(await http.requests().count == 1)
    }

    @Test
    func definitelyRejectedCreateRemainsAnOrdinaryServerFailure() async throws {
        let http = SendHTTPFixture(responses: [response(400, "rejected")])
        let repository = DefaultSendRepository(
            runtime: try makeRuntime(),
            cryptography: TestSendCryptography(),
            http: http
        )
        var draft = SendDraft(contentKind: .text)
        draft.name = "Synthetic"; draft.text = "Synthetic"
        await #expect(throws: SendRepositoryError.server(statusCode: 400)) {
            _ = try await repository.save(draft, file: nil)
        }
    }

    @Test
    func transportFailureAfterSubmissionIsAnUnknownMutation() async throws {
        let http = SendHTTPFixture(failSend: true)
        let repository = DefaultSendRepository(
            runtime: try makeRuntime(),
            cryptography: TestSendCryptography(),
            http: http
        )
        var draft = SendDraft(contentKind: .text)
        draft.name = "Synthetic"; draft.text = "Synthetic"
        await #expect(throws: SendRepositoryError.mutationOutcomeUnknown) {
            _ = try await repository.save(draft, file: nil)
        }
        #expect(await http.requests().count == 1)
    }

    @Test
    func loadUsesSessionBearerRejectsRedirectsAndCachesOnlyDomainSummaries() async throws {
        let runtime = try makeRuntime()
        let http = SendHTTPFixture(responses: [response(200, "{}")])
        let crypto = TestSendCryptography(records: [record("send-1", name: "Example")])
        let repository = DefaultSendRepository(runtime: runtime, cryptography: crypto, http: http)

        let items = try await repository.load()

        #expect(items.map(\.name) == ["Example"])
        let request = try #require(await http.requests().first)
        #expect(request.url == URL(string: "https://vault.example.com/vault/api/sends")!)
        #expect(request.method == .get)
        #expect(request.headers["Authorization"] == "Bearer send-test-token")
        #expect(request.redirectPolicy == .reject)
    }

    @Test
    func serverErrorRemainsTypedWithoutRetainingResponseBody() async throws {
        let http = SendHTTPFixture(responses: [response(502, #"{"error":"private-response"}"#)])
        let repository = DefaultSendRepository(
            runtime: try makeRuntime(), cryptography: TestSendCryptography(), http: http
        )

        await #expect(throws: SendRepositoryError.server(statusCode: 502)) {
            try await repository.load()
        }
        #expect(!String(reflecting: SendRepositoryError.server(statusCode: 502)).contains("private-response"))
    }

    @Test
    func mutationProjectionSurvivesCancellationOfItsCaller() async throws {
        let http = SendHTTPFixture(gatedMethod: .post)
        let created = record("created", name: "Created")
        let repository = DefaultSendRepository(
            runtime: try makeRuntime(),
            cryptography: TestSendCryptography(responseRecord: created),
            http: http
        )
        var draft = SendDraft(contentKind: .text)
        draft.name = "Created"
        draft.text = "plaintext never sent by Data"

        let caller = Task { try await repository.save(draft, file: nil) }
        await http.waitForGatedRequest()
        caller.cancel()
        await http.resumeGatedRequest(with: response(200, "ciphertext response"))
        let projected = try await caller.value

        #expect(projected.map(\.id.rawValue) == ["created"])
        #expect(try await repository.details(for: SendID(rawValue: "created")).name == "Created")
        let request = try #require(await http.requests().first)
        #expect(request.url.path.hasSuffix("/sends"))
        #expect(request.method == .post)
        #expect(request.redirectPolicy == .reject)
        #expect(request.headers["Authorization"] == "Bearer send-test-token")
        #expect(request.body == Data("prepared-ciphertext".utf8))
    }

    @Test
    func updateAndDeleteUseTheExpectedResourceMethodsAndAuthoritativeSnapshot() async throws {
        let existing = record("send-1", name: "Before")
        let updated = record("send-1", name: "After")
        let http = SendHTTPFixture(responses: [response(200, "list"), response(200, "updated"), response(200, "")])
        let repository = DefaultSendRepository(
            runtime: try makeRuntime(),
            cryptography: TestSendCryptography(records: [existing], responseRecord: updated),
            http: http
        )
        _ = try await repository.load()
        var draft = SendDraft(contentKind: .text)
        draft.editingID = existing.id
        draft.name = "After"
        draft.text = "updated text"
        let afterUpdate = try await repository.save(draft, file: nil)
        let afterDelete = try await repository.delete(id: existing.id)
        let requests = await http.requests()

        #expect(afterUpdate.map(\.name) == ["After"])
        #expect(afterDelete.isEmpty)
        #expect(requests.map(\.method) == [.get, .put, .delete])
        #expect(requests[1].url.path.hasSuffix("/sends/send-1"))
        #expect(requests[2].url.path.hasSuffix("/sends/send-1"))
        #expect(requests[1].redirectPolicy == .reject)
        #expect(requests[2].redirectPolicy == .reject)
    }

    @Test
    func disablingExistingPasswordMakesASeparateFollowUpRequest() async throws {
        let existing = record("send-1", name: "Protected")
        let updated = record("send-1", name: "Protected")
        let http = SendHTTPFixture(
            responses: [response(200, "list"), response(200, "updated"), response(200, "removed")]
        )
        let repository = DefaultSendRepository(
            runtime: try makeRuntime(),
            cryptography: TestSendCryptography(records: [existing], responseRecord: updated),
            http: http
        )
        _ = try await repository.load()
        var draft = SendDraft(contentKind: .text)
        draft.editingID = existing.id
        draft.name = "Protected"
        draft.text = "text"
        draft.hasPasswordProtection = false
        draft.hadExistingPassword = true

        _ = try await repository.save(draft, file: nil)
        let requests = await http.requests()

        #expect(requests.count == 3)
        #expect(requests[1].method == .put)
        #expect(requests[1].url.path.hasSuffix("/sends/send-1"))
        #expect(requests[2].method == .put)
        #expect(requests[2].url.path.hasSuffix("/sends/send-1/remove-password"))
    }

    @Test
    func failedPasswordRemovalReportsThatTheMetadataUpdateAlreadyCommitted() async throws {
        let existing = record("send-1", name: "Protected")
        let updated = record("send-1", name: "Protected")
        let http = SendHTTPFixture(
            responses: [response(200, "list"), response(200, "updated"), response(500, "private failure")]
        )
        let repository = DefaultSendRepository(
            runtime: try makeRuntime(),
            cryptography: TestSendCryptography(records: [existing], responseRecord: updated),
            http: http
        )
        _ = try await repository.load()
        var draft = SendDraft(contentKind: .text)
        draft.editingID = existing.id
        draft.name = "Protected"
        draft.text = "text"
        draft.hadExistingPassword = true

        await #expect(throws: SendRepositoryError.committedButFollowUpFailed) {
            try await repository.save(draft, file: nil)
        }
        #expect(try await repository.details(for: existing.id).name == "Protected")
    }

    @Test
    func directFileCreationRegistersThenUploadsOnlyEncryptedBytes() async throws {
        let files = makeTemporaryFiles()
        defer { try? FileManager.default.removeItem(at: files.rootURL) }
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("send-\(UUID().uuidString).txt")
        try Data("plaintext file".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let ticket = SendFileUploadTicket(
            record: record("file-send", name: "Attachment", kind: .file),
            uploadURL: URL(string: "https://vault.example.com/unused")!,
            uploadKind: .direct,
            fileID: "file-id",
            encryptedFileName: "encrypted-name"
        )
        let crypto = TestSendCryptography(fileTicket: ticket)
        let http = SendHTTPFixture(responses: [response(200, "ticket"), response(200, "")])
        let repository = DefaultSendRepository(
            runtime: try makeRuntime(),
            cryptography: crypto,
            http: http,
            temporaryFiles: files
        )
        var draft = SendDraft(contentKind: .file)
        draft.name = "Attachment"
        draft.pickedFileName = fileURL.lastPathComponent

        let items = try await repository.save(draft, file: TestImportedSendFile(url: fileURL))
        let requests = await http.requests()

        #expect(items.map(\.id.rawValue) == ["file-send"])
        #expect(requests.count == 2)
        #expect(requests[0].url.path.hasSuffix("/sends/file/v2"))
        #expect(requests[0].body == Data("prepared-ciphertext".utf8))
        #expect(requests[1].url.path.hasSuffix("/sends/file-send/file/file-id"))
        let upload = try #require(await http.uploads().first)
        #expect(requests[1].body == nil)
        #expect(upload.capturedBody?.contains(Data("encrypted-file-bytes".utf8)) == true)
        #expect(upload.capturedBody?.contains(Data("plaintext file".utf8)) == false)
        #expect(requests[1].headers["Content-Length"] == String(upload.byteCount))
        #expect(upload.permissions == 0o600)
        #expect(!FileManager.default.fileExists(atPath: upload.fileURL.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: files.rootURL.path).isEmpty)
        #expect(requests[1].headers["Authorization"] == "Bearer send-test-token")
        #expect(requests[1].redirectPolicy == .reject)
    }

    @Test
    func azureUploadUsesItsSignedURLWithoutLeakingTheAccountBearer() async throws {
        let files = makeTemporaryFiles()
        defer { try? FileManager.default.removeItem(at: files.rootURL) }
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("send-\(UUID().uuidString).txt")
        try Data("plaintext file".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let uploadURL = URL(string: "https://blob.example.com/container/file?sv=2026-01-01&sig=private-signature")!
        let ticket = SendFileUploadTicket(
            record: record("file-send", name: "Attachment", kind: .file), uploadURL: uploadURL,
            uploadKind: .azure, fileID: "file-id", encryptedFileName: "encrypted-name"
        )
        let http = SendHTTPFixture(responses: [response(200, "ticket"), response(201, "")])
        let repository = DefaultSendRepository(
            runtime: try makeRuntime(), cryptography: TestSendCryptography(fileTicket: ticket), http: http,
            temporaryFiles: files
        )
        var draft = SendDraft(contentKind: .file)
        draft.name = "Attachment"
        draft.pickedFileName = fileURL.lastPathComponent

        _ = try await repository.save(draft, file: TestImportedSendFile(url: fileURL))
        let requests = await http.requests()
        let upload = try #require(requests.last)

        #expect(upload.url == uploadURL)
        #expect(upload.method == .put)
        #expect(upload.body == nil)
        let transferred = try #require(await http.uploads().first)
        #expect(transferred.capturedBody == Data("encrypted-file-bytes".utf8))
        #expect(upload.headers["Content-Length"] == String(transferred.byteCount))
        #expect(transferred.permissions == 0o600)
        #expect(!FileManager.default.fileExists(atPath: transferred.fileURL.path))
        #expect(upload.headers["Authorization"] == nil)
        #expect(upload.headers["x-ms-version"] == "2026-01-01")
        #expect(upload.redirectPolicy == .reject)
    }

    @Test
    func fileUploadFailureIsReportedAsCommittedAndDoesNotLeaveAnUnprojectedRecord() async throws {
        let files = makeTemporaryFiles()
        defer { try? FileManager.default.removeItem(at: files.rootURL) }
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("send-\(UUID().uuidString).txt")
        try Data("plaintext file".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let ticket = SendFileUploadTicket(
            record: record("file-send", name: "Attachment", kind: .file),
            uploadURL: URL(string: "https://vault.example.com/unused")!,
            uploadKind: .direct, fileID: "file-id", encryptedFileName: "encrypted-name"
        )
        let http = SendHTTPFixture(responses: [response(200, "ticket"), response(500, "private error")])
        let repository = DefaultSendRepository(
            runtime: try makeRuntime(), cryptography: TestSendCryptography(fileTicket: ticket), http: http,
            temporaryFiles: files
        )
        var draft = SendDraft(contentKind: .file)
        draft.name = "Attachment"
        draft.pickedFileName = fileURL.lastPathComponent

        await #expect(throws: SendRepositoryError.fileUploadFailed) {
            try await repository.save(draft, file: TestImportedSendFile(url: fileURL))
        }
        // The server accepted the metadata write before the file transfer failed; it is retained
        // in the repository snapshot so the UI can warn against a duplicate create.
        #expect(try await repository.details(for: SendID(rawValue: "file-send")).name == "Attachment")
        #expect(try FileManager.default.contentsOfDirectory(atPath: files.rootURL.path).isEmpty)
    }

    @Test
    func scopeEndsAfterEncryptionBeforeMetadataAndFileTransport() async throws {
        let fixture = try makeFileScenario()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let scope = SendFileScopeProbe()
        let http = SendHTTPFixture(responses: [response(200, "ticket"), response(200, "")], scope: scope)
        let repository = DefaultSendRepository(
            runtime: try makeRuntime(), cryptography: TestSendCryptography(fileTicket: fixture.ticket, scope: scope),
            http: http, temporaryFiles: fixture.files
        )
        _ = try await repository.save(
            SendDraft(contentKind: .file),
            file: TestImportedSendFile(url: fixture.fileURL, scope: scope)
        )
        #expect(!scope.isActive)
        #expect(scope.entryCount == 1)
        #expect(await http.scopeAtRequests() == [false, false])
        #expect(try Data(contentsOf: fixture.fileURL) == Data("plaintext file".utf8))
    }

    @Test
    func largeDirectUploadUsesFilePortWithoutFixtureReadingTheWholeBody() async throws {
        let fixture = try makeFileScenario()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let count = UInt64(16) * 1_024 * 1_024
        let http = SendHTTPFixture(responses: [response(200, "ticket"), response(200, "")], captureUploadBodies: false)
        let repository = DefaultSendRepository(
            runtime: try makeRuntime(),
            cryptography: TestSendCryptography(fileTicket: fixture.ticket, encryptedFileLength: count),
            http: http, temporaryFiles: fixture.files
        )
        _ = try await repository.save(SendDraft(contentKind: .file), file: TestImportedSendFile(url: fixture.fileURL))
        let upload = try #require(await http.uploads().first)
        #expect(upload.capturedBody == nil)
        #expect(upload.byteCount > count)
        #expect(upload.byteCount < count + 1_024)
        #expect(upload.request.body == nil)
        #expect(upload.request.headers["Content-Length"] == String(upload.byteCount))
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.files.rootURL.path).isEmpty)
    }

    @Test
    func filePreparationFailureCleansItsDirectoryBeforeAnyServerMutation() async throws {
        let fixture = try makeFileScenario()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let http = SendHTTPFixture()
        let repository = DefaultSendRepository(
            runtime: try makeRuntime(), cryptography: TestSendCryptography(preparationFailure: .cryptoFailure),
            http: http, temporaryFiles: fixture.files
        )
        await #expect(throws: SendRepositoryError.cryptoFailure) {
            try await repository.save(SendDraft(contentKind: .file), file: TestImportedSendFile(url: fixture.fileURL))
        }
        #expect(await http.requests().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.files.rootURL.path).isEmpty)
    }

    @Test
    func protectionFailureCleansItsDirectoryAndStopsBeforeServerWrite() async throws {
        let fixture = try makeFileScenario()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let http = SendHTTPFixture()
        let repository = DefaultSendRepository(
            runtime: try makeRuntime(), cryptography: TestSendCryptography(fileTicket: fixture.ticket), http: http,
            temporaryFiles: FailingSendWorkFiles(store: fixture.files, failsProtection: true)
        )
        await #expect(throws: SendRepositoryError.filePreparationFailed) {
            try await repository.save(SendDraft(contentKind: .file), file: TestImportedSendFile(url: fixture.fileURL))
        }
        #expect(await http.requests().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.files.rootURL.path).isEmpty)
    }

    @Test
    func precommitCleanupFailureRemainsDistinctAndDoesNotSendMetadata() async throws {
        let fixture = try makeFileScenario()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let http = SendHTTPFixture()
        let repository = DefaultSendRepository(
            runtime: try makeRuntime(), cryptography: TestSendCryptography(preparationFailure: .cryptoFailure),
            http: http,
            temporaryFiles: FailingSendWorkFiles(store: fixture.files, failsCleanup: true)
        )
        await #expect(throws: SendRepositoryError.temporaryCleanupFailed) {
            try await repository.save(SendDraft(contentKind: .file), file: TestImportedSendFile(url: fixture.fileURL))
        }
        #expect(await http.requests().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.files.rootURL.path).count == 1)
    }

    @Test
    func successfulUploadWithCleanupFailureIsNotReportedAsFailedUpload() async throws {
        let fixture = try makeFileScenario()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let http = SendHTTPFixture(responses: [response(200, "ticket"), response(200, "")])
        let repository = DefaultSendRepository(
            runtime: try makeRuntime(), cryptography: TestSendCryptography(fileTicket: fixture.ticket), http: http,
            temporaryFiles: FailingSendWorkFiles(store: fixture.files, failsCleanup: true)
        )
        await #expect(throws: SendRepositoryError.committedButCleanupFailed) {
            try await repository.save(SendDraft(contentKind: .file), file: TestImportedSendFile(url: fixture.fileURL))
        }
        #expect(await http.uploads().count == 1)
        #expect(try await repository.details(for: fixture.ticket.record.id).name == "Attachment")
    }

    @Test
    func failedUploadAndFailedCleanupPreserveBothPostcommitFacts() async throws {
        let fixture = try makeFileScenario()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let http = SendHTTPFixture(responses: [response(200, "ticket"), response(500, "")])
        let repository = DefaultSendRepository(
            runtime: try makeRuntime(), cryptography: TestSendCryptography(fileTicket: fixture.ticket), http: http,
            temporaryFiles: FailingSendWorkFiles(store: fixture.files, failsCleanup: true)
        )
        await #expect(throws: SendRepositoryError.fileUploadAndCleanupFailed) {
            try await repository.save(SendDraft(contentKind: .file), file: TestImportedSendFile(url: fixture.fileURL))
        }
        #expect(try await repository.details(for: fixture.ticket.record.id).name == "Attachment")
    }

    @Test
    func malformedAcknowledgedTicketClosesFileMutationInsteadOfBecomingRetryable() async throws {
        let fixture = try makeFileScenario()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let http = SendHTTPFixture(responses: [response(200, "malformed ticket")])
        let repository = DefaultSendRepository(
            runtime: try makeRuntime(), cryptography: TestSendCryptography(), http: http, temporaryFiles: fixture.files
        )
        await #expect(throws: SendRepositoryError.fileUploadFailed) {
            try await repository.save(SendDraft(contentKind: .file), file: TestImportedSendFile(url: fixture.fileURL))
        }
        #expect(await http.requests().count == 1)
        #expect(await http.uploads().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.files.rootURL.path).isEmpty)
    }

    @Test
    func ambiguousFileRegistrationIsNotReportedAsUnsubmitted() async throws {
        let fixture = try makeFileScenario()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let http = SendHTTPFixture(responses: [response(503, "unavailable")])
        let repository = DefaultSendRepository(
            runtime: try makeRuntime(),
            cryptography: TestSendCryptography(),
            http: http,
            temporaryFiles: fixture.files
        )
        await #expect(throws: SendRepositoryError.mutationOutcomeUnknown) {
            try await repository.save(SendDraft(contentKind: .file), file: TestImportedSendFile(url: fixture.fileURL))
        }
        #expect(await http.requests().count == 1)
        #expect(await http.uploads().isEmpty)
    }

    @Test
    func ambiguousFileRegistrationAndCleanupFailurePreserveBothFacts() async throws {
        let fixture = try makeFileScenario()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let http = SendHTTPFixture(failSend: true)
        let repository = DefaultSendRepository(
            runtime: try makeRuntime(), cryptography: TestSendCryptography(), http: http,
            temporaryFiles: FailingSendWorkFiles(store: fixture.files, failsCleanup: true)
        )
        await #expect(throws: SendRepositoryError.mutationOutcomeUnknownAndCleanupFailed) {
            try await repository.save(SendDraft(contentKind: .file), file: TestImportedSendFile(url: fixture.fileURL))
        }
        #expect(await http.requests().count == 1)
    }

    @Test
    func directUploadPreservesLongOpaqueServerFilename() async throws {
        let name = "2." + String(repeating: "ab/c", count: 100) + "|mac"
        let fixture = try makeFileScenario(fileName: name)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let http = SendHTTPFixture(responses: [response(200, "ticket"), response(200, "")])
        let repository = DefaultSendRepository(
            runtime: try makeRuntime(),
            cryptography: TestSendCryptography(fileTicket: fixture.ticket),
            http: http,
            temporaryFiles: fixture.files
        )
        _ = try await repository.save(SendDraft(contentKind: .file), file: TestImportedSendFile(url: fixture.fileURL))
        let body = try #require(await http.uploads().first?.capturedBody)
        #expect(String(decoding: body, as: UTF8.self).contains("filename=\"\(name)\""))
    }

    @Test
    func cancelledConsumerCannotStopAnAcknowledgedFileUploadOrItsCleanup() async throws {
        let fixture = try makeFileScenario()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let http = SendHTTPFixture(responses: [response(200, "ticket")], gateUpload: true)
        let repository = DefaultSendRepository(
            runtime: try makeRuntime(), cryptography: TestSendCryptography(fileTicket: fixture.ticket), http: http,
            temporaryFiles: fixture.files
        )
        let caller = Task { try await repository.save(
            SendDraft(contentKind: .file),
            file: TestImportedSendFile(url: fixture.fileURL)
        ) }
        await http.waitForGatedRequest()
        caller.cancel()
        await http.resumeGatedRequest(with: response(200, ""))
        let result = try await caller.value
        #expect(result.map(\.id) == [fixture.ticket.record.id])
        #expect(await http.requests().count == 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.files.rootURL.path).isEmpty)
    }

    @Test
    func runtimeRevocationRejectsLateUploadResultAndCleansFiles() async throws {
        let fixture = try makeFileScenario()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let runtime = try makeRuntime()
        let http = SendHTTPFixture(responses: [response(200, "ticket")], gateUpload: true)
        let repository = DefaultSendRepository(
            runtime: runtime, cryptography: TestSendCryptography(fileTicket: fixture.ticket), http: http,
            temporaryFiles: fixture.files
        )
        let caller = Task { try await repository.save(
            SendDraft(contentKind: .file),
            file: TestImportedSendFile(url: fixture.fileURL)
        ) }
        await http.waitForGatedRequest()
        await runtime.revoke(.lock)
        await http.resumeGatedRequest(with: response(200, ""))
        await #expect(throws: CancellationError.self) { try await caller.value }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.files.rootURL.path).isEmpty)
    }

    @Test
    func unsafeMultipartFilenameNeverReachesFileTransportAfterRegistration() async throws {
        let fixture = try makeFileScenario(fileName: "bad\"\r\nname")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let http = SendHTTPFixture(responses: [response(200, "ticket")])
        let repository = DefaultSendRepository(
            runtime: try makeRuntime(), cryptography: TestSendCryptography(fileTicket: fixture.ticket), http: http,
            temporaryFiles: fixture.files
        )
        await #expect(throws: SendRepositoryError.fileUploadFailed) {
            try await repository.save(SendDraft(contentKind: .file), file: TestImportedSendFile(url: fixture.fileURL))
        }
        #expect(await http.uploads().isEmpty)
        #expect(await http.requests().count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.files.rootURL.path).isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func listAndCreateRunFIFOInsteadOfOverwritingEachOthersSnapshot() async throws {
        let created = record("created", name: "Created")
        let http = SendHTTPFixture(gatedMethod: .get)
        let repository = DefaultSendRepository(
            runtime: try makeRuntime(), cryptography: TestSendCryptography(responseRecord: created), http: http
        )
        let load = Task { try await repository.load() }
        await http.waitForGatedRequest()
        let save = Task { try await repository.save(SendDraft(contentKind: .text), file: nil) }
        while await repository.queuedOperationCount == 0 {
            try Task.checkCancellation()
            await Task.yield()
        }
        #expect(await http.requests().count == 1)
        await http.resumeGatedRequest(with: response(200, "list"))
        #expect(try await load.value.isEmpty)
        #expect(try await save.value.map(\.id) == [created.id])
        #expect(try await repository.details(for: created.id).name == "Created")
        #expect(await http.requests().map(\.method) == [.get, .post])
    }

    @Test(.timeLimit(.minutes(1)))
    func queuedListCannotSendAfterRevocationDuringAnActiveCreate() async throws {
        let runtime = try makeRuntime()
        let http = SendHTTPFixture(gatedMethod: .post)
        let repository = DefaultSendRepository(
            runtime: runtime, cryptography: TestSendCryptography(responseRecord: record("created", name: "Created")),
            http: http
        )
        let save = Task { try await repository.save(SendDraft(contentKind: .text), file: nil) }
        await http.waitForGatedRequest()
        let load = Task { try await repository.load() }
        while await repository.queuedOperationCount == 0 {
            try Task.checkCancellation()
            await Task.yield()
        }
        await runtime.revoke(.lock)
        await http.resumeGatedRequest(with: response(200, "late create"))
        await #expect(throws: CancellationError.self) { try await save.value }
        await #expect(throws: CancellationError.self) { try await load.value }
        #expect(await http.requests().count == 1)
        #expect(await repository.queuedOperationCount == 0)
    }

    private func makeTemporaryFiles() -> SensitiveTemporaryFileStore {
        SensitiveTemporaryFileStore(
            rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(
                "send-work-\(UUID().uuidString)",
                isDirectory: true
            )
        )
    }

    private func makeFileScenario(fileName: String = "encrypted-name") throws -> SendFileScenario {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "send-scenario-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let fileURL = directory.appendingPathComponent("input.txt")
        try Data("plaintext file".utf8).write(to: fileURL)
        return SendFileScenario(
            directory: directory, fileURL: fileURL,
            files: SensitiveTemporaryFileStore(rootURL: directory.appendingPathComponent("work", isDirectory: true)),
            ticket: SendFileUploadTicket(
                record: record("file-send", name: "Attachment", kind: .file),
                uploadURL: URL(string: "https://vault.example.com/unused")!,
                uploadKind: .direct, fileID: "file-id", encryptedFileName: fileName
            )
        )
    }

    @Test
    func unsafeIdentifiersAreRejectedBeforeTheyReachTheTransport() async throws {
        let http = SendHTTPFixture()
        let repository = DefaultSendRepository(
            runtime: try makeRuntime(),
            cryptography: TestSendCryptography(),
            http: http
        )

        await #expect(throws: SendRepositoryError.itemUnavailable) {
            try await repository.delete(id: SendID(rawValue: "../other-account"))
        }
        #expect(await http.requests().isEmpty)
    }

    @Test
    func missingAccessTokenStopsBeforeNetworkTransport() async throws {
        let http = SendHTTPFixture()
        let repository = DefaultSendRepository(
            runtime: try makeRuntime(token: nil), cryptography: TestSendCryptography(), http: http
        )

        await #expect(throws: SessionAuthorizationError.temporarilyUnavailable) {
            try await repository.load()
        }
        #expect(await http.requests().isEmpty)
    }

    private func makeRuntime(token: String? = "send-test-token") throws -> SessionRuntime {
        let account = AccountSession(
            accountID: AccountID(rawValue: "test-account"),
            email: "test@example.com",
            environment: try ServerEnvironment(baseURL: URL(string: "https://vault.example.com/vault/")!)
        )
        return SessionRuntime(account: account, resource: SendRuntimeResource(), tokens: SendRuntimeTokens(token: token))
    }

    private func response(_ status: Int, _ body: String) -> HTTPResponse {
        HTTPResponse(statusCode: status, headers: [:], body: Data(body.utf8))
    }

    private func record(_ id: String, name: String, kind: SendContentKind = .text) -> SendRecord {
        let summary = SendSummary(
            id: SendID(rawValue: id), name: name, contentKind: kind, isDisabled: false,
            expirationDate: nil, deletionDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        return SendRecord(id: summary.id, encryptedPayload: Data("opaque".utf8), summary: summary)
    }
}

private struct TestSendCryptography: SendCryptography {
    var records: [SendRecord] = []
    var responseRecord: SendRecord?
    var fileTicket: SendFileUploadTicket?
    var preparationFailure: SendRepositoryError?
    var scope: SendFileScopeProbe?
    var encryptedFileLength: UInt64?

    func decodeList(_ response: Data) throws -> [SendRecord] { records }
    func decodeResponse(_ response: Data) throws -> SendRecord {
        guard let responseRecord else { throw SendRepositoryError.invalidResponse }
        return responseRecord
    }

    func decodeFileUploadTicket(_ response: Data) throws -> SendFileUploadTicket {
        guard let fileTicket else { throw SendRepositoryError.invalidResponse }
        return fileTicket
    }

    func details(for record: SendRecord) throws -> SendDetails {
        SendDetails(
            id: record.id, name: record.summary.name, contentKind: record.summary.contentKind,
            notes: nil, fileName: nil, textHidden: false, accessCount: 0, maxAccessCount: nil,
            hasPassword: false, hidesEmail: false, isDisabled: false, expirationDate: nil,
            deletionDate: record.summary.deletionDate
        )
    }

    func editDraft(for record: SendRecord) throws -> SendDraft { SendDraft(contentKind: .text) }
    func prepare(_ draft: SendDraft, existing: SendRecord?) throws -> PreparedSendMutation {
        PreparedSendMutation(requestBody: Data("prepared-ciphertext".utf8))
    }

    func prepareFile(_ draft: SendDraft, plaintextURL: URL, encryptedURL: URL) throws -> PreparedSendFileMutation {
        if let preparationFailure { throw preparationFailure }
        if let scope, !scope.isActive { throw SendRepositoryError.invalidDraft }
        let bytes = Data("encrypted-file-bytes".utf8)
        try bytes.write(to: encryptedURL)
        if let encryptedFileLength {
            let handle = try FileHandle(forWritingTo: encryptedURL)
            defer { try? handle.close() }
            try handle.truncate(atOffset: encryptedFileLength)
        }
        return PreparedSendFileMutation(
            requestBody: Data("prepared-ciphertext".utf8), encryptedFileURL: encryptedURL,
            byteCount: encryptedFileLength ?? UInt64(bytes.count)
        )
    }

    func shareLink(for record: SendRecord, webVaultURL: URL) throws -> URL { webVaultURL }
}

private actor SendHTTPFixture: HTTPClient {
    private var scriptedResponses: [HTTPResponse]
    private let gatedMethod: HTTPRequest.Method?
    private var savedRequests: [HTTPRequest] = []
    private var gatedResponse: CheckedContinuation<HTTPResponse, Never>?
    private var gatedRequestWaiters: [CheckedContinuation<Void, Never>] = []
    private let gateUpload: Bool
    private let captureUploadBodies: Bool
    private let scope: SendFileScopeProbe?
    private var hasGated = false
    private var savedUploads: [SendUploadedFile] = []
    private var requestScopes: [Bool] = []
    private let failSend: Bool

    init(
        responses: [HTTPResponse] = [],
        gatedMethod: HTTPRequest.Method? = nil,
        gateUpload: Bool = false,
        captureUploadBodies: Bool = true,
        scope: SendFileScopeProbe? = nil,
        failSend: Bool = false
    ) {
        scriptedResponses = responses
        self.gatedMethod = gatedMethod
        self.gateUpload = gateUpload
        self.captureUploadBodies = captureUploadBodies
        self.scope = scope
        self.failSend = failSend
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        if failSend { savedRequests.append(request); throw URLError(.networkConnectionLost) }
        return await respond(to: request, isUpload: false)
    }

    private func respond(to request: HTTPRequest, isUpload: Bool) async -> HTTPResponse {
        savedRequests.append(request)
        requestScopes.append(scope?.isActive ?? false)
        if !hasGated, (isUpload && gateUpload) || request.method == gatedMethod {
            hasGated = true
            return await withCheckedContinuation { continuation in
                gatedResponse = continuation
                let waiters = gatedRequestWaiters
                gatedRequestWaiters.removeAll()
                for waiter in waiters { waiter.resume() }
            }
        }
        guard !scriptedResponses.isEmpty else { return HTTPResponse(statusCode: 200, headers: [:], body: Data()) }
        return scriptedResponses.removeFirst()
    }

    func upload(_ request: HTTPRequest, fromFile fileURL: URL) async throws -> HTTPResponse {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
        savedUploads.append(SendUploadedFile(
            request: request, fileURL: fileURL,
            capturedBody: captureUploadBodies ? try Data(contentsOf: fileURL) : nil,
            byteCount: size, permissions: permissions
        ))
        return await respond(to: request, isUpload: true)
    }

    func download(_ request: HTTPRequest, to destinationURL: URL) async throws -> HTTPFileResponse {
        throw CancellationError()
    }

    func requests() -> [HTTPRequest] { savedRequests }
    func uploads() -> [SendUploadedFile] { savedUploads }
    func scopeAtRequests() -> [Bool] { requestScopes }
    func waitForGatedRequest() async {
        if gatedResponse != nil { return }
        await withCheckedContinuation { gatedRequestWaiters.append($0) }
    }

    func resumeGatedRequest(with response: HTTPResponse) {
        gatedResponse?.resume(returning: response)
        gatedResponse = nil
    }
}

private final class SendRuntimeResource: SessionResource, @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    var isActive: Bool { lock.withLock { active } }
    func revoke() { lock.withLock { active = false } }
}

private actor SendRuntimeTokens: SessionTokenProviding {
    private let token: String?
    init(token: String?) { self.token = token }
    func getAccessToken() async -> String? { token }
    func revoke() async {}
}

private struct TestImportedSendFile: ImportedFile {
    let url: URL
    var scope: SendFileScopeProbe?
    var fileName: String { url.lastPathComponent }
    func withSecurityScopedAccess<Value: Sendable>(
        _ operation: @Sendable (URL) async throws -> Value
    ) async throws -> Value {
        scope?.begin()
        defer { scope?.end() }
        return try await operation(url)
    }
}

private struct SendFileScenario {
    let directory: URL
    let fileURL: URL
    let files: SensitiveTemporaryFileStore
    let ticket: SendFileUploadTicket
}

private struct SendUploadedFile: Sendable {
    let request: HTTPRequest
    let fileURL: URL
    let capturedBody: Data?
    let byteCount: UInt64
    let permissions: UInt16
}

private struct FailingSendWorkFiles: SensitiveFileWorking {
    let store: SensitiveTemporaryFileStore
    var failsProtection = false
    var failsCleanup = false
    func makeWorkDirectory() async throws -> URL { try await store.makeWorkDirectory() }
    func makeSensitiveFile(in directory: URL, suggestedName: String) async throws -> URL {
        try await store.makeSensitiveFile(in: directory, suggestedName: suggestedName)
    }

    func protectFile(at url: URL) async throws {
        if failsProtection { throw SensitiveTemporaryFileStoreError.couldNotCreateFile }
        try await store.protectFile(at: url)
    }

    func removeWorkDirectory(_ directory: URL) async throws {
        if failsCleanup { throw SensitiveTemporaryFileStoreError.cleanupFailed }
        try await store.removeWorkDirectory(directory)
    }
}

/// Synchronous crypto and asynchronous import/HTTP share this fixture; every mutable field is
/// protected by the same lock, and no URL/content is stored in it.
private final class SendFileScopeProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var active = false
    private var entries = 0
    var isActive: Bool { lock.withLock { active } }
    var entryCount: Int { lock.withLock { entries } }
    func begin() { lock.withLock { active = true; entries += 1 } }
    func end() { lock.withLock { active = false } }
}
