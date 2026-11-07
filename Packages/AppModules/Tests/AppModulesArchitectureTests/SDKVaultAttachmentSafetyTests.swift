import BitwardenSdk
import BitwardenSDKAdapter
import Domain
import Foundation
import Networking
import Testing

/// Safety regressions formerly tested only against the unused AttachmentService.
/// Exercise the live source, including its revision/permission and SDK boundaries.
@Suite
struct SDKVaultAttachmentSafetyTests {
    @Test(arguments: [
        "https://vault.example.com/blob/xyz",
        "/ciphers/cipher-1/attachment/attachment-1",
    ])
    func downloadUsesOnlyTheConfiguredOriginAndRejectsRedirects(_ location: String) async throws {
        let fixture = try await Fixture()
        defer { fixture.removeDirectory() }
        fixture.http.responses = [
            try fixture.metadata(location),
            HTTPResponse(statusCode: 200, headers: [:], body: Data("encrypted-bytes".utf8)),
        ]

        try await fixture.download()

        let metadataRequest = fixture.http.calls[1].request
        #expect(metadataRequest.url.path == "/api/ciphers/cipher-1/attachment/attachment-1")
        let request = fixture.http.calls[2].request
        #expect(fixture.http.calls[2].transfer == .download)
        #expect(fixture.http.calls[2].fileURL == fixture.encryptedURL)
        #expect(request.url.host == "vault.example.com")
        let expectedPath = location.hasPrefix("/ciphers/")
            ? "/api" + URL(string: location)!.path
            : URL(string: location)!.path
        #expect(request.url.path == expectedPath)
        #expect(request.headers["Authorization"] == "Bearer token")
        #expect(request.redirectPolicy == .reject)
        #expect(try Data(contentsOf: fixture.encryptedURL) == Data("encrypted-bytes".utf8))
        #expect(try Data(contentsOf: fixture.decryptedURL) == fixture.crypto.decryptedAttachmentContents)
    }

    @Test(arguments: [
        "https://cdn.example.com/blob/xyz",
        "https://sub.vault.example.com/file",
        "http://vault.example.com/file",
        "https://vault.example.com:444/file",
        "//attacker.example.com/file",
        "https://user:password@vault.example.com/file",
    ])
    func downloadRejectsForeignOriginsBeforeAnyBlobRequest(_ location: String) async throws {
        let fixture = try await Fixture()
        defer { fixture.removeDirectory() }
        fixture.http.responses = [try fixture.metadata(location)]

        await #expect(throws: VaultRepositoryError.unsupportedOperation) { try await fixture.download() }

        #expect(fixture.http.calls.count == 2) // initial sync and same-origin metadata only
        #expect(!FileManager.default.fileExists(atPath: fixture.encryptedURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.decryptedURL.path))
        #expect(!fixture.crypto.events.contains("decryptAttachmentFile(attachment-1)"))
    }

    @Test
    func missingTokenCannotStartAnAttachmentRequest() async throws {
        let fixture = try await Fixture()
        defer { fixture.removeDirectory() }
        await fixture.token.clear()

        await #expect(throws: VaultRepositoryError.sessionClosed) { try await fixture.download() }

        #expect(fixture.http.calls.count == 1)
        #expect(!FileManager.default.fileExists(atPath: fixture.encryptedURL.path))
    }

    @Test(arguments: ["../../report\"\r\nInjected: true", "../nested/name", "name\\with\\slashes"])
    func uploadDoesNotAllowMultipartHeaderInjectionOrPathComponents(_ fileName: String) async throws {
        let fixture = try await Fixture()
        defer { fixture.removeDirectory() }
        fixture.crypto.encryptAttachmentResult = Attachment(
            id: nil,
            url: nil,
            size: nil,
            sizeName: nil,
            fileName: fileName,
            key: "encrypted-key"
        )
        fixture.http.responses = [
            HTTPResponse(statusCode: 200, headers: [:], body: Data(
                #"{"attachmentId":"attachment-1","url":"/blob","fileUploadType":0}"#.utf8
            )),
            HTTPResponse(statusCode: 200, headers: [:], body: Data()),
            HTTPResponse(statusCode: 200, headers: [:], body: Data(Fixture.cipherJSON.utf8)),
        ]

        try await fixture.source.uploadAttachment(
            to: fixture.context,
            file: MockImportedFile(url: fixture.directory.appendingPathComponent("original.bin")),
            encryptedURL: fixture.encryptedURL
        )

        let request = fixture.http.calls[2].request
        let body = try #require(request.body)
        #expect(fixture.http.calls[2].transfer == .upload)
        #expect(fixture.http.calls[2].submittedBodyWasNil)
        let string = String(decoding: body, as: UTF8.self)
        let expectedName = fileName == "../nested/name" ? "name" : "attachment"
        #expect(string.contains("filename=\"\(expectedName)\""))
        #expect(!string.contains("Injected: true"))
        #expect(!string.contains("../"))
        #expect(body.range(of: fixture.crypto.encryptedAttachmentContents) != nil)
        #expect(request.url.absoluteString == "https://vault.example.com/blob")
        #expect(request.redirectPolicy == .reject)
    }

    @Test
    func failedBlobDownloadNeverStartsDecryption() async throws {
        let fixture = try await Fixture()
        defer { fixture.removeDirectory() }
        fixture.http.responses = [
            try fixture.metadata("/blob"),
            HTTPResponse(statusCode: 503, headers: [:], body: Data()),
        ]
        await #expect(throws: HTTPStatusError.self) { try await fixture.download() }
        #expect(fixture.http.calls.last?.transfer == .download)
        #expect(!fixture.crypto.events.contains("decryptAttachmentFile(attachment-1)"))
        #expect(!FileManager.default.fileExists(atPath: fixture.decryptedURL.path))
    }

    @Test
    func secretsRevokedDuringDownloadDoNotReachSDKDecryption() async throws {
        let fixture = try await Fixture()
        defer { fixture.removeDirectory() }
        fixture.http.responses = [try fixture.metadata("/blob"),
                                  HTTPResponse(statusCode: 200, headers: [:], body: Data("encrypted".utf8)),
                                  HTTPResponse(
                                      statusCode: 200,
                                      headers: [:],
                                      body: Data("{\"ciphers\":[\(Fixture.cipherJSON)]}".utf8)
                                  )]
        fixture.http.beforeDownloadReturns = {
            fixture.crypto.decryptCiphersResult = [.fixture(reprompt: .password)]
            _ = try await fixture.source.fetchOutput()
        }
        await #expect(throws: VaultRepositoryError.readOnly) { try await fixture.download() }
        #expect(!fixture.crypto.events.contains("decryptAttachmentFile(attachment-1)"))
        #expect(!FileManager.default.fileExists(atPath: fixture.decryptedURL.path))
    }
}

private actor AttachmentToken {
    private var value: String? = "token"
    func current() -> String? { value }
    func clear() { value = nil }
}

private struct Fixture: Sendable {
    static let cipherJSON = """
    {"id":"cipher-1","type":1,"name":"encrypted-name","favorite":false,"reprompt":0,
     "revisionDate":"1970-01-01T00:00:00.000Z","creationDate":"1970-01-01T00:00:00.000Z",
     "login":{"username":"encrypted-user","password":"encrypted-password"}}
    """
    let http = MockHTTPClient()
    let crypto = SpyVaultCryptoService()
    let token = AttachmentToken()
    let source: SDKVaultSessionSource
    let directory: URL
    let context = VaultItemContext(id: CipherID(rawValue: "cipher-1"), revision: Date(timeIntervalSince1970: 0))
    var encryptedURL: URL { directory.appendingPathComponent("encrypted.data") }
    var decryptedURL: URL { directory.appendingPathComponent("decrypted.data") }

    init() async throws {
        let token = token
        source = SDKVaultSessionSource(
            http: http,
            environment: try Domain.ServerEnvironment(baseURL: URL(string: "https://vault.example.com")!),
            crypto: crypto,
            accessToken: { await token.current() },
            checkAccess: { try Task.checkCancellation() }
        )
        crypto.decryptCiphersResult = [.fixture(attachments: [
            AttachmentView(
                id: "attachment-1",
                url: nil,
                size: nil,
                sizeName: nil,
                fileName: "preview.bin",
                key: "encrypted-key"
            ),
        ])]
        http.responses = [HTTPResponse(
            statusCode: 200,
            headers: [:],
            body: Data("{\"ciphers\":[\(Self.cipherJSON)]}".utf8)
        )]
        _ = try await source.fetchOutput()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sdk-attachment-safety-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }

    func metadata(_ location: String) throws -> HTTPResponse {
        let dto = AttachmentResponseDTO(
            id: "attachment-1",
            url: location,
            fileName: nil,
            key: nil,
            size: nil,
            sizeName: nil
        )
        return HTTPResponse(statusCode: 200, headers: [:], body: try JSONEncoder().encode(dto))
    }

    func download() async throws {
        try await source.downloadAttachment(
            attachmentReference(),
            context: context,
            encryptedURL: encryptedURL,
            decryptedURL: decryptedURL
        )
    }

    func removeDirectory() { try? FileManager.default.removeItem(at: directory) }
}
