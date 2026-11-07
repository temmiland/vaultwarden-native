import BitwardenSdk
import BitwardenSDKAdapter
import Domain
import Foundation
import Networking
import Testing

@Suite
struct SDKVaultSourceTests {
    private func response(_ id: String = "cipher-1", unsupportedPayload: Bool = false) -> Data {
        Data("""
        {"id":"\(id)","type":1,"name":"encrypted-name","favorite":false,"reprompt":0,
         "revisionDate":"1970-01-01T00:00:00.000Z","creationDate":"1970-01-01T00:00:00.000Z",
         "login":{"username":"encrypted-user","password":"encrypted-password"\(unsupportedPayload ? ",\"futureField\":\"encrypted-future\"" : "")}}
        """.utf8)
    }

    private func ok(_ body: Data) -> HTTPResponse { HTTPResponse(statusCode: 200, headers: [:], body: body) }
    private func make(
        crypto: SpyVaultCryptoService = SpyVaultCryptoService(),
        http: MockHTTPClient = MockHTTPClient(),
        token: @escaping @Sendable () async -> String? = { "token" },
        check: @escaping @Sendable () throws -> Void = { try Task.checkCancellation() }
    ) throws -> SDKVaultSessionSource {
        SDKVaultSessionSource(
            http: http,
            environment: try Domain.ServerEnvironment(baseURL: URL(string: "https://vault.example.com")!),
            crypto: crypto,
            accessToken: token,
            checkAccess: check
        )
    }

    private func seeded(crypto: SpyVaultCryptoService, http: MockHTTPClient, cipher: CipherView = .fixture()) async throws -> SDKVaultSessionSource {
        crypto.decryptCiphersResult = [cipher]
        http.responses = [ok(Data("{\"ciphers\":[\(String(decoding: response(), as: UTF8.self))]}".utf8))]
        let source = try make(crypto: crypto, http: http)
        _ = try await source.fetchOutput()
        return source
    }

    @Test
    func createEncryptsBeforeHTTPAndDecryptsTheAcknowledgedResponse() async throws {
        let crypto = SpyVaultCryptoService(); let http = MockHTTPClient()
        crypto.encryptCipherResult = EncryptionContext(
            encryptedFor: "user-1",
            cipher: .fixture(id: nil, name: "encrypted-name")
        )
        crypto.decryptCipherResult = .fixture(id: "created", name: "Readable")
        http.responses = [ok(response("created"))]
        let source = try make(crypto: crypto, http: http)
        var draft = VaultItemDraft(kind: .login)
        draft.name = "Plaintext draft name"
        let id = try await source.save(draft)
        #expect(id.rawValue == "created")
        #expect(crypto.events.count == 2)
        #expect(crypto.events[0].hasPrefix("encryptCipher"))
        #expect(crypto.events[1] == "decryptCipher(created)")
        let request = try #require(http.calls.first?.request)
        #expect(request.method == .post)
        #expect(request.url.path == "/api/ciphers")
        #expect(request.headers["Authorization"] == "Bearer token")
        let body = try #require(request.body)
        let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(payload["name"] as? String == "encrypted-name")
        #expect(payload["encryptedFor"] as? String == "user-1")
        #expect(body.range(of: Data(draft.name.utf8)) == nil)
        #expect(try await source.currentOutput().snapshot.items.map(\.name) == ["Readable"])
    }

    @Test
    func updateUsesTheExistingIDAndRetainsTheSourceRevision() async throws {
        let crypto = SpyVaultCryptoService(); let http = MockHTTPClient()
        let source = try await seeded(crypto: crypto, http: http)
        var draft = try await source.makeDraft(for: CipherID(rawValue: "cipher-1"))
        draft.name = "Renamed"
        crypto.decryptCipherResult = .fixture(name: "Renamed")
        http.responses = [ok(response())]
        _ = try await source.save(draft)
        #expect(http.calls.last?.request.method == .put)
        #expect(http.calls.last?.request.url.path == "/api/ciphers/cipher-1")
        #expect(try await source.currentOutput().snapshot.revision == 2)
    }

    @Test
    func acknowledgedWriteRejectsResponseEncryptedForAnotherAccount() async throws {
        let crypto = SpyVaultCryptoService(); let http = MockHTTPClient()
        crypto.encryptCipherResult = EncryptionContext(encryptedFor: "user-1", cipher: .fixture(id: nil))
        http.responses = [ok(Data("""
        {"id":"created","type":1,"name":"encrypted-name","encryptedFor":"other-user",
         "login":{"username":"encrypted-user","password":"encrypted-password"}}
        """.utf8))]
        let source = try make(crypto: crypto, http: http)
        await #expect(throws: VaultRepositoryError.committedButRefreshFailed) {
            _ = try await source.save(.init(kind: .login))
        }
        #expect(try await source.currentOutput().snapshot.isStale)
    }

    @Test
    func missingAndStaleEditBasesNeverBecomeCreates() async throws {
        let crypto = SpyVaultCryptoService(); let http = MockHTTPClient()
        let source = try await seeded(crypto: crypto, http: http)
        let missing = VaultItemDraft(editingID: CipherID(rawValue: "absent"), kind: .login, baseRevision: .distantPast)
        await #expect(throws: VaultItemDraftError.missingItem) { _ = try await source.save(missing) }
        let stale = VaultItemDraft(editingID: CipherID(rawValue: "cipher-1"), kind: .login, baseRevision: .distantPast)
        await #expect(throws: VaultItemDraftError.staleDraft) { _ = try await source.save(stale) }
        #expect(http.calls.count == 1)
    }

    @Test
    func failedOrCancelledEncryptionNeverStartsHTTP() async throws {
        let crypto = SpyVaultCryptoService(); let http = MockHTTPClient()
        let source = try make(crypto: crypto, http: http)
        crypto.errorToThrow = SourceFixtureError.encryption
        await #expect(throws: SourceFixtureError.encryption) { _ = try await source.save(.init(kind: .login)) }
        crypto.errorToThrow = CancellationError()
        await #expect(throws: CancellationError.self) { _ = try await source.save(.init(kind: .login)) }
        #expect(http.calls.isEmpty)
    }

    @Test
    func revocationDuringEncryptionPreventsTheServerWrite() async throws {
        let crypto = SpyVaultCryptoService(); let http = MockHTTPClient()
        let source = try make(crypto: crypto, http: http)
        crypto.beforeEncryptReturns = { await source.revoke() }
        await #expect(throws: CancellationError.self) { _ = try await source.save(.init(kind: .login)) }
        #expect(http.calls.isEmpty)
    }

    @Test(arguments: ["revision", "reprompt", "permission", "unsupportedPayload"])
    func refreshDuringEncryptionRechecksTheDraftBeforeHTTP(_ change: String) async throws {
        let crypto = SpyVaultCryptoService(); let http = MockHTTPClient()
        let source = try await seeded(crypto: crypto, http: http)
        let draft = try await source.makeDraft(for: CipherID(rawValue: "cipher-1"))
        switch change {
        case "revision": crypto.decryptCiphersResult = [.fixture(revisionDate: Date(timeIntervalSince1970: 1))]
        case "reprompt": crypto.decryptCiphersResult = [.fixture(reprompt: .password)]
        case "permission": crypto.decryptCiphersResult = [.fixture(edit: false)]
        default: crypto.decryptCiphersResult = [.fixture()] // even if SDK drops the edit fence
        }
        http.responses = [
            ok(
                Data(
                    "{\"ciphers\":[\(String(decoding: response(unsupportedPayload: change == "unsupportedPayload"), as: UTF8.self))]}".utf8
                )
            ),
        ]
        crypto.beforeEncryptReturns = {
            do { _ = try await source.fetchOutput() }
            catch { Issue.record("Fixture refresh failed: \(error)") }
        }
        if change == "revision" {
            await #expect(throws: VaultItemDraftError.staleDraft) { _ = try await source.save(draft) }
        } else {
            await #expect(throws: VaultItemDraftError.readOnly) { _ = try await source.save(draft) }
        }
        #expect(http.calls.count == 2)
        #expect(http.calls.allSatisfy { $0.request.method == .get })
    }

    @Test
    func unsupportedPayloadRemainsReadableButBlocksEveryExistingAppMutation() async throws {
        let crypto = SpyVaultCryptoService(); let http = MockHTTPClient()
        // Deliberately return edit=true to prove Data does not trust preservation by SDK crypto.
        crypto.decryptCiphersResult = [.fixture()]
        http.responses = [
            ok(Data("{\"ciphers\":[\(String(decoding: response(unsupportedPayload: true), as: UTF8.self))]}".utf8)),
        ]
        let source = try make(crypto: crypto, http: http)
        let output = try await source.fetchOutput()
        let detail = try #require(output.snapshot.details[CipherID(rawValue: "cipher-1")])
        #expect(output.snapshot.items.count == 1 && output.snapshot.warnings.isEmpty)
        #expect(detail.permissions.canViewSecrets)
        #expect(detail.permissions.editRestriction == .unsupportedPayload)
        #expect(!detail.permissions.canEdit && !detail.permissions.canDelete)
        #expect(output.snapshot.items.first?.isEditable == false)
        #expect(output.snapshot.items.first?.canDelete == false)
        await #expect(throws: VaultItemDraftError.readOnly) { _ = try await source.makeDraft(for: detail.id) }
        let draft = VaultItemDraft(editingID: detail.id, kind: .login, baseRevision: detail.context.revision)
        await #expect(throws: VaultItemDraftError.readOnly) { _ = try await source.save(draft) }
        await #expect(throws: VaultRepositoryError.readOnly) { try await source.delete(detail.context) }
        await #expect(throws: VaultRepositoryError.readOnly) {
            try await source.uploadAttachment(
                to: detail.context, file: MockImportedFile(url: URL(fileURLWithPath: "/unused-input")),
                encryptedURL: URL(fileURLWithPath: "/unused-output")
            )
        }
        let reference = VaultAttachmentReference(
            cipherID: detail.id,
            attachmentID: AttachmentID(rawValue: "attachment-1")
        )
        await #expect(throws: VaultRepositoryError.readOnly) { try await source.deleteAttachment(
            reference,
            context: detail.context
        ) }
        #expect(http.calls.count == 1 && http.calls.allSatisfy { $0.request.method == .get })
        #expect(!crypto.events.contains { $0.hasPrefix("encryptCipher") })
        let cached = try JSONDecoder().decode(
            CipherResponseDTO.self,
            from: #require(output.encryptedLoginRecords.first?.encryptedCipherPayload)
        )
        #expect(cached.hasUnrecognizedPayload && cached.edit == false)
    }

    @Test
    func subsequentKnownOnlySyncReplacesTheReadOnlyFenceInsteadOfPermanentlyPoisoningTheItem() async throws {
        let crypto = SpyVaultCryptoService(); let http = MockHTTPClient()
        crypto.decryptCiphersResult = [.fixture()]
        let source = try make(crypto: crypto, http: http)
        for unsupported in [true, false] {
            http.responses = [
                ok(
                    Data(
                        "{\"ciphers\":[\(String(decoding: response(unsupportedPayload: unsupported), as: UTF8.self))]}".utf8
                    )
                ),
            ]
            let output = try await source.fetchOutput()
            #expect(output.snapshot.items.first?.isEditable == !unsupported)
        }
        _ = try await source.makeDraft(for: CipherID(rawValue: "cipher-1"))
    }

    @Test
    func acknowledgedMalformedResponseRequiresSyncAndCannotBeBlindlyRetried() async throws {
        let crypto = SpyVaultCryptoService(); let http = MockHTTPClient()
        http.responses = [ok(Data("malformed".utf8))]
        let source = try make(crypto: crypto, http: http)
        await #expect(throws: VaultRepositoryError.committedButRefreshFailed) { _ = try await source.save(
            .init(kind: .login)
        ) }
        await #expect(throws: VaultRepositoryError.staleItem) { _ = try await source.save(.init(kind: .login)) }
        #expect(http.calls.count == 1)
    }

    @Test
    func acknowledgedDecryptFailureIsNotAnOrdinaryRetryableCreate() async throws {
        let crypto = SpyVaultCryptoService(); let http = MockHTTPClient()
        crypto.decryptCipherError = SourceFixtureError.encryption
        http.responses = [ok(response())]
        let source = try make(crypto: crypto, http: http)
        await #expect(throws: VaultRepositoryError.committedButRefreshFailed) { _ = try await source.save(
            .init(kind: .login)
        ) }
        #expect(try await source.currentOutput().snapshot.isStale)
    }

    @Test
    func missingTokenDoesNotBecomeAnUnauthenticatedRequest() async throws {
        let http = MockHTTPClient(); let source = try make(http: http, token: { nil })
        await #expect(throws: VaultRepositoryError.sessionClosed) { _ = try await source.fetchOutput() }
        #expect(http.calls.isEmpty)
    }

    @Test
    func duplicateIDsAreNotExportedAsFulfillableRecords() async throws {
        let http = MockHTTPClient(); let crypto = SpyVaultCryptoService()
        let cipher = String(decoding: response(), as: UTF8.self)
        http.responses = [ok(Data("{\"ciphers\":[\(cipher),\(cipher)]}".utf8))]
        let output = try await make(crypto: crypto, http: http).fetchOutput()
        #expect(output.snapshot.items.isEmpty)
        #expect(output.snapshot.warnings == [.unavailableItems(count: 2)])
        #expect(output.encryptedLoginRecords.isEmpty)
    }

    @Test(arguments: ["reprompt", "hidden", "unresolved", "ambiguous"])
    func restrictedSecretsNeverEnterCacheOrIdentities(_ restriction: String) async throws {
        let http = MockHTTPClient(); let crypto = SpyVaultCryptoService()
        let source = try await seeded(crypto: crypto, http: http)
        if restriction == "reprompt" {
            crypto.decryptCiphersResult = [.fixture(reprompt: .password)]
        } else {
            crypto.decryptCiphersResult = [.fixture(organizationId: "org-1", collectionIds: ["collection-1"])]
            switch restriction {
            case "hidden": crypto.decryptCollectionsResult = [.fixture(hidePasswords: true)]
            case "ambiguous": crypto.decryptCollectionsResult = [.fixture(), .fixture(hidePasswords: true)]
            default: crypto.decryptCollectionsResult = []
            }
        }
        http.responses = [ok(Data("{\"ciphers\":[\(String(decoding: response(), as: UTF8.self))]}".utf8))]
        let output = try await source.fetchOutput()
        #expect(output.encryptedLoginRecords.isEmpty)
        #expect(output.identitySources.isEmpty)
        #expect(output.snapshot.items.count == 1)
        #expect(output.snapshot.details[CipherID(rawValue: "cipher-1")]?.permissions.canViewSecrets == false)
    }

    @Test
    func deletingRemovesCipherFromSnapshotAndEncryptedProjection() async throws {
        let crypto = SpyVaultCryptoService(); let http = MockHTTPClient()
        let source = try await seeded(crypto: crypto, http: http)
        http.responses = [HTTPResponse(statusCode: 204, headers: [:], body: Data())]
        try await source.delete(
            VaultItemContext(id: CipherID(rawValue: "cipher-1"), revision: Date(timeIntervalSince1970: 0))
        )
        let output = try await source.currentOutput()
        #expect(output.snapshot.items.isEmpty)
        #expect(output.encryptedLoginRecords.isEmpty)
        #expect(http.calls.last?.request.method == .delete)
    }

    @Test
    func attachmentMetadataSuccessWithMalformedReplyRequiresSync() async throws {
        let crypto = SpyVaultCryptoService(); let http = MockHTTPClient()
        let source = try await seeded(crypto: crypto, http: http)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "sdk-source-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let encrypted = directory.appendingPathComponent("encrypted.data")
        http.responses = [ok(Data("malformed".utf8))]
        let context = VaultItemContext(id: CipherID(rawValue: "cipher-1"), revision: Date(timeIntervalSince1970: 0))
        await #expect(throws: VaultRepositoryError.committedButRefreshFailed) {
            try await source.uploadAttachment(
                to: context,
                file: MockImportedFile(url: directory.appendingPathComponent("original.bin")),
                encryptedURL: encrypted
            )
        }
        #expect(http.calls.count == 2)
        #expect(try await source.currentOutput().snapshot.isStale)
    }

    @Test
    func attachmentUploadUsesOnlyEncryptedBytesAndRefreshesAfterBothWrites() async throws {
        let crypto = SpyVaultCryptoService(); let http = MockHTTPClient()
        let source = try await seeded(crypto: crypto, http: http)
        let directory = try workDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.bin")
        try Data("original-plaintext".utf8).write(to: original)
        crypto.encryptAttachmentResult = Attachment(
            id: nil,
            url: nil,
            size: nil,
            sizeName: nil,
            fileName: "encrypted-name",
            key: "encrypted-key"
        )
        http.responses = [ok(
            Data(
                #"{"attachmentId":"attachment-1","url":"/ciphers/cipher-1/attachment/attachment-1","fileUploadType":0}"#.utf8
            )
        ),
        ok(Data()), ok(response())]
        try await source.uploadAttachment(
            to: context(),
            file: MockImportedFile(url: original),
            encryptedURL: directory.appendingPathComponent("encrypted.data")
        )
        #expect(http.calls.map(\.request.method) == [.get, .post, .post, .get])
        let metadataRequest = http.calls[1].request
        #expect(metadataRequest.url.path == "/api/ciphers/cipher-1/attachment/v2")
        let metadata = try JSONDecoder().decode(AttachmentRequestDTO.self, from: #require(metadataRequest.body))
        #expect(metadata.key == "encrypted-key")
        #expect(metadata.fileName == "encrypted-name")
        #expect(metadata.fileSize == UInt64(crypto.encryptedAttachmentContents.count))
        #expect(http.calls.allSatisfy { $0.request.redirectPolicy == .reject })
        #expect(http.calls.allSatisfy { $0.request.headers["Authorization"] == "Bearer token" })
        #expect(http.calls[2].request.headers["Content-Type"]?.hasPrefix("multipart/form-data; boundary=") == true)
        #expect(
            http.calls[2].request.url.absoluteString == "https://vault.example.com/api/ciphers/cipher-1/attachment/attachment-1"
        )
        #expect(http.calls[2].transfer == .upload)
        #expect(http.calls[2].fileURL != nil)
        #expect(http.calls[2].submittedBodyWasNil)
        let upload = try #require(http.calls[2].request.body)
        #expect(http.calls[2].request.headers["Content-Length"] == String(upload.count))
        #expect(String(decoding: upload, as: UTF8.self).contains("name=\"data\"; filename=\"encrypted-name\""))
        #expect(upload.range(of: crypto.encryptedAttachmentContents) != nil)
        #expect(upload.range(of: Data("original-plaintext".utf8)) == nil)
        #expect(try Data(contentsOf: original) == Data("original-plaintext".utf8))
        #expect(
            crypto.events.suffix(3) == [
                "encryptCipher(Example)",
                "encryptAttachmentFile(original.bin)",
                "decryptCipher(cipher-1)",
            ]
        )
        #expect(try await source.currentOutput().snapshot.revision == 2)
    }

    @Test(arguments: ["https://foreign.example.com/blob", "//foreign.example.com/blob", "http://vault.example.com/blob",
                      "https://user:password@vault.example.com/blob", "https://vault.example.com:444/blob"])
    func attachmentUploadRejectsForeignOriginsWithoutSendingBearerTokens(_ url: String) async throws {
        let crypto = SpyVaultCryptoService(); let http = MockHTTPClient()
        let source = try await seeded(crypto: crypto, http: http)
        let directory = try workDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let metadata = AttachmentUploadDataResponseDTO(attachmentId: "attachment-1", url: url, fileUploadType: 0)
        http.responses = [ok(try JSONEncoder().encode(metadata))]
        await #expect(throws: VaultRepositoryError.committedButRefreshFailed) {
            try await source.uploadAttachment(
                to: context(),
                file: MockImportedFile(url: directory.appendingPathComponent("original.bin")),
                encryptedURL: directory.appendingPathComponent("encrypted.data")
            )
        }
        #expect(http.calls.count == 2)
        #expect(try await source.currentOutput().snapshot.isStale)
    }

    @Test
    func unsupportedAttachmentUploadModeDoesNotUploadBytes() async throws {
        let crypto = SpyVaultCryptoService(); let http = MockHTTPClient()
        let source = try await seeded(crypto: crypto, http: http)
        let directory = try workDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        http.responses = [
            ok(Data(#"{"attachmentId":"attachment-1","url":"https://vault.example.com/blob","fileUploadType":1}"#.utf8)),
        ]
        await #expect(throws: VaultRepositoryError.committedButRefreshFailed) {
            try await source.uploadAttachment(
                to: context(),
                file: MockImportedFile(url: directory.appendingPathComponent("original.bin")),
                encryptedURL: directory.appendingPathComponent("encrypted.data")
            )
        }
        #expect(http.calls.count == 2)
    }

    @Test
    func attachmentDownloadRefreshesMetadataThenDecryptsWithTheOriginalCipher() async throws {
        let crypto = SpyVaultCryptoService(); let http = MockHTTPClient()
        let source = try await seeded(crypto: crypto, http: http, cipher: .fixture(attachments: [attachment()]))
        let directory = try workDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        http.responses = [
            ok(Data(#"{"id":"attachment-1","url":"https://vault.example.com/blob"}"#.utf8)),
            ok(Data("encrypted-bytes".utf8)),
        ]
        let encrypted = directory.appendingPathComponent("encrypted.data"), decrypted = directory.appendingPathComponent(
            "decrypted.data"
        )
        try await source.downloadAttachment(
            attachmentReference(),
            context: context(),
            encryptedURL: encrypted,
            decryptedURL: decrypted
        )
        #expect(http.calls.map(\.request.method) == [.get, .get, .get])
        #expect(http.calls[1].request.url.path == "/api/ciphers/cipher-1/attachment/attachment-1")
        #expect(http.calls[2].request.url.absoluteString == "https://vault.example.com/blob")
        #expect(http.calls.allSatisfy { $0.request.redirectPolicy == .reject })
        #expect(http.calls.allSatisfy { $0.request.headers["Authorization"] == "Bearer token" })
        #expect(try Data(contentsOf: decrypted) == crypto.decryptedAttachmentContents)
        #expect(crypto.events.suffix(2) == ["encryptCipher(Example)", "decryptAttachmentFile(attachment-1)"])
    }

    @Test
    func attachmentDownloadCannotBypassCipherRevisionOrSecretPermission() async throws {
        let crypto = SpyVaultCryptoService(); let http = MockHTTPClient()
        let source = try await seeded(
            crypto: crypto,
            http: http,
            cipher: .fixture(viewPassword: false, attachments: [attachment()])
        )
        let directory = try workDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        await #expect(throws: VaultRepositoryError.readOnly) {
            try await source.downloadAttachment(
                attachmentReference(),
                context: context(),
                encryptedURL: directory.appendingPathComponent("enc"),
                decryptedURL: directory.appendingPathComponent("dec")
            )
        }
        await #expect(throws: VaultRepositoryError.staleItem) {
            try await source.downloadAttachment(
                attachmentReference(),
                context: .init(id: context().id, revision: .distantPast),
                encryptedURL: directory.appendingPathComponent("enc"),
                decryptedURL: directory.appendingPathComponent("dec")
            )
        }
        #expect(http.calls.count == 1)
    }

    @Test
    func attachmentDeletionAcknowledgementWithFailedRefreshCannotBeRepeatedBlindly() async throws {
        let crypto = SpyVaultCryptoService(); let http = MockHTTPClient()
        let source = try await seeded(crypto: crypto, http: http, cipher: .fixture(attachments: [attachment()]))
        http.responses = [HTTPResponse(statusCode: 204, headers: [:], body: Data()), ok(Data("malformed".utf8))]
        await #expect(throws: VaultRepositoryError.committedButRefreshFailed) { try await source.deleteAttachment(
            attachmentReference(),
            context: context()
        ) }
        await #expect(throws: VaultRepositoryError.staleItem) { try await source.deleteAttachment(
            attachmentReference(),
            context: context()
        ) }
        #expect(http.calls.count == 3)
        #expect(http.calls[1].request.method == .delete)
        #expect(http.calls[1].request.url.path == "/api/ciphers/cipher-1/attachment/attachment-1")
    }

    private func workDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "sdk-vault-source-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func context() -> VaultItemContext { .init(
        id: CipherID(rawValue: "cipher-1"),
        revision: Date(timeIntervalSince1970: 0)
    ) }
    private func attachment() -> AttachmentView { .init(
        id: "attachment-1",
        url: nil,
        size: nil,
        sizeName: nil,
        fileName: "preview.bin",
        key: "wrapped-key"
    ) }
}

private enum SourceFixtureError: Error, Equatable { case encryption }
