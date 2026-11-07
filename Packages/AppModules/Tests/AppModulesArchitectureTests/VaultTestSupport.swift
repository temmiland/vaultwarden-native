import BitwardenSdk
import BitwardenSDKAdapter
import Domain
import Foundation
import Networking

func vaultSnapshot(
    ciphers: [CipherView] = [],
    collections: [CollectionView] = [],
    revision: UInt64 = 1,
    warnings: [VaultLoadWarning] = []
) -> VaultSnapshot {
    let collectionSummaries = SDKVaultPresentationMapper.collections(from: collections)
    let details = ciphers.compactMap { SDKVaultPresentationMapper.detail(from: $0, collections: collectionSummaries) }
    return VaultSnapshot(
        revision: revision,
        items: SDKVaultPresentationMapper.summaries(from: ciphers, collections: collectionSummaries),
        lastSuccessfulSync: nil,
        isStale: false,
        details: Dictionary(uniqueKeysWithValues: details.map { ($0.id, $0) }),
        collections: collectionSummaries,
        warnings: warnings
    )
}

func attachmentReference(cipherID: String = "cipher-1", attachmentID: String = "attachment-1") -> VaultAttachmentReference {
    VaultAttachmentReference(cipherID: CipherID(rawValue: cipherID), attachmentID: AttachmentID(rawValue: attachmentID))
}

struct MockImportedFile: ImportedFile {
    let fileName: String
    let url: URL

    init(url: URL, fileName: String? = nil) {
        self.url = url
        self.fileName = fileName ?? url.lastPathComponent
    }

    func withSecurityScopedAccess<Value: Sendable>(
        _ operation: @Sendable (URL) async throws -> Value
    ) async throws -> Value {
        try await operation(url)
    }
}

@MainActor
final class MockFileImportClient: FileImportClient {
    var file: (any ImportedFile)?
    var errorToThrow: Error?

    init(file: (any ImportedFile)? = nil) {
        self.file = file
    }

    func pickFile() async throws -> (any ImportedFile)? {
        if let errorToThrow { throw errorToThrow }
        return file
    }
}

// MARK: - HTTPClient mock

final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    enum Transfer { case send, upload, download }
    struct Call {
        let request: HTTPRequest
        let transfer: Transfer
        let fileURL: URL?
        let submittedBodyWasNil: Bool
    }

    private(set) var calls: [Call] = []
    var responses: [HTTPResponse] = []
    var responseProvider: ((HTTPRequest) -> HTTPResponse)?
    var errorToThrow: Error?
    var beforeDownloadReturns: (@Sendable () async throws -> Void)?

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try perform(request, transfer: .send)
    }

    private func perform(
        _ request: HTTPRequest,
        transfer: Transfer,
        fileURL: URL? = nil,
        submittedBodyWasNil: Bool? = nil
    ) throws -> HTTPResponse {
        calls.append(
            Call(
                request: request,
                transfer: transfer,
                fileURL: fileURL,
                submittedBodyWasNil: submittedBodyWasNil ?? (request.body == nil)
            )
        )
        if let errorToThrow {
            throw errorToThrow
        }
        if let responseProvider {
            return responseProvider(request)
        }
        if !responses.isEmpty {
            return responses.removeFirst()
        }
        return HTTPResponse(statusCode: 200, headers: [:], body: Data())
    }

    func upload(_ request: HTTPRequest, fromFile fileURL: URL) async throws -> HTTPResponse {
        let submittedBodyWasNil = request.body == nil
        var request = request
        // Small response fixtures intentionally inspect uploaded bytes. The separate multipart
        // builder tests exercise large files without this inspection-only whole-file read.
        request.body = try Data(contentsOf: fileURL)
        return try perform(request, transfer: .upload, fileURL: fileURL, submittedBodyWasNil: submittedBodyWasNil)
    }

    func download(_ request: HTTPRequest, to destinationURL: URL) async throws -> HTTPFileResponse {
        let response = try perform(request, transfer: .download, fileURL: destinationURL)
        try response.requireSuccess()
        try response.body.write(to: destinationURL)
        try await beforeDownloadReturns?()
        return HTTPFileResponse(statusCode: response.statusCode, headers: response.headers)
    }
}

// MARK: - VaultCryptoServicing spy

final class SpyVaultCryptoService: VaultCryptoServicing, @unchecked Sendable {
    private(set) var events: [String] = []

    var decryptCiphersResult: [CipherView] = []
    var decryptCipherResult: CipherView?
    var encryptCipherResult: EncryptionContext?
    var decryptFoldersResult: [FolderView] = []
    var decryptCollectionsResult: [CollectionView] = []
    var totpResult: TotpResponse = TotpResponse(code: "123456", period: 30)
    var fido2CredentialsResult: [Fido2CredentialView] = []
    var encryptAttachmentResult: Attachment?
    /// What `encryptAttachmentFile`/`decryptAttachmentFile` write to `encryptedFilePath` /
    /// `decryptedFilePath` respectively, so callers that inspect the file afterwards (size,
    /// contents, existence for cleanup) don't need real attachment bytes or a real FFI-backed SDK.
    var encryptedAttachmentContents = Data("encrypted-attachment".utf8)
    var decryptedAttachmentContents = Data("decrypted-attachment".utf8)
    var errorToThrow: Error?
    private(set) var lastOrganizationKeys: [String: String]?
    private(set) var lastDecryptedCiphers: [Cipher] = []
    /// Allows a save regression to refresh local state while encryption is suspended.
    var beforeEncryptReturns: (@Sendable () async -> Void)?
    var decryptCipherError: Error?

    func initializeOrganizationCrypto(organizationKeys: [String: String]) async throws {
        events.append("initializeOrganizationCrypto(\(organizationKeys.count))")
        lastOrganizationKeys = organizationKeys
        if let errorToThrow { throw errorToThrow }
    }

    func decryptCiphers(_ ciphers: [Cipher]) async throws -> [CipherView] {
        lastDecryptedCiphers = ciphers
        events.append("decryptCiphers(\(ciphers.count))")
        if let errorToThrow { throw errorToThrow }
        return decryptCiphersResult
    }

    func decryptCipher(_ cipher: Cipher) async throws -> CipherView {
        events.append("decryptCipher(\(cipher.id ?? "nil"))")
        if let decryptCipherError { throw decryptCipherError }
        if let errorToThrow { throw errorToThrow }
        return decryptCipherResult ?? .fixture()
    }

    func encryptCipher(_ cipherView: CipherView) async throws -> EncryptionContext {
        events.append("encryptCipher(\(cipherView.name))")
        if let errorToThrow { throw errorToThrow }
        await beforeEncryptReturns?()
        return encryptCipherResult ?? EncryptionContext(encryptedFor: "user-1", cipher: .fixture())
    }

    func decryptFolders(_ folders: [Folder]) throws -> [FolderView] {
        events.append("decryptFolders(\(folders.count))")
        if let errorToThrow { throw errorToThrow }
        return decryptFoldersResult
    }

    func decryptCollections(_ collections: [Collection]) throws -> [CollectionView] {
        events.append("decryptCollections(\(collections.count))")
        if let errorToThrow { throw errorToThrow }
        return decryptCollectionsResult
    }

    func generateTotp(key: String, at date: Date?) throws -> TotpResponse {
        events.append("generateTotp")
        if let errorToThrow { throw errorToThrow }
        return totpResult
    }

    func decryptFido2Credentials(cipherView: CipherView) throws -> [Fido2CredentialView] {
        events.append("decryptFido2Credentials(\(cipherView.id ?? "nil"))")
        if let errorToThrow { throw errorToThrow }
        return fido2CredentialsResult
    }

    var fido2AutofillCredentialsResult: [Fido2CredentialAutofillView] = []

    func decryptFido2AutofillCredentials(cipherView: CipherView) throws -> [Fido2CredentialAutofillView] {
        events.append("decryptFido2AutofillCredentials(\(cipherView.id ?? "nil"))")
        if let errorToThrow { throw errorToThrow }
        return fido2AutofillCredentialsResult
    }

    func encryptAttachmentFile(
        cipher: Cipher,
        attachment: AttachmentView,
        decryptedFilePath: String,
        encryptedFilePath: String
    ) throws -> Attachment {
        events.append("encryptAttachmentFile(\(attachment.fileName ?? "nil"))")
        if let errorToThrow { throw errorToThrow }
        try encryptedAttachmentContents.write(to: URL(fileURLWithPath: encryptedFilePath))
        return encryptAttachmentResult ?? Attachment(
            id: "attachment-1", url: nil, size: "10", sizeName: "10 B", fileName: attachment.fileName,
            key: "enc-attachment-key"
        )
    }

    func decryptAttachmentFile(
        cipher: Cipher,
        attachment: AttachmentView,
        encryptedFilePath: String,
        decryptedFilePath: String
    ) throws {
        events.append("decryptAttachmentFile(\(attachment.id ?? "nil"))")
        if let errorToThrow { throw errorToThrow }
        try decryptedAttachmentContents.write(to: URL(fileURLWithPath: decryptedFilePath))
    }
}

// MARK: - Fixtures

extension Cipher {
    static func fixture(
        id: String? = "cipher-1",
        name: String? = "Example",
        type: CipherType = .login,
        login: Login? = Login(
            username: "user",
            password: "pass",
            passwordRevisionDate: nil,
            uris: nil,
            totp: nil,
            autofillOnPageLoad: nil,
            fido2Credentials: nil
        )
    ) -> Cipher {
        Cipher(
            id: id,
            organizationId: nil,
            folderId: nil,
            collectionIds: [],
            key: nil,
            name: name,
            notes: nil,
            type: type,
            login: login,
            identity: nil,
            card: nil,
            secureNote: nil,
            sshKey: nil,
            bankAccount: nil,
            driversLicense: nil,
            passport: nil,
            favorite: false,
            reprompt: .none,
            organizationUseTotp: false,
            edit: true,
            permissions: nil,
            viewPassword: true,
            localData: nil,
            attachments: nil,
            fields: nil,
            passwordHistory: nil,
            creationDate: Date(timeIntervalSince1970: 0),
            deletedDate: nil,
            revisionDate: Date(timeIntervalSince1970: 0),
            archivedDate: nil,
            data: nil
        )
    }
}

extension CipherView {
    static func fixture(
        id: String? = "cipher-1",
        organizationId: String? = nil,
        collectionIds: [String] = [],
        name: String = "Example",
        type: CipherType = .login,
        login: LoginView? = LoginView(
            username: "user",
            password: "pass",
            passwordRevisionDate: nil,
            uris: nil,
            totp: nil,
            autofillOnPageLoad: nil,
            fido2Credentials: nil
        ),
        identity: IdentityView? = nil,
        card: CardView? = nil,
        sshKey: SshKeyView? = nil,
        edit: Bool = true,
        permissions: CipherPermissions? = nil,
        viewPassword: Bool = true,
        reprompt: CipherRepromptType = .none,
        attachments: [AttachmentView]? = nil,
        attachmentDecryptionFailures: [String]? = nil,
        deletedDate: Date? = nil,
        revisionDate: Date = Date(timeIntervalSince1970: 0),
        archivedDate: Date? = nil
    ) -> CipherView {
        CipherView(
            id: id,
            organizationId: organizationId,
            folderId: nil,
            collectionIds: collectionIds,
            key: nil,
            name: name,
            notes: nil,
            type: type,
            login: login,
            identity: identity,
            card: card,
            secureNote: nil,
            sshKey: sshKey,
            bankAccount: nil,
            driversLicense: nil,
            passport: nil,
            favorite: false,
            reprompt: reprompt,
            organizationUseTotp: false,
            edit: edit,
            permissions: permissions,
            viewPassword: viewPassword,
            localData: nil,
            attachments: attachments,
            attachmentDecryptionFailures: attachmentDecryptionFailures?.map {
                AttachmentView(id: $0, url: nil, size: nil, sizeName: nil, fileName: nil, key: nil)
            },
            fields: nil,
            passwordHistory: nil,
            creationDate: Date(timeIntervalSince1970: 0),
            deletedDate: deletedDate,
            revisionDate: revisionDate,
            archivedDate: archivedDate
        )
    }
}

extension CollectionView {
    static func fixture(
        id: String? = "collection-1",
        organizationId: String = "org-1",
        name: String = "Engineering",
        readOnly: Bool = false,
        hidePasswords: Bool = false,
        manage: Bool = false
    ) -> CollectionView {
        CollectionView(
            id: id,
            organizationId: organizationId,
            name: name,
            externalId: nil,
            hidePasswords: hidePasswords,
            readOnly: readOnly,
            manage: manage,
            type: .sharedCollection
        )
    }
}
