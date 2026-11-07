import Domain

public enum VaultAction {
    case searchQueryChanged(String)
    case filterSelected(VaultFilter)
    case itemSelected(CipherID?)

    case addItemTapped(VaultItemKind)
    case editItemTapped(CipherID)
    case sheetDismissed
    case draftChanged(VaultItemDraft)

    case deleteItemTapped(CipherID)
    case deleteCancelled

    case deleteAttachmentTapped(VaultAttachmentReference)
    case deleteAttachmentCancelled
    case previewDismissed

    case generatorPresentedChanged(Bool)
    case generatorOptionsChanged(PasswordGeneratorOptions)

    case errorDismissed
    case passkeyRecoveryReviewDismissed
    case logoutTapped
}
