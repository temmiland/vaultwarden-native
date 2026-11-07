import BitwardenSdk
import Foundation

/// Adapter-internal SDK-shaped crypto seam. Domain and presentation ports never expose these
/// values. Thin seam around `BitwardenSdk.Client.vault()` so adapter tests can substitute a fake
/// instead of initializing a real FFI-backed crypto session.
public protocol VaultCryptoServicing: Sendable {
    /// Must be called once per sync, before decrypting any org-owned cipher/collection - without
    /// it, `decrypt(cipher:)` for an org item fails per-field with "Missing Key for Id:
    /// Organization(...)" (logged by the Rust core, not thrown), leaving that item's fields empty.
    func initializeOrganizationCrypto(organizationKeys: [String: String]) async throws
    func decryptCiphers(_ ciphers: [Cipher]) async throws -> [CipherView]
    func decryptCipher(_ cipher: Cipher) async throws -> CipherView
    func encryptCipher(_ cipherView: CipherView) async throws -> EncryptionContext
    func decryptFolders(_ folders: [Folder]) throws -> [FolderView]
    func decryptCollections(_ collections: [Collection]) throws -> [CollectionView]
    func generateTotp(key: String, at date: Date?) throws -> TotpResponse

    /// A cipher's `login.fido2Credentials` stays encrypted even after `decrypt(cipher:)` - only
    /// this call actually decrypts the passkey's display fields (rpId, username, ...). The
    /// private key material (`keyValue`) stays wrapped regardless; it's only used internally by
    /// the SDK's own Fido2 authenticator flow, never surfaced here.
    func decryptFido2Credentials(cipherView: CipherView) throws -> [Fido2CredentialView]

    /// Passkey fields in the shape the *system* wants: raw `credentialId`/`userHandle` bytes,
    /// rather than `decryptFido2Credentials`' Bitwarden-encoded strings (a bare UUID, or base64url
    /// behind a `b64.` prefix - see `string_to_guid_bytes` in `bitwarden-fido`). Use this whenever
    /// the bytes leave the app, since misreading that encoding fails silently rather than loudly.
    func decryptFido2AutofillCredentials(cipherView: CipherView) throws -> [Fido2CredentialAutofillView]

    /// Encrypts a file on disk (`decryptedFilePath`) into a new attachment (`encryptedFilePath`),
    /// generating/wrapping the attachment's own key under `cipher`'s key. `cipher` must be the
    /// *encrypted* domain object (e.g. from `encryptCipher(_:)`), not a `CipherView` - the SDK needs
    /// the still-wrapped cipher key to wrap the new attachment key against it.
    func encryptAttachmentFile(
        cipher: Cipher,
        attachment: AttachmentView,
        decryptedFilePath: String,
        encryptedFilePath: String
    ) throws -> Attachment

    /// Decrypts an already-downloaded encrypted attachment file (`encryptedFilePath`) to plaintext
    /// (`decryptedFilePath`). `attachment` should be the decrypted `AttachmentView` for this
    /// attachment (its `key` field stays encrypted even after cipher decryption).
    func decryptAttachmentFile(
        cipher: Cipher,
        attachment: AttachmentView,
        encryptedFilePath: String,
        decryptedFilePath: String
    ) throws
}

/// Live implementation backed by the real vendored crypto core. Constructed with the `Client`
/// owned by the session runtime — this package never rolls its own crypto.
public struct SDKVaultCryptoService: VaultCryptoServicing, Sendable {
    private let sessionClient: SDKSessionClient

    public init(client: Client) {
        sessionClient = SDKSessionClient(client: client)
    }

    public init(sessionClient: SDKSessionClient) { self.sessionClient = sessionClient }

    public func initializeOrganizationCrypto(organizationKeys: [String: String]) async throws {
        try await sessionClient.withClient { client in
            guard !organizationKeys.isEmpty else { return }
            try await client.crypto().initializeOrgCrypto(req: InitOrgCryptoRequest(organizationKeys: organizationKeys))
        }
    }

    public func decryptCiphers(_ ciphers: [Cipher]) async throws -> [CipherView] {
        var views: [CipherView] = []
        views.reserveCapacity(ciphers.count)
        for cipher in ciphers {
            try Task.checkCancellation()
            do {
                views.append(try await decryptCipher(cipher))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // The sync loader compares requested/returned ids and publishes a privacy-safe
                // unavailable-item count. Never treat this batch as proof of a complete vault.
                continue
            }
        }
        try sessionClient.checkAccess()
        return views
    }

    public func decryptCipher(_ cipher: Cipher) async throws -> CipherView {
        let view = try await sessionClient.withClient { try await $0.vault().ciphers().decrypt(cipher: cipher) }
        try SDKDecryptionIntegrity.validate(cipher, decrypted: view)
        return view
    }

    public func encryptCipher(_ cipherView: CipherView) async throws -> EncryptionContext {
        try await sessionClient.withClient { try await $0.vault().ciphers().encrypt(cipherView: cipherView) }
    }

    public func decryptFolders(_ folders: [Folder]) throws -> [FolderView] {
        try sessionClient.withClient { try $0.vault().folders().decryptList(folders: folders) }
    }

    public func decryptCollections(_ collections: [Collection]) throws -> [CollectionView] {
        try sessionClient.withClient { try $0.vault().collections().decryptList(collections: collections) }
    }

    public func generateTotp(key: String, at date: Date?) throws -> TotpResponse {
        try sessionClient.withClient { try $0.vault().generateTotp(key: key, time: date) }
    }

    public func decryptFido2AutofillCredentials(cipherView: CipherView) throws -> [Fido2CredentialAutofillView] {
        try sessionClient.withClient { try $0.platform().fido2().decryptFido2AutofillCredentials(cipherView: cipherView) }
    }

    public func decryptFido2Credentials(cipherView: CipherView) throws -> [Fido2CredentialView] {
        try sessionClient.withClient { try $0.vault().ciphers().decryptFido2Credentials(cipherView: cipherView) }
    }

    public func encryptAttachmentFile(
        cipher: Cipher,
        attachment: AttachmentView,
        decryptedFilePath: String,
        encryptedFilePath: String
    ) throws -> Attachment {
        try sessionClient.withClient {
            try $0.vault().attachments().encryptFile(
                cipher: cipher, attachment: attachment,
                decryptedFilePath: decryptedFilePath, encryptedFilePath: encryptedFilePath
            )
        }
    }

    public func decryptAttachmentFile(
        cipher: Cipher,
        attachment: AttachmentView,
        encryptedFilePath: String,
        decryptedFilePath: String
    ) throws {
        try sessionClient.withClient {
            try $0.vault().attachments().decryptFile(
                cipher: cipher, attachment: attachment,
                encryptedFilePath: encryptedFilePath, decryptedFilePath: decryptedFilePath
            )
        }
    }
}
