import BitwardenSdk
import BitwardenSDKAdapter
import Domain
import Foundation
import Networking
import Testing

private final class SendNoTokenProvider: ClientManagedTokens {
    func getAccessToken() async -> String? { nil }
}

@Suite
struct SDKSendCryptographyTests {
    @Test
    func realSDKEncryptsLongFilenameWhichSurvivesMultipartAssembly() async throws {
        let email = "synthetic@example.invalid"
        let password = "synthetic-test-only-password"
        let kdf = Kdf.pbkdf2(iterations: 600_000)
        let client = Client(tokenProvider: SendNoTokenProvider(), settings: ClientSettings(
            identityUrl: "https://example.invalid/identity", apiUrl: "https://example.invalid/api",
            userAgent: "synthetic-test", deviceType: .macOsDesktop,
            deviceIdentifier: "synthetic-test", bitwardenClientVersion: "0.0.1", bitwardenPackageType: nil
        ))
        let keys = try client.auth().makeRegisterKeys(email: email, password: password, kdf: kdf)
        try await client.crypto().initializeUserCrypto(req: InitUserCryptoRequest(
            userId: "00000000-0000-4000-8000-000000000001", kdfParams: kdf, email: email,
            accountCryptographicState: .v1(privateKey: keys.keys.private),
            method: .masterPasswordUnlock(password: password, masterPasswordUnlock: MasterPasswordUnlockData(
                kdf: kdf, masterKeyWrappedUserKey: keys.encryptedUserKey, salt: email
            )), upgradeToken: nil
        ))
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let plaintext = directory.appendingPathComponent("input")
        let ciphertext = directory.appendingPathComponent("encrypted")
        try Data("synthetic file".utf8).write(to: plaintext)
        try Data().write(to: ciphertext)
        var draft = SendDraft(contentKind: .file)
        draft.name = "synthetic file"
        draft.pickedFileName = String(repeating: "a", count: 200) + ".txt"
        let prepared = try SDKSendCryptography(crypto: SDKSendCryptoService(client: client)).prepareFile(
            draft, plaintextURL: plaintext, encryptedURL: ciphertext
        )
        let object = try #require(JSONSerialization.jsonObject(with: prepared.requestBody) as? [String: Any])
        let file = try #require(object["file"] as? [String: Any])
        let encryptedName = try #require(file["fileName"] as? String)
        #expect(encryptedName.utf8.count > 255)
        let bodyURL = directory.appendingPathComponent("multipart")
        _ = try MultipartFileBody.prepare(
            inputURL: ciphertext,
            outputURL: bodyURL,
            fileName: encryptedName,
            boundary: "test-boundary",
            preserveSlashesInFileName: true
        )
        let body = try Data(contentsOf: bodyURL)
        #expect(body.range(of: Data("filename=\"\(encryptedName)\"".utf8)) != nil)
        #expect(body.range(of: Data("synthetic file".utf8)) == nil)
    }

    @Test
    func listDecodingKeepsAnUndecryptableItemVisibleWithoutBlockingReadableItems() throws {
        let response = Data("""
        {"data":[
          {"id":"good","type":0,"name":"cipher-name","key":"cipher-key","revisionDate":"2026-09-01T00:00:00Z","deletionDate":"2026-10-01T00:00:00Z","text":{"text":"cipher-text","hidden":false}},
          {"id":"bad","type":0,"name":"cipher-name","key":"cipher-key","revisionDate":"2026-09-01T00:00:00Z","deletionDate":"2026-10-01T00:00:00Z","text":{"text":"broken-cipher","hidden":false}}
        ]}
        """.utf8)
        let crypto = TestSendCrypto(
            views: ["good": view(id: "good", name: "Readable Send")],
            undecryptableIDs: ["bad"]
        )

        let records = try SDKSendCryptography(crypto: crypto).decodeList(response)

        #expect(records.count == 2)
        #expect(records.first(where: { $0.id.rawValue == "good" })?.summary.name == "Readable Send")
        #expect(records.first(where: { $0.id.rawValue == "bad" })?.summary.canOpen == false)
        #expect(records.first(where: { $0.id.rawValue == "bad" })?.summary.name == "Unable to decrypt Send")
        #expect(!String(reflecting: records).contains("cipher-key"))
    }

    @Test
    func prepareSerializesOnlySdkEncryptedTextAndPassword() throws {
        let encrypted = send(id: "new-send", name: "cipher-name", key: "cipher-key", password: "password-hash")
        let crypto = TestSendCrypto(encryptedSend: encrypted)
        var draft = SendDraft(contentKind: .text)
        draft.name = "private name marker"
        draft.notes = "private notes marker"
        draft.text = "private text marker"
        draft.password = "private password marker"
        draft.hasPasswordProtection = true
        draft.deletionDate = Date(timeIntervalSince1970: 1_800_000_000)

        let prepared = try SDKSendCryptography(crypto: crypto).prepare(draft, existing: nil)
        let object = try #require(JSONSerialization.jsonObject(with: prepared.requestBody) as? [String: Any])
        let text = try #require(object["text"] as? [String: Any])
        let bodyText = String(decoding: prepared.requestBody, as: UTF8.self)

        #expect(object["name"] as? String == "cipher-name")
        #expect(object["key"] as? String == "cipher-key")
        #expect(object["password"] as? String == "password-hash")
        #expect(text["text"] as? String == "encrypted-text")
        #expect(object["authType"] as? Int == 1)
        #expect(!bodyText.contains("private name marker"))
        #expect(!bodyText.contains("private notes marker"))
        #expect(!bodyText.contains("private text marker"))
        #expect(!bodyText.contains("private password marker"))
        #expect(object["fileLength"] == nil)
    }

    @Test
    func filePreparationEncryptsBytesBeforeIncludingCiphertextLengthInRequest() throws {
        let encrypted = send(id: nil, name: "cipher-file-name", key: "cipher-key", type: .file)
        let encryptedBytes = Data("opaque encrypted file bytes".utf8)
        let crypto = TestSendCrypto(encryptedSend: encrypted, encryptedBytes: encryptedBytes)
        var draft = SendDraft(contentKind: .file)
        draft.name = "Private File Name"
        draft.pickedFileName = "plaintext.txt"
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let plaintext = directory.appendingPathComponent("plaintext.txt")
        let ciphertext = directory.appendingPathComponent("encrypted.data")
        try Data("plaintext file marker".utf8).write(to: plaintext)
        try Data().write(to: ciphertext)

        let prepared = try SDKSendCryptography(crypto: crypto).prepareFile(
            draft, plaintextURL: plaintext, encryptedURL: ciphertext
        )
        let object = try #require(JSONSerialization.jsonObject(with: prepared.requestBody) as? [String: Any])
        let file = try #require(object["file"] as? [String: Any])
        let bodyText = String(decoding: prepared.requestBody, as: UTF8.self)

        #expect(object["fileLength"] as? Int == encryptedBytes.count)
        #expect(file["fileName"] as? String == "encrypted-file-name")
        #expect(prepared.encryptedFileURL == ciphertext)
        #expect(prepared.byteCount == UInt64(encryptedBytes.count))
        #expect(try Data(contentsOf: ciphertext) == encryptedBytes)
        #expect(try Data(contentsOf: plaintext) == Data("plaintext file marker".utf8))
        #expect(!String(reflecting: prepared).contains("plaintext.txt"))
        #expect(!bodyText.contains("plaintext file marker"))
        #expect(!bodyText.contains("plaintext.txt"))
        #expect(!bodyText.contains("Private File Name"))
    }

    @Test
    func sparseFileCiphertextLengthUses64BitMetadataWithoutReadingItsContents() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let plaintext = directory.appendingPathComponent("input")
        let ciphertext = directory.appendingPathComponent("output")
        try Data("small input".utf8).write(to: plaintext)
        try Data().write(to: ciphertext)
        let count = UInt64(6) * 1_024 * 1_024 * 1_024
        let crypto = TestSendCrypto(
            encryptedSend: send(id: nil, name: "cipher", key: "key", type: .file),
            encryptedFileLength: count
        )
        let prepared = try SDKSendCryptography(crypto: crypto).prepareFile(
            SendDraft(contentKind: .file), plaintextURL: plaintext, encryptedURL: ciphertext
        )
        let body = try #require(JSONSerialization.jsonObject(with: prepared.requestBody) as? [String: Any])
        #expect((body["fileLength"] as? NSNumber)?.uint64Value == count)
        #expect(prepared.byteCount == count)
    }

    @Test
    func filePreparationRejectsSymlinkDirectoryAndAliasedPathsBeforeCrypto() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let plaintext = directory.appendingPathComponent("input")
        let ciphertext = directory.appendingPathComponent("output")
        let link = directory.appendingPathComponent("link")
        try Data("unchanged input".utf8).write(to: plaintext)
        try Data("unchanged output".utf8).write(to: ciphertext)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: plaintext)
        let crypto = SDKSendCryptography(crypto: TestSendCrypto())
        for input in [link, directory, ciphertext] {
            #expect(throws: SendRepositoryError.invalidDraft) {
                try crypto.prepareFile(SendDraft(contentKind: .file), plaintextURL: input, encryptedURL: ciphertext)
            }
        }
        #expect(throws: SendRepositoryError.invalidDraft) {
            try crypto.prepareFile(SendDraft(contentKind: .file), plaintextURL: plaintext, encryptedURL: link)
        }
        #expect(try Data(contentsOf: plaintext) == Data("unchanged input".utf8))
        #expect(try Data(contentsOf: ciphertext) == Data("unchanged output".utf8))
    }

    @Test
    func invalidDraftAccessCountsAreRejectedWithoutClampingOrIntegerTraps() {
        let crypto = SDKSendCryptography(crypto: TestSendCrypto())
        for count in [Int.min, -1, 0, Int(UInt32.max) + 1, Int.max] {
            var draft = SendDraft(contentKind: .text)
            draft.hasMaxAccessCount = true
            draft.maxAccessCount = count
            #expect(throws: SendRepositoryError.invalidDraft) { try crypto.prepare(draft, existing: nil) }
        }
    }

    @Test
    func largestSupportedAccessCountIsPreservedAndDisabledLimitIgnoresStaleValue() throws {
        let crypto = SDKSendCryptography(crypto: TestSendCrypto())
        var draft = SendDraft(contentKind: .text)
        draft.hasMaxAccessCount = true
        draft.maxAccessCount = Int(UInt32.max)
        let prepared = try crypto.prepare(draft, existing: nil)
        let body = try #require(JSONSerialization.jsonObject(with: prepared.requestBody) as? [String: Any])
        #expect((body["maxAccessCount"] as? NSNumber)?.uint64Value == UInt64(UInt32.max))
        draft.hasMaxAccessCount = false
        draft.maxAccessCount = Int.max
        let unlimited = try crypto.prepare(draft, existing: nil)
        let unlimitedBody = try #require(JSONSerialization.jsonObject(with: unlimited.requestBody) as? [String: Any])
        #expect(unlimitedBody["maxAccessCount"] == nil)
    }

    @Test
    func nonfiniteDatesAreRejectedBeforeDateFormatting() {
        let crypto = SDKSendCryptography(crypto: TestSendCrypto())
        for interval in [Double.nan, .infinity, -.infinity] {
            var draft = SendDraft(contentKind: .text)
            draft.deletionDate = Date(timeIntervalSince1970: interval)
            #expect(throws: SendRepositoryError.invalidDraft) { try crypto.prepare(draft, existing: nil) }
            draft.deletionDate = Date()
            draft.hasExpirationDate = true
            draft.expirationDate = Date(timeIntervalSince1970: interval)
            #expect(throws: SendRepositoryError.invalidDraft) { try crypto.prepare(draft, existing: nil) }
        }
    }

    @Test
    func fileCreationCannotUseTheMetadataOnlyPortOrAnEditingDraft() throws {
        let crypto = SDKSendCryptography(crypto: TestSendCrypto())
        #expect(throws: SendRepositoryError.invalidDraft) {
            try crypto.prepare(SendDraft(contentKind: .file), existing: nil)
        }
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var draft = SendDraft(contentKind: .file)
        draft.editingID = SendID(rawValue: "existing")
        #expect(throws: SendRepositoryError.invalidDraft) {
            try crypto.prepareFile(
                draft,
                plaintextURL: directory.appendingPathComponent("in"),
                encryptedURL: directory.appendingPathComponent("out")
            )
        }
    }

    @Test
    func azureTicketRejectsEmbeddedCredentialsAndFragments() {
        let crypto = SDKSendCryptography(crypto: TestSendCrypto())
        for url in ["https://user:password@blob.example.com/file", "https://blob.example.com/file#fragment"] {
            let response = """
            {"url":"\(url)","fileUploadType":1,"sendResponse":{"id":"send","type":1,"name":"cipher-name","key":"cipher-key","revisionDate":"2026-09-01T00:00:00Z","deletionDate":"2026-10-01T00:00:00Z","file":{"id":"file","fileName":"encrypted-name"}}}
            """
            #expect(throws: SendRepositoryError.invalidResponse) { try crypto.decodeFileUploadTicket(Data(response.utf8)) }
        }
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "sdk-send-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return directory
    }

    @Test
    func fileUploadTicketRejectsUnknownKindsAndInsecureAzureURLs() {
        let crypto = SDKSendCryptography(crypto: TestSendCrypto())
        let base = #"{"url":"https://blob.example.com/file?sig=x","fileUploadType":2,"sendResponse":{"id":"send","type":1,"name":"cipher-name","key":"cipher-key","revisionDate":"2026-09-01T00:00:00Z","deletionDate":"2026-10-01T00:00:00Z","file":{"id":"file","fileName":"encrypted-name"}}}"#
        #expect(throws: SendRepositoryError.invalidResponse) {
            try crypto.decodeFileUploadTicket(Data(base.utf8))
        }
        let insecure = base.replacingOccurrences(of: "https://blob.example.com", with: "http://blob.example.com")
            .replacingOccurrences(of: "\"fileUploadType\":2", with: "\"fileUploadType\":1")
        #expect(throws: SendRepositoryError.invalidResponse) {
            try crypto.decodeFileUploadTicket(Data(insecure.utf8))
        }
    }

    @Test
    func malformedOrUnsupportedSendTypesFailClosedWithoutIntegerTraps() {
        let crypto = SDKSendCryptography(crypto: TestSendCrypto())
        for rawType in [-1, 2, 256, Int.max] {
            let json = """
            {"id":"send","type":\(rawType),"name":"cipher-name","key":"cipher-key","revisionDate":"2026-09-01T00:00:00Z","deletionDate":"2026-10-01T00:00:00Z"}
            """
            #expect(throws: SendRepositoryError.invalidResponse) {
                try crypto.decodeResponse(Data(json.utf8))
            }
        }
    }

    @Test
    func shareLinkMatchesVaultwardenFragmentFormat() throws {
        let encrypted = send(id: "send", name: "cipher-name", key: "Pgui0FK85cNhBGWHAlBHBw==")
        let record = try SDKSendCryptography(crypto: TestSendCrypto(views: ["send": view(
            id: "send", name: "Readable", accessID: "abc123", key: "Pgui0FK85cNhBGWHAlBHBw=="
        )])).decodeResponse(response(for: encrypted))

        let link = try SDKSendCryptography(crypto: TestSendCrypto(views: ["send": view(
            id: "send", name: "Readable", accessID: "abc123", key: "Pgui0FK85cNhBGWHAlBHBw=="
        )])).shareLink(for: record, webVaultURL: URL(string: "https://vault.example.com/")!)

        #expect(link.absoluteString == "https://vault.example.com/#/send/abc123/Pgui0FK85cNhBGWHAlBHBw")
    }

    private func response(for send: Send) throws -> Data {
        let type = Int(send.type.rawValue)
        let json = """
        {"id":"\(send.id ?? "")","accessId":"access","type":\(type),"name":"cipher-name","key":"cipher-key","revisionDate":"2026-09-01T00:00:00Z","deletionDate":"2026-10-01T00:00:00Z","text":{"text":"cipher-text","hidden":false}}
        """
        return Data(json.utf8)
    }

    private func send(
        id: String?, name: String, key: String, password: String? = nil,
        type: SendType = .text
    ) -> Send {
        Send(
            id: id, accessId: "access", name: name, notes: nil, key: key, password: password,
            type: type,
            file: type == .file ? SendFile(id: "file-id", fileName: "encrypted-file-name", size: nil, sizeName: nil) : nil,
            text: type == .text ? SendText(text: "encrypted-text", hidden: false) : nil,
            maxAccessCount: nil, accessCount: 0, disabled: false, hideEmail: false,
            revisionDate: Date(timeIntervalSince1970: 1_700_000_000),
            deletionDate: Date(timeIntervalSince1970: 1_800_000_000), expirationDate: nil,
            emails: nil, authType: password == nil ? .none : .password
        )
    }

    private func view(
        id: String, name: String, accessID: String? = "access", key: String? = "key"
    ) -> SendView {
        SendView(
            id: id, accessId: accessID, name: name, notes: nil, key: key, newPassword: nil,
            hasPassword: false, type: .text, file: nil,
            text: SendTextView(text: "plaintext", hidden: false), maxAccessCount: nil,
            accessCount: 0, disabled: false, hideEmail: false,
            revisionDate: Date(timeIntervalSince1970: 1_700_000_000),
            deletionDate: Date(timeIntervalSince1970: 1_800_000_000), expirationDate: nil,
            emails: [], authType: .none
        )
    }
}

private struct TestSendCrypto: SendCryptoServicing {
    var views: [String: SendView] = [:]
    var undecryptableIDs: Set<String> = []
    var encryptedSend: Send = Send(
        id: "encrypted", accessId: "access", name: "cipher-name", notes: nil, key: "cipher-key",
        password: nil, type: .text, file: nil, text: SendText(text: "encrypted-text", hidden: false),
        maxAccessCount: nil, accessCount: 0, disabled: false, hideEmail: false,
        revisionDate: Date(timeIntervalSince1970: 1_700_000_000),
        deletionDate: Date(timeIntervalSince1970: 1_800_000_000), expirationDate: nil,
        emails: nil, authType: .none
    )
    var encryptedBytes: Data = Data("encrypted-bytes".utf8)
    var encryptedFileLength: UInt64?

    func decryptList(_ sends: [Send]) throws -> [SendListView] { [] }
    func decrypt(_ send: Send) throws -> SendView {
        if let id = send.id, undecryptableIDs.contains(id) { throw SendRepositoryError.cryptoFailure }
        if let id = send.id, let view = views[id] { return view }
        return SendView(
            id: send.id, accessId: send.accessId, name: send.name, notes: nil, key: send.key,
            newPassword: nil, hasPassword: send.password != nil, type: send.type, file: nil,
            text: send.text.map { SendTextView(text: $0.text, hidden: $0.hidden) },
            maxAccessCount: send.maxAccessCount, accessCount: send.accessCount,
            disabled: send.disabled, hideEmail: send.hideEmail, revisionDate: send.revisionDate,
            deletionDate: send.deletionDate, expirationDate: send.expirationDate,
            emails: [], authType: send.authType
        )
    }

    func encrypt(_ sendView: SendView) throws -> Send {
        Send(
            id: encryptedSend.id, accessId: encryptedSend.accessId, name: encryptedSend.name,
            notes: encryptedSend.notes, key: encryptedSend.key, password: encryptedSend.password,
            type: encryptedSend.type, file: encryptedSend.file, text: encryptedSend.text,
            maxAccessCount: sendView.maxAccessCount, accessCount: encryptedSend.accessCount,
            disabled: encryptedSend.disabled, hideEmail: encryptedSend.hideEmail,
            revisionDate: encryptedSend.revisionDate, deletionDate: encryptedSend.deletionDate,
            expirationDate: encryptedSend.expirationDate, emails: encryptedSend.emails,
            authType: encryptedSend.authType
        )
    }

    func encryptFile(send: Send, plaintextURL: URL, encryptedURL: URL) throws {
        // Only the crypto fixture writes opaque bytes. Production calls the existing SDK file API.
        try encryptedBytes.write(to: encryptedURL)
        if let encryptedFileLength {
            let handle = try FileHandle(forWritingTo: encryptedURL)
            defer { try? handle.close() }
            try handle.truncate(atOffset: encryptedFileLength)
        }
    }
}
