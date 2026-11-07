import Domain

public enum VaultEffect {
    case loadVault
    case reviewPasskeyRegistrationRecovery
    case abandonPasskeyRegistrationRecovery(PasskeyRegistrationRecoveryReview)
    case saveDraft
    case confirmDelete
    case regeneratePassword
    case refreshTotp(VaultItemContext)
    case loadPasskeys(VaultItemContext)

    case pickAttachment(cipherID: CipherID)
    case downloadAttachment(VaultAttachmentReference)
    case confirmDeleteAttachment
}
