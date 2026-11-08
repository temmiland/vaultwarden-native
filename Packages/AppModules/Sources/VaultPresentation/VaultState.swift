import Domain
import Foundation

public struct VaultState {
    public internal(set) var isLoading = true
    public internal(set) var errorMessage: String?
    public internal(set) var passkeyRecoveryReview: PasskeyRegistrationRecoveryReview?
    public internal(set) var isPasskeyRecoveryBusy = false
    public internal(set) var snapshot = VaultSnapshot(revision: 0, items: [], lastSuccessfulSync: nil, isStale: false)
    public var loadWarnings: [VaultLoadWarning] { snapshot.warnings }

    public var needsSyncAttention: Bool {
        if snapshot.isStale { return true }
        guard snapshot.lastSuccessfulSync != nil else { return false }
        switch snapshot.projectionStatus {
        case let .current(revision), let .suggestionsDisabled(revision):
            return revision != snapshot.revision
        case .stale, .unavailable:
            return true
        }
    }

    public var unavailableItemCount: Int {
        loadWarnings.reduce(0) { total, warning in
            switch warning {
            case let .unavailableItems(count): total + max(0, count)
            case .passkeyRegistrationRecoveryPending: total
            }
        }
    }

    public internal(set) var searchQuery = ""
    public internal(set) var filter: VaultFilter = .allItems
    public internal(set) var selectedItemID: CipherID?

    public internal(set) var sheet: VaultSheet?
    public internal(set) var isSavingDraft = false
    public internal(set) var pendingDeleteID: CipherID?

    public internal(set) var isGeneratorPresented = false
    public internal(set) var generatorOptions = PasswordGeneratorOptions()
    public internal(set) var generatedPassword = ""
    public internal(set) var generatorErrorMessage: String?

    public internal(set) var oneTimeCode: VaultOneTimeCode?
    public internal(set) var passkeyContext: VaultItemContext?
    public internal(set) var passkeySummaries: [VaultPasskeySummary] = []

    public internal(set) var pendingAttachmentDelete: VaultAttachmentReference?
    public internal(set) var isAttachmentBusy = false
    public internal(set) var previewURL: URL?
    public internal(set) var previewContext: VaultItemContext?

    public var folderSummaries: [VaultFolderSummary] {
        snapshot.folders
    }

    public var collectionSummaries: [VaultCollectionSummary] {
        snapshot.collections
    }

    public var selectedItem: VaultItemDetail? {
        selectedItemID.flatMap { snapshot.details[$0] }
    }

    public var visibleItems: [VaultItemSummary] {
        snapshot.items
            .filter { filter.matches($0) && $0.matches(searchQuery: searchQuery) }
            .sorted {
                let order = $0.name.localizedCaseInsensitiveCompare($1.name)
                return order == .orderedSame ? $0.id.rawValue < $1.id.rawValue : order == .orderedAscending
            }
    }

    public func organizationName(for id: OrganizationID) -> String? { snapshot.organizationNames[id] }

    public func passkeys(for context: VaultItemContext) -> [VaultPasskeySummary] {
        guard let item = selectedItem, item.context == context, item.permissions.canViewSecrets,
              passkeyContext == context,
              case let .login(login) = item.payload, login.hasPasskeys
        else { return [] }
        return passkeySummaries
    }

    public func totp(for context: VaultItemContext) -> VaultOneTimeCode? {
        guard let item = selectedItem, item.context == context, item.permissions.canViewSecrets,
              case let .login(login) = item.payload, login.hasTotp, oneTimeCode?.context == context
        else { return nil }
        return oneTimeCode
    }

    mutating func clearDetailSupplements() {
        oneTimeCode = nil
        passkeyContext = nil
        passkeySummaries = []
    }

    /// An editor contains plain secrets too. Revoke it when the current item no longer permits
    /// viewing them, but keep ordinary revision conflicts/read-only edits available for recovery.
    mutating func reconcileEditingAccess() {
        guard let id = sheet?.draft.editingID else { return }
        guard let detail = snapshot.details[id], detail.permissions.canViewSecrets else {
            sheet = nil
            errorMessage = "The editor was closed because this item's secrets are no longer accessible. Unsaved changes were discarded."
            return
        }
    }

    /// Selection may disappear after a filter, search, sync or mutation. Outgoing detail tasks
    /// must not keep their credentials in state or leave a confirmation targeting another item.
    mutating func reconcileSelection() {
        reconcileEditingAccess()
        if let selectedItemID, !visibleItems.contains(where: { $0.id == selectedItemID }) {
            self.selectedItemID = nil
        }
        let detail = selectedItem
        let hasTotp: Bool
        let hasPasskeys: Bool
        if case let .login(login) = detail?.payload {
            hasTotp = login.hasTotp
            hasPasskeys = login.hasPasskeys
        } else {
            hasTotp = false
            hasPasskeys = false
        }
        if oneTimeCode?.context != detail?.context || !hasTotp {
            oneTimeCode = nil
        }
        if passkeyContext != detail?.context || !hasPasskeys {
            passkeyContext = nil
            passkeySummaries = []
        }
        if pendingAttachmentDelete?.cipherID != selectedItemID { pendingAttachmentDelete = nil }
    }
}

public enum VaultSheet: Identifiable {
    case edit(VaultItemDraft)

    public var id: String {
        switch self {
        case let .edit(draft): draft.id
        }
    }

    public var draft: VaultItemDraft {
        switch self {
        case let .edit(draft): draft
        }
    }
}
