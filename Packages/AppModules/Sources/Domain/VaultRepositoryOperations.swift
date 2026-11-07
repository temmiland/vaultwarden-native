import Foundation

public enum VaultProjectionStatus: Sendable, Equatable {
    case current(revision: UInt64)
    case stale
    case unavailable
}

public enum VaultRepositoryError: Error, Sendable, Equatable {
    case unsupportedOperation
    case sessionClosed
    case staleItem
    case missingItem
    case readOnly
    /// The server acknowledged the write. Do not offer another create/upload as a retry.
    case committedButRefreshFailed
    case temporaryCleanupFailed
    case committedButCleanupFailed
}

/// Defaults keep snapshot-only fixtures/adapters possible. Live composition supplies every
/// existing item/attachment operation; unsupported operations never masquerade as success.
public extension VaultRepository {
    func preparePasskeyRegistrationRecoveryReview() async throws -> PasskeyRegistrationRecoveryReview { throw PasskeyRegistrationReviewError.unavailable }
    func abandonPasskeyRegistrationRecovery(_: PasskeyRegistrationRecoveryReview) async throws { throw PasskeyRegistrationReviewError.unavailable }
    func makeDraft(for _: CipherID) async throws -> VaultItemDraft { throw VaultRepositoryError.unsupportedOperation }
    func save(_: VaultItemDraft) async throws -> CipherID { throw VaultRepositoryError.unsupportedOperation }
    func delete(_: VaultItemContext) async throws { throw VaultRepositoryError.unsupportedOperation }
    func oneTimeCode(for _: VaultItemContext) async throws -> VaultOneTimeCode { throw VaultRepositoryError.unsupportedOperation }
    func passkeys(for _: VaultItemContext) async throws -> [VaultPasskeySummary] { throw VaultRepositoryError.unsupportedOperation }
    func uploadAttachment(to _: VaultItemContext, file _: any ImportedFile) async throws { throw VaultRepositoryError.unsupportedOperation }
    func downloadAttachment(_: VaultAttachmentReference, context _: VaultItemContext) async throws -> URL { throw VaultRepositoryError.unsupportedOperation }
    func deleteAttachment(_: VaultAttachmentReference, context _: VaultItemContext) async throws { throw VaultRepositoryError.unsupportedOperation }
}
