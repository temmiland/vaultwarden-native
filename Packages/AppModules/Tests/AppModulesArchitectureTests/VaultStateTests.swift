import BitwardenSdk
import BitwardenSDKAdapter
import Domain
import Foundation
import Testing
@testable import VaultPresentation

@Suite
struct VaultStateTests {
    @Test
    func passkeyRecoveryWarningDoesNotInventUnavailableItemsOrRemoveVaultRows() {
        var state = VaultState()
        state.snapshot = VaultSnapshot(
            revision: 1,
            items: [],
            lastSuccessfulSync: nil,
            isStale: false,
            warnings: [.passkeyRegistrationRecoveryPending, .unavailableItems(count: 2)]
        )
        #expect(state.unavailableItemCount == 2)
        #expect(state.loadWarnings.contains(.passkeyRegistrationRecoveryPending))
    }

    @Test
    func collectionFilteringAndSearchUseTheDomainSnapshot() {
        var state = VaultState()
        state.snapshot = vaultSnapshot(ciphers: [
            .fixture(id: "one", collectionIds: ["collection-1"], name: "Primary"),
            .fixture(id: "two", collectionIds: ["collection-2"], name: "Other"),
            .fixture(id: "three", name: "Unassigned"),
        ])
        state.filter = .collection(CollectionID(rawValue: "collection-1"))
        #expect(state.visibleItems.map(\.id.rawValue) == ["one"])
        state.searchQuery = "no-match"
        #expect(state.visibleItems.isEmpty)
    }

    @Test
    func deletedAndArchivedCiphersNeverEnterTheActiveSnapshot() {
        var state = VaultState()
        state.snapshot = vaultSnapshot(ciphers: [.fixture(id: "active"),
                                                 .fixture(id: "deleted", deletedDate: Date()),
                                                 .fixture(id: "archived", archivedDate: Date())])
        #expect(state.visibleItems.map(\.id.rawValue) == ["active"])
    }

    @Test
    func multipleCollectionMembershipAndOrganizationIdentityAreRetained() {
        var state = VaultState()
        state.snapshot = vaultSnapshot(
            ciphers: [.fixture(collectionIds: ["first", "second"])],
            collections: [.fixture(id: "first"), .fixture(id: "second")]
        )
        #expect(state.collectionSummaries.map(\.id.rawValue) == ["first", "second"])
        #expect(state.collectionSummaries.allSatisfy { $0.organizationID == OrganizationID(rawValue: "org-1") })
        state.filter = .collection(CollectionID(rawValue: "second"))
        #expect(state.visibleItems.count == 1)
    }

    @Test
    func permissionAndSelectionChangesClearRetainedCredentialsAndEditor() throws {
        var state = VaultState()
        state.snapshot = vaultSnapshot(ciphers: [.fixture()])
        state.selectedItemID = CipherID(rawValue: "cipher-1")
        let context = try #require(state.selectedItem?.context)
        state.sheet = .edit(try SDKVaultItemDraftMapper.makeDraft(from: .fixture()))
        state.oneTimeCode = VaultOneTimeCode(context: context, code: "123456", period: 30)
        state.passkeyContext = context
        state.passkeySummaries = [.init(id: "passkey", relyingPartyName: "Example", userName: "user")]
        state.snapshot = vaultSnapshot(ciphers: [.fixture(viewPassword: false)], revision: 2)
        state.reconcileSelection()
        #expect(state.sheet == nil)
        #expect(state.totp(for: context) == nil)
        #expect(state.passkeys(for: context).isEmpty)
        #expect(state.errorMessage != nil)
        state.searchQuery = "absent"
        state.reconcileSelection()
        #expect(state.selectedItemID == nil)
        #expect(state.selectedItem == nil)
    }
}

/// Permission assertions now exercise the SDK adapter, not a removed SDK-shaped screen API.
@Suite
struct VaultPermissionMappingTests {
    private func permissions(_ cipher: CipherView, _ collections: [CollectionView] = []) -> VaultItemPermissions {
        SDKVaultPresentationMapper.permissions(
            for: cipher,
            collections: SDKVaultPresentationMapper.collections(from: collections)
        )
    }

    @Test
    func cipherAndCollectionEditAndSecretFlagsRemainIndependent() {
        #expect(permissions(.fixture()).canEdit)
        #expect(!permissions(.fixture(edit: false)).canEdit)
        #expect(!permissions(.fixture(viewPassword: false)).canEdit)
        #expect(!permissions(.fixture(viewPassword: false)).canViewSecrets)
        let cipher = CipherView.fixture(collectionIds: ["collection-1"])
        #expect(permissions(cipher, [.fixture()]).canEdit)
        #expect(!permissions(cipher, [.fixture(readOnly: true)]).canEdit)
        #expect(permissions(cipher, [.fixture(readOnly: true)]).canViewSecrets)
        #expect(!permissions(cipher, [.fixture(hidePasswords: true)]).canEdit)
        #expect(!permissions(cipher, [.fixture(hidePasswords: true)]).canViewSecrets)
        #expect(!permissions(cipher).canViewSecrets)
    }

    @Test(arguments: [CipherType.bankAccount, .driversLicense, .passport])
    func unsupportedTypesCannotReachALossyEditor(_ type: CipherType) {
        #expect(!permissions(.fixture(type: type)).canEdit)
        #expect(permissions(.fixture(type: type)).editRestriction != nil)
    }

    @Test
    func deletePermissionAndAttachmentDecryptionFailuresAreRespected() {
        let denied = permissions(.fixture(permissions: .init(delete: false, restore: false)))
        #expect(denied.canEdit)
        #expect(!denied.canDelete)
        #expect(permissions(.fixture()).canDelete)
        #expect(!permissions(.fixture(edit: false)).canDelete)
        let broken = permissions(.fixture(attachmentDecryptionFailures: ["attachment-1"]))
        #expect(!broken.canEdit)
        #expect(!broken.canDelete)
        #expect(broken.editRestriction != nil)
    }

    @Test
    func repromptDoesNotMasqueradeAsDeviceAuthentication() {
        let protected = permissions(.fixture(reprompt: .password))
        #expect(!protected.canViewSecrets)
        #expect(!protected.canEdit)
        #expect(!protected.canDelete)
        #expect(protected.editRestriction == .repromptRequired)
    }
}
