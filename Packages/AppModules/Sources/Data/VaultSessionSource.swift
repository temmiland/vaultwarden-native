import AutoFillContract
import Domain
import Foundation

/// Crypto backing and encrypted projection input for one accepted revision. No SDK value crosses
/// this port. UI consumes only the snapshot; cache bytes and identity inputs stay in Data.
public struct VaultSourceOutput: Sendable {
    public let snapshot: VaultSnapshot
    public let encryptedLoginRecords: [EncryptedLoginRecord]
    public let encryptedOrganizationKeys: [String: String]
    public let identitySources: [VaultLoginIdentitySource]
    public init(
        snapshot: VaultSnapshot,
        encryptedLoginRecords: [EncryptedLoginRecord],
        encryptedOrganizationKeys: [String: String],
        identitySources: [VaultLoginIdentitySource]
    ) {
        self.snapshot = snapshot; self.encryptedLoginRecords = encryptedLoginRecords
        self.encryptedOrganizationKeys = encryptedOrganizationKeys; self.identitySources = identitySources
    }
}

public protocol VaultSessionSource: VaultSnapshotSource {
    func fetchOutput() async throws -> VaultSourceOutput
    func currentOutput() async throws -> VaultSourceOutput
    func makeDraft(for id: CipherID) async throws -> VaultItemDraft
    func save(_ draft: VaultItemDraft) async throws -> CipherID
    func delete(_ context: VaultItemContext) async throws
    func oneTimeCode(for context: VaultItemContext) async throws -> VaultOneTimeCode
    func passkeys(for context: VaultItemContext) async throws -> [VaultPasskeySummary]
    func uploadAttachment(to context: VaultItemContext, file: any ImportedFile, encryptedURL: URL) async throws
    func downloadAttachment(
        _ reference: VaultAttachmentReference,
        context: VaultItemContext,
        encryptedURL: URL,
        decryptedURL: URL
    ) async throws
    func deleteAttachment(_ reference: VaultAttachmentReference, context: VaultItemContext) async throws
    func revoke() async
}

public extension VaultSessionSource {
    func fetchVaultSnapshot() async throws -> VaultSnapshot { try await fetchOutput().snapshot }
}
