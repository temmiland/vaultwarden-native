import BitwardenSDKAdapter
import Domain
import Foundation

/// Data's SDK-free source port is implemented here; the SDK target never depends back on Data.
public struct SDKVaultSourceAdapter: VaultSessionSource {
    private let backing: SDKVaultSessionSource
    public init(backing: SDKVaultSessionSource) { self.backing = backing }
    private func output(_ value: SDKVaultOutput) -> VaultSourceOutput {
        VaultSourceOutput(
            snapshot: value.snapshot,
            encryptedLoginRecords: value.encryptedLoginRecords,
            encryptedOrganizationKeys: value.encryptedOrganizationKeys,
            identitySources: value.identitySources
        )
    }

    public func fetchOutput() async throws -> VaultSourceOutput { output(try await backing.fetchOutput()) }
    public func currentOutput() async throws -> VaultSourceOutput { output(try await backing.currentOutput()) }
    public func makeDraft(for id: CipherID) async throws -> VaultItemDraft { try await backing.makeDraft(for: id) }
    public func save(_ draft: VaultItemDraft) async throws -> CipherID { try await backing.save(draft) }
    public func delete(_ context: VaultItemContext) async throws { try await backing.delete(context) }
    public func oneTimeCode(for context: VaultItemContext) async throws -> VaultOneTimeCode { try await backing.oneTimeCode(
        for: context
    ) }
    public func passkeys(for context: VaultItemContext) async throws -> [VaultPasskeySummary] { try await backing.passkeys(
        for: context
    ) }
    public func uploadAttachment(to context: VaultItemContext, file: any ImportedFile, encryptedURL: URL) async throws {
        try await backing.uploadAttachment(to: context, file: file, encryptedURL: encryptedURL)
    }

    public func downloadAttachment(
        _ reference: VaultAttachmentReference,
        context: VaultItemContext,
        encryptedURL: URL,
        decryptedURL: URL
    ) async throws {
        try await backing.downloadAttachment(
            reference,
            context: context,
            encryptedURL: encryptedURL,
            decryptedURL: decryptedURL
        )
    }

    public func deleteAttachment(_ reference: VaultAttachmentReference, context: VaultItemContext) async throws {
        try await backing.deleteAttachment(reference, context: context)
    }

    public func revoke() async { await backing.revoke() }
}
