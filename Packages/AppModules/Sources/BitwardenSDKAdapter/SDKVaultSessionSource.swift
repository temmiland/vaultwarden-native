import AutoFillContract
import BitwardenSdk
import Domain
import Foundation
import Networking

public struct SDKVaultOutput: Sendable {
    public let snapshot: VaultSnapshot
    public let encryptedLoginRecords: [EncryptedLoginRecord]
    public let encryptedOrganizationKeys: [String: String]
    public let identitySources: [VaultLoginIdentitySource]
}

/// SDK backing for the repository, not a second screen state. Data serializes sync/mutations;
/// only this adapter retains decrypted SDK records required for lossless edit/crypto operations.
public actor SDKVaultSessionSource {
    private let http: any HTTPClient
    private let environment: Domain.ServerEnvironment
    private let crypto: any VaultCryptoServicing
    private let accessToken: @Sendable () async -> String?
    private let requireAccessToken: (@Sendable () async throws -> String)?
    private let checkAccess: @Sendable () throws -> Void
    private var ciphers: [String: CipherView] = [:]
    private var encrypted: [String: CipherResponseDTO] = [:]
    private var folders: [FolderView] = []
    private var collections: [CollectionView] = []
    private var organizationKeys: [String: String] = [:]
    private var organizationNames: [String: String] = [:]
    private var warnings: [VaultLoadWarning] = []
    private var revision: UInt64
    private var isClosed = false
    private var requiresSync = false

    public init(
        http: any HTTPClient,
        environment: Domain.ServerEnvironment,
        crypto: any VaultCryptoServicing,
        accessToken: @escaping @Sendable () async -> String?,
        requireAccessToken: (@Sendable () async throws -> String)? = nil,
        checkAccess: @escaping @Sendable () throws -> Void,
        initialRevision: UInt64 = 0
    ) {
        self.http = http; self.environment = environment; self.crypto = crypto
        self.accessToken = accessToken; self.checkAccess = checkAccess; revision = initialRevision
        self.requireAccessToken = requireAccessToken
    }

    public func fetchOutput() async throws -> SDKVaultOutput {
        try check()
        guard revision < .max else { throw VaultRepositoryError.unsupportedOperation }
        let url = environment.apiURL.appendingPathComponent("sync")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "excludeDomains", value: "true")]
        let response = try await send(
            url: components?.url ?? url,
            method: .get,
            maximumResponseBytes: HTTPResponseBodyLimit.vaultSync
        )
        let dto = try JSONDecoder().decode(SyncResponseDTO.self, from: response.body)
        var keys: [String: String] = [:]
        var names: [String: String] = [:]
        var organizationIDs = Set<String>()
        for organization in dto.profile?.organizations ?? [] {
            guard let id = organization.id else { continue }
            guard !id.isEmpty, organizationIDs.insert(id).inserted else { throw CipherMappingError.invalidField(
                "profile.organizations.id"
            ) }
            keys[id] = organization.key; names[id] = organization.name
        }
        // From this point a failed sync may have changed the SDK's organization key set. Old
        // views remain readable, but mutations must wait for a successful coherent sync.
        requiresSync = true
        try await crypto.initializeOrganizationCrypto(organizationKeys: keys)
        let active = (dto.ciphers ?? []).filter { $0.deletedDate == nil && $0.archivedDate == nil }
        let counts = active.reduce(into: [String: Int]()) { counts, cipher in
            if let id = cipher.id { counts[id, default: 0] += 1 }
        }
        var sdk: [Cipher] = []
        var raw: [String: CipherResponseDTO] = [:]
        var unavailable = 0
        for cipher in active {
            try check()
            guard let id = cipher.id, !id.isEmpty, counts[id] == 1 else { unavailable += 1; continue }
            raw[id] = cipher
            do { sdk.append(try cipher.toSDKCipher()) }
            catch is CipherMappingError { unavailable += 1 }
        }
        let decrypted = try await crypto.decryptCiphers(sdk)
        try check()
        let decryptedIDs = Set(decrypted.compactMap(\.id))
        unavailable += sdk.filter { $0.id.map { !decryptedIDs.contains($0) } ?? true }.count
        let nextFolders = try crypto.decryptFolders(try (dto.folders ?? []).map { try $0.toSDKFolder() })
        let nextCollections = try crypto.decryptCollections(try (dto.collections ?? []).map { try $0.toSDKCollection() })
        try check()
        var nextCiphers: [String: CipherView] = [:]
        for view in decrypted {
            guard let id = view.id, raw[id] != nil, nextCiphers[id] == nil else {
                throw CipherMappingError.invalidField("decrypted.id")
            }
            nextCiphers[id] = view
        }
        ciphers = nextCiphers
        encrypted = raw; folders = nextFolders; collections = nextCollections
        organizationKeys = keys; organizationNames = names
        warnings = unavailable > 0 ? [.unavailableItems(count: unavailable)] : []
        requiresSync = false
        revision += 1
        return try currentOutput()
    }

    public func currentOutput() throws -> SDKVaultOutput {
        try check()
        let views = ciphers.values.sorted { ($0.id ?? "") < ($1.id ?? "") }
        let collectionSummaries = SDKVaultPresentationMapper.collections(from: collections)
        let unsupportedPayloadIDs = Set(encrypted.values.filter(\.hasUnrecognizedPayload).compactMap(\.id))
        let details = views.compactMap { SDKVaultPresentationMapper.detail(
            from: $0,
            collections: collectionSummaries,
            organizationName: $0.organizationId.flatMap { organizationNames[$0] },
            supportsLosslessEditing: $0.id.map { !unsupportedPayloadIDs.contains($0) } ?? false
        ) }
        // The old extension schema has no collection permissions. Exclude entries whose current
        // resolved Domain permission does not prove secret access rather than exporting a bypass.
        let eligibleIDs = Set(views.filter {
            SDKVaultAccessPolicy.isEligibleForAutoFill($0) &&
                SDKVaultPresentationMapper.permissions(for: $0, collections: collectionSummaries).canViewSecrets
        }.compactMap(\.id))
        let records = try encrypted.values.filter {
            SDKVaultAccessPolicy.isEligibleForAutoFill($0) && $0.id.map(eligibleIDs.contains) == true
        }.sorted { ($0.id ?? "") < ($1.id ?? "") }
            .compactMap { cipher -> EncryptedLoginRecord? in
                guard let id = cipher.id else { return nil }
                return EncryptedLoginRecord(
                    id: id,
                    deletedAt: nil,
                    encryptedCipherPayload: try JSONEncoder().encode(cipher)
                )
            }
        let identitySources = views.compactMap { view -> VaultLoginIdentitySource? in
            guard let id = view.id, SDKVaultAccessPolicy.isEligibleForAutoFill(view), let login = view.login,
                  SDKVaultPresentationMapper.permissions(for: view, collections: collectionSummaries).canViewSecrets
            else { return nil }
            let passkeys = (try? crypto.decryptFido2AutofillCredentials(cipherView: view)) ?? []
            return VaultLoginIdentitySource(
                cipherID: CipherID(rawValue: id),
                displayName: view.name,
                username: login.username,
                serviceIdentifiers: (login.uris ?? []).compactMap(\.uri),
                hasOneTimeCode: !(login.totp ?? "").isEmpty,
                passkeys: passkeys.map { PasskeyIdentitySource(
                    relyingPartyIdentifier: $0.rpId,
                    userName: $0.userNameForUi ?? login.username ?? view.name,
                    credentialID: $0.credentialId,
                    userHandle: $0.userHandle
                ) },
                isEligibleForAutoFill: true
            )
        }
        let snapshot = VaultSnapshot(
            revision: revision,
            items: SDKVaultPresentationMapper.summaries(
                from: views, collections: collectionSummaries, unsupportedPayloadIDs: unsupportedPayloadIDs
            ),
            lastSuccessfulSync: nil,
            isStale: requiresSync,
            details: Dictionary(uniqueKeysWithValues: details.map { ($0.id, $0) }),
            folders: SDKVaultPresentationMapper.folders(from: folders),
            collections: collectionSummaries,
            organizationNames: Dictionary(
                uniqueKeysWithValues: organizationNames.map { (OrganizationID(rawValue: $0.key), $0.value) }
            ),
            warnings: warnings
        )
        return SDKVaultOutput(
            snapshot: snapshot,
            encryptedLoginRecords: records,
            encryptedOrganizationKeys: organizationKeys,
            identitySources: identitySources
        )
    }

    public func makeDraft(for id: CipherID) throws -> VaultItemDraft {
        try checkMutation()
        guard let cipher = ciphers[id.rawValue] else { throw VaultItemDraftError.missingItem }
        guard permissions(cipher).canEdit else { throw VaultItemDraftError.readOnly }
        return try SDKVaultItemDraftMapper.makeDraft(from: cipher)
    }

    public func save(_ draft: VaultItemDraft) async throws -> CipherID {
        try checkMutation()
        let view = try applying(draft)
        let context = try await crypto.encryptCipher(view)
        try checkMutation()
        _ = try applying(draft)
        let url = draft.editingID.map { environment.apiURL.appendingPathComponent("ciphers").appendingPathComponent(
            $0.rawValue
        ) }
            ?? environment.apiURL.appendingPathComponent("ciphers")
        let response = try await send(
            url: url,
            method: draft.editingID == nil ? .post : .put,
            body: try JSONEncoder().encode(CipherRequestDTO(
                cipher: context.cipher,
                encryptedFor: context.encryptedFor,
                lastKnownRevisionDate: draft.editingID == nil ? nil : draft.baseRevision
            ))
        )
        do {
            let raw = try JSONDecoder().decode(CipherResponseDTO.self, from: response.body)
            guard raw.encryptedFor == nil || raw.encryptedFor == context.encryptedFor else {
                throw CipherMappingError.invalidField("encryptedFor")
            }
            guard let id = raw.id, !id.isEmpty, draft.editingID == nil || draft.editingID?.rawValue == id
            else { throw VaultRepositoryError.missingItem }
            let decrypted = try await crypto.decryptCipher(try raw.toSDKCipher())
            try check()
            encrypted[id] = raw; ciphers[id] = decrypted
            revision += 1
            return CipherID(rawValue: id)
        } catch {
            requiresSync = true
            if error is CancellationError { throw error }
            throw VaultRepositoryError.committedButRefreshFailed
        }
    }

    public func delete(_ context: VaultItemContext) async throws {
        let cipher = try currentCipher(context, requiringEdit: false)
        guard permissions(cipher).canDelete else { throw VaultRepositoryError.readOnly }
        _ = try await send(url: cipherURL(context.id), method: .delete)
        try check()
        ciphers.removeValue(forKey: context.id.rawValue); encrypted.removeValue(forKey: context.id.rawValue)
        revision += 1
    }

    public func oneTimeCode(for context: VaultItemContext) throws -> VaultOneTimeCode {
        let cipher = try currentCipher(context, requiringEdit: false)
        guard permissions(cipher).canViewSecrets, let seed = cipher.login?.totp, !seed.isEmpty else { throw VaultRepositoryError.readOnly }
        let response = try crypto.generateTotp(key: seed, at: nil)
        try check()
        return VaultOneTimeCode(context: context, code: response.code, period: response.period)
    }

    public func passkeys(for context: VaultItemContext) throws -> [VaultPasskeySummary] {
        let cipher = try currentCipher(context, requiringEdit: false)
        guard permissions(cipher).canViewSecrets else { throw VaultRepositoryError.readOnly }
        return SDKVaultPresentationMapper.passkeys(from: try crypto.decryptFido2Credentials(cipherView: cipher))
    }

    public func uploadAttachment(to context: VaultItemContext, file: any ImportedFile, encryptedURL: URL) async throws {
        _ = try currentCipher(context, requiringEdit: true)
        let metadata = try await file.withSecurityScopedAccess { [self] inputURL in
            try await encryptAttachment(
                context: context,
                inputURL: inputURL,
                encryptedURL: encryptedURL,
                fileName: file.fileName
            )
        }
        _ = try currentCipher(context, requiringEdit: true)
        guard let size = (try FileManager.default.attributesOfItem(atPath: encryptedURL.path))[.size] as? NSNumber,
              size.int64Value >= 0 else { throw VaultRepositoryError.unsupportedOperation }
        let request = AttachmentRequestDTO(
            key: metadata.key,
            fileName: metadata.fileName ?? file.fileName,
            fileSize: size.uint64Value
        )
        let response = try await send(
            url: cipherURL(context.id).appendingPathComponent("attachment/v2"),
            method: .post,
            body: try JSONEncoder().encode(request)
        )
        do {
            let upload = try JSONDecoder().decode(AttachmentUploadDataResponseDTO.self, from: response.body)
            guard (upload.fileUploadType ?? 0) == 0, let uploadURL = upload.url else { throw VaultRepositoryError.committedButRefreshFailed }
            // Validate origin BEFORE token acquisition or file assembly. The enclosing registered
            // work directory owns this additional encrypted body and cleanup on every exit.
            let url = try trustedAttachmentURL(uploadURL)
            let body = try MultipartFileBody.prepare(
                inputURL: encryptedURL,
                outputURL: encryptedURL.deletingLastPathComponent().appendingPathComponent(
                    "multipart-\(UUID().uuidString)"
                ),
                fileName: metadata.fileName ?? "attachment",
                boundary: "Boundary-\(UUID().uuidString)",
                checkAccess: checkAccess
            )
            let uploadRequest = try await authorizedRequest(url: url, method: .post, headers: [
                "Content-Type": body.contentType, "Content-Length": String(body.byteCount),
            ])
            _ = try currentCipher(context, requiringEdit: true)
            let uploadResponse = try await http.upload(uploadRequest, fromFile: body.fileURL)
            try uploadResponse.requireSuccess()
            try check()
            try await refreshAfterCommittedMutation(context.id)
        } catch {
            requiresSync = true
            if error is CancellationError { throw error }
            throw VaultRepositoryError.committedButRefreshFailed
        }
    }

    public func deleteAttachment(_ reference: VaultAttachmentReference, context: VaultItemContext) async throws {
        let cipher = try currentCipher(context, requiringEdit: true)
        guard reference.cipherID == context.id, cipher.attachments?.filter({ $0.id == reference.attachmentID.rawValue }).count == 1
        else { throw VaultRepositoryError.missingItem }
        _ = try await send(
            url: cipherURL(context.id).appendingPathComponent("attachment").appendingPathComponent(
                reference.attachmentID.rawValue
            ),
            method: .delete
        )
        try await refreshAfterCommittedMutation(context.id)
    }

    public func downloadAttachment(
        _ reference: VaultAttachmentReference,
        context: VaultItemContext,
        encryptedURL: URL,
        decryptedURL: URL
    ) async throws {
        let cipher = try currentCipher(context, requiringEdit: false)
        guard reference.cipherID == context.id, permissions(cipher).canViewSecrets,
              cipher.attachments?.filter({ $0.id == reference.attachmentID.rawValue }).count == 1,
              let attachment = cipher.attachments?.first(where: { $0.id == reference.attachmentID.rawValue })
        else { throw VaultRepositoryError.readOnly }
        let response = try await send(
            url: cipherURL(context.id).appendingPathComponent("attachment").appendingPathComponent(
                reference.attachmentID.rawValue
            ),
            method: .get
        )
        let metadata = try JSONDecoder().decode(AttachmentResponseDTO.self, from: response.body)
        guard let url = metadata.url else { throw VaultRepositoryError.missingItem }
        var downloadRequest = try await authorizedRequest(url: trustedAttachmentURL(url), method: .get)
        downloadRequest.maximumResponseBytes = HTTPResponseBodyLimit.fileDownload
        _ = try readableCipher(context)
        let downloaded = try await http.download(downloadRequest, to: encryptedURL)
        guard (200 ..< 300).contains(downloaded.statusCode) else {
            throw HTTPStatusError(
                response: HTTPResponse(
                    statusCode: downloaded.statusCode,
                    headers: downloaded.headers,
                    body: Foundation.Data()
                )
            )
        }
        _ = try readableCipher(context)
        let keyContext = try await crypto.encryptCipher(cipher)
        _ = try readableCipher(context)
        try crypto.decryptAttachmentFile(
            cipher: keyContext.cipher,
            attachment: attachment,
            encryptedFilePath: encryptedURL.path,
            decryptedFilePath: decryptedURL.path
        )
        _ = try readableCipher(context)
    }

    private func readableCipher(_ context: VaultItemContext) throws -> CipherView {
        let cipher = try currentCipher(context, requiringEdit: false)
        guard permissions(cipher).canViewSecrets else { throw VaultRepositoryError.readOnly }
        return cipher
    }

    private func encryptAttachment(context: VaultItemContext, inputURL: URL, encryptedURL: URL, fileName: String) async throws -> Attachment {
        let cipher = try currentCipher(context, requiringEdit: true)
        let keyContext = try await crypto.encryptCipher(cipher)
        _ = try currentCipher(context, requiringEdit: true)
        return try crypto.encryptAttachmentFile(
            cipher: keyContext.cipher,
            attachment: AttachmentView(id: nil, url: nil, size: nil, sizeName: nil, fileName: fileName, key: nil),
            decryptedFilePath: inputURL.path,
            encryptedFilePath: encryptedURL.path
        )
    }

    private func refreshAfterCommittedMutation(_ id: CipherID) async throws {
        do {
            let response = try await send(url: cipherURL(id), method: .get)
            let raw = try JSONDecoder().decode(CipherResponseDTO.self, from: response.body)
            guard raw.id == id.rawValue else { throw VaultRepositoryError.missingItem }
            let view = try await crypto.decryptCipher(try raw.toSDKCipher())
            try check()
            encrypted[id.rawValue] = raw; ciphers[id.rawValue] = view; revision += 1
        } catch {
            requiresSync = true
            if error is CancellationError { throw error }
            throw VaultRepositoryError.committedButRefreshFailed
        }
    }

    private func applying(_ draft: VaultItemDraft) throws -> CipherView {
        let existing = draft.editingID.flatMap { ciphers[$0.rawValue] }
        if let existing, !permissions(existing).canEdit { throw VaultItemDraftError.readOnly }
        return try SDKVaultItemDraftMapper.applying(draft, to: existing)
    }

    private func currentCipher(_ context: VaultItemContext, requiringEdit: Bool) throws -> CipherView {
        try checkMutation()
        guard let cipher = ciphers[context.id.rawValue] else { throw VaultRepositoryError.missingItem }
        guard cipher.revisionDate == context.revision else { throw VaultRepositoryError.staleItem }
        if requiringEdit, !permissions(cipher).canEdit { throw VaultRepositoryError.readOnly }
        return cipher
    }

    private func permissions(_ cipher: CipherView) -> VaultItemPermissions {
        SDKVaultPresentationMapper.permissions(
            for: cipher,
            collections: SDKVaultPresentationMapper.collections(from: collections),
            supportsLosslessEditing: cipher.id.flatMap { encrypted[$0] }?.hasUnrecognizedPayload == false
        )
    }

    private func checkMutation() throws {
        try check()
        guard !requiresSync else { throw VaultRepositoryError.staleItem }
        guard revision < .max else { throw VaultRepositoryError.unsupportedOperation }
    }

    private func check() throws {
        try Task.checkCancellation(); try checkAccess()
        guard !isClosed else { throw CancellationError() }
    }

    private func cipherURL(_ id: CipherID) -> URL { environment.apiURL.appendingPathComponent("ciphers").appendingPathComponent(
        id.rawValue
    ) }
    private func trustedAttachmentURL(_ value: String) throws -> URL {
        guard !value.hasPrefix("//"), let url = resolvedAttachmentURL(value),
              url.user == nil, url.password == nil, url.scheme?.lowercased() == environment.apiURL.scheme?.lowercased(),
              url.host?.lowercased() == environment.apiURL.host?.lowercased(),
              (url.port ?? (url.scheme == "https" ? 443 : 80)) == (
                  environment.apiURL.port ?? (environment.apiURL.scheme == "https" ? 443 : 80)
              )
        else { throw VaultRepositoryError.unsupportedOperation }
        return url
    }

    /// Vaultwarden returns the v2 upload endpoint as a root-relative `/ciphers/...` path even
    /// though that route is mounted beneath `/api`. Preserve reverse-proxy prefixes by resolving
    /// this documented path against the configured API base, rather than the origin root.
    private func resolvedAttachmentURL(_ value: String) -> URL? {
        guard let returned = URLComponents(string: value) else { return nil }
        guard returned.scheme == nil, returned.host == nil, returned.path.hasPrefix("/ciphers/") else {
            return URL(string: value, relativeTo: environment.apiURL)?.absoluteURL
        }
        guard !returned.path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }),
              var base = URLComponents(url: environment.apiURL, resolvingAgainstBaseURL: false) else { return nil }
        let apiPath = base.percentEncodedPath.hasSuffix("/") ? String(base.percentEncodedPath.dropLast()) : base.percentEncodedPath
        base.percentEncodedPath = apiPath + returned.percentEncodedPath
        base.percentEncodedQuery = returned.percentEncodedQuery
        base.percentEncodedFragment = returned.percentEncodedFragment
        return base.url
    }

    private func send(
        url: URL,
        method: HTTPRequest.Method,
        body: Foundation.Data? = nil,
        contentType: String = "application/json",
        maximumResponseBytes: Int = HTTPResponseBodyLimit.standard
    ) async throws -> HTTPResponse {
        var request = try await authorizedRequest(url: url, method: method)
        request.body = body
        request.maximumResponseBytes = maximumResponseBytes
        if body != nil { request.headers["Content-Type"] = contentType }
        let response = try await http.send(request)
        try check()
        guard response.isSuccess else { throw HTTPStatusError(response: response) }
        return response
    }

    private func authorizedRequest(url: URL, method: HTTPRequest.Method, headers: [String: String] = [:]) async throws -> HTTPRequest {
        try check()
        let token: String
        if let requireAccessToken { token = try await requireAccessToken() }
        else {
            guard let available = await accessToken() else { throw VaultRepositoryError.sessionClosed }
            token = available
        }
        try check()
        var headers = headers
        headers["Authorization"] = "Bearer \(token)"
        return HTTPRequest(url: url, method: method, headers: headers, redirectPolicy: .reject)
    }

    public func revoke() {
        isClosed = true
        ciphers.removeAll(); encrypted.removeAll(); folders.removeAll(); collections.removeAll()
        organizationKeys.removeAll(); organizationNames.removeAll(); warnings.removeAll()
    }
}
