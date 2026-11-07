import BitwardenSdk
import BitwardenSDKAdapter
import Domain
import Foundation
import Testing

/// Pure value-boundary fixtures. These do not create an FFI client or contact a server.
@Suite
struct VaultItemDraftMapperTests {
    private let revision = Date(timeIntervalSince1970: 100)

    @Test(arguments: [CipherType.login, .secureNote, .card, .identity, .sshKey])
    func unmodifiedFormPreservesAllExistingValues(_ type: CipherType) throws {
        let original = fixture(type: type)
        let draft = try SDKVaultItemDraftMapper.makeDraft(from: original)
        let rebuilt = try SDKVaultItemDraftMapper.applying(draft, to: original, now: original.revisionDate)

        #expect(draft.editingID == CipherID(rawValue: "cipher-1"))
        #expect(draft.baseRevision == revision)
        #expect(rebuilt == original)
    }

    @Test
    func visibleIdentityEditDoesNotRebuildHiddenIdentityFields() throws {
        let original = fixture(type: .identity)
        var draft = try SDKVaultItemDraftMapper.makeDraft(from: original)
        draft.firstName = "changed"
        let rebuilt = try SDKVaultItemDraftMapper.applying(draft, to: original)

        #expect(rebuilt.identity?.firstName == "changed")
        #expect(rebuilt.identity?.title == original.identity?.title)
        #expect(rebuilt.identity?.middleName == original.identity?.middleName)
        #expect(rebuilt.identity?.address1 == original.identity?.address1)
        #expect(rebuilt.identity?.company == original.identity?.company)
        #expect(rebuilt.identity?.ssn == original.identity?.ssn)
        #expect(rebuilt.identity?.passportNumber == original.identity?.passportNumber)
        #expect(rebuilt.identity?.licenseNumber == original.identity?.licenseNumber)
        #expect(rebuilt.attachments == original.attachments)
        #expect(rebuilt.fields == original.fields)
        #expect(rebuilt.passwordHistory == original.passwordHistory)
        #expect(rebuilt.key == original.key)
        #expect(rebuilt.collectionIds == original.collectionIds)
    }

    @Test
    func clearingAndAppendingURIRowsPreservesMetadataAtSourcePositions() throws {
        let original = fixture(type: .login)
        var draft = try SDKVaultItemDraftMapper.makeDraft(from: original)
        draft.uris[2] = "" // explicitly clear the populated URI, not the nil/empty rows
        draft.uris.append("https://new.example.com")
        let rebuilt = try SDKVaultItemDraftMapper.applying(draft, to: original)
        let uris = try #require(rebuilt.login?.uris)

        #expect(uris.count == 3)
        #expect(uris[0] == original.login?.uris?[0])
        #expect(uris[1] == original.login?.uris?[1])
        #expect(uris[2].uri == "https://new.example.com")
        #expect(uris[2].match == nil)
        #expect(uris[2].uriChecksum == nil)
    }

    @Test
    func anEditRequiresTheSameItemKindIDAndCurrentRevision() throws {
        let original = fixture(type: .login)
        let draft = try SDKVaultItemDraftMapper.makeDraft(from: original)
        #expect(throws: VaultItemDraftError.missingItem) {
            _ = try SDKVaultItemDraftMapper.applying(draft, to: nil)
        }
        #expect(throws: VaultItemDraftError.draftMismatch) {
            _ = try SDKVaultItemDraftMapper.applying(draft, to: fixture(type: .login, id: "other-id"))
        }
        #expect(throws: VaultItemDraftError.draftMismatch) {
            _ = try SDKVaultItemDraftMapper.applying(draft, to: fixture(type: .card))
        }
        #expect(throws: VaultItemDraftError.staleDraft) {
            _ = try SDKVaultItemDraftMapper.applying(
                draft, to: fixture(type: .login, revision: Date(timeIntervalSince1970: 101))
            )
        }
    }

    @Test
    func revokedPermissionsOrInactiveItemsCannotBeWrittenFromAnOldDraft() throws {
        let draft = try SDKVaultItemDraftMapper.makeDraft(from: fixture(type: .login))
        let invalidBases = [
            fixture(type: .login, edit: false),
            fixture(type: .login, viewPassword: false),
            fixture(type: .login, deleted: true),
            fixture(type: .login, archived: true),
            fixture(type: .login, attachmentFailure: true),
            fixture(type: .login, reprompt: .password),
        ]
        for base in invalidBases {
            #expect(throws: VaultItemDraftError.readOnly) {
                _ = try SDKVaultItemDraftMapper.makeDraft(from: base)
            }
            #expect(throws: VaultItemDraftError.readOnly) {
                _ = try SDKVaultItemDraftMapper.applying(draft, to: base)
            }
        }
    }

    @Test(arguments: [VaultItemKind.bankAccount, .driversLicense, .passport, .unknown])
    func unsupportedKindsAreNeverNewEditableItems(_ kind: VaultItemKind) {
        #expect(!kind.supportsEditing)
        #expect(throws: VaultItemDraftError.unsupportedItemKind) {
            _ = try SDKVaultItemDraftMapper.applying(VaultItemDraft(kind: kind), to: nil)
        }
    }

    @Test
    func aNewDraftCannotReplaceAnExistingItemOrCarryAnEditRevision() {
        let newDraft = VaultItemDraft(kind: .login)
        #expect(throws: VaultItemDraftError.draftMismatch) {
            _ = try SDKVaultItemDraftMapper.applying(newDraft, to: fixture(type: .login))
        }
        let invalidDraft = VaultItemDraft(editingID: nil, kind: .login, baseRevision: revision)
        #expect(throws: VaultItemDraftError.draftMismatch) {
            _ = try SDKVaultItemDraftMapper.applying(invalidDraft, to: nil)
        }
        #expect(throws: VaultItemDraftError.missingItem) {
            _ = try SDKVaultItemDraftMapper.makeDraft(from: fixture(type: .login, id: nil))
        }
    }

    @Test
    func normalAndDebugDescriptionsDoNotPrintDraftSecrets() {
        var draft = VaultItemDraft(kind: .login)
        draft.name = "private-item-name"
        draft.password = "fake-test-secret"
        draft.sshPrivateKey = "fake-private-key"

        #expect(String(describing: draft) == "VaultItemDraft(<redacted>)")
        #expect(String(reflecting: draft) == "VaultItemDraft(<redacted>)")
    }

    @Test(arguments: [CipherType.login, .secureNote, .card, .identity, .sshKey])
    func presentationUsesOwnIDsAndRedactedDetailValues(_ type: CipherType) throws {
        let original = fixture(type: type, reprompt: .none, notes: "fake-private-note")
        let summary = try #require(
            SDKVaultPresentationMapper.summary(from: original, collections: presentationCollections)
        )
        let detail = try #require(
            SDKVaultPresentationMapper.detail(
                from: original,
                collections: presentationCollections,
                organizationName: "Test Org"
            )
        )

        #expect(summary.id == CipherID(rawValue: "cipher-1"))
        #expect(summary.folderID == FolderID(rawValue: "folder-1"))
        #expect(summary.collectionIDs == [CollectionID(rawValue: "collection-1")])
        #expect(detail.context.revision == revision)
        #expect(detail.organizationName == "Test Org")
        #expect(detail.permissions.canEdit)
        #expect(!detail.permissions.canDelete)
        #expect(detail.permissions.canViewSecrets)
        #expect(detail.attachments.first?.reference == VaultAttachmentReference(
            cipherID: summary.id, attachmentID: AttachmentID(rawValue: "attachment-1")
        ))
        #expect(String(reflecting: summary) == "VaultItemSummary(<redacted>)")
        #expect(String(reflecting: detail) == "VaultItemDetail(<redacted>)")
        #expect(String(reflecting: detail.payload) == "VaultItemPayload(<redacted>)")
        let storedFields = Set(Mirror(reflecting: detail).children.compactMap(\.label))
        #expect(storedFields.isDisjoint(with: ["key", "passwordHistory", "fields", "localData"]))
    }

    @Test(arguments: [CipherType.login, .secureNote, .card, .sshKey])
    func hiddenSecretsNeverReachTheDetailProjection(_ type: CipherType) throws {
        let original = fixture(type: type, viewPassword: false, reprompt: .none, notes: "fake-private-note")
        let detail = try #require(
            SDKVaultPresentationMapper.detail(from: original, collections: presentationCollections)
        )
        #expect(detail.notes == nil)
        #expect(detail.permissions.editRestriction == .secretsHidden)
        #expect(!detail.permissions.canViewSecrets)
        #expect(detail.attachments.allSatisfy { !$0.canDownload })
        switch detail.payload {
        case let .login(login):
            #expect(login.password == nil)
            #expect(!login.hasTotp)
            #expect(!Mirror(reflecting: login).children.contains { $0.label == "totpSeed" })
        case let .card(card):
            #expect(card.number == nil)
            #expect(card.securityCode == nil)
        case let .sshKey(key): #expect(key.privateKey == nil)
        case .secureNote: break
        default: Issue.record("Unexpected fixture type")
        }
    }

    @Test(arguments: [CipherType.login, .secureNote, .card, .identity, .sshKey])
    func masterPasswordRepromptIsReadOnlyWithoutAnAuthorizationGrant(_ type: CipherType) throws {
        let original = fixture(type: type, reprompt: .password, notes: "fake-private-note")
        let summary = try #require(
            SDKVaultPresentationMapper.summary(from: original, collections: presentationCollections)
        )
        let detail = try #require(
            SDKVaultPresentationMapper.detail(from: original, collections: presentationCollections)
        )

        #expect(original.reprompt == .password)
        #expect(detail.permissions.editRestriction == .repromptRequired)
        #expect(!detail.permissions.canEdit)
        #expect(!detail.permissions.canDelete)
        #expect(!detail.permissions.canViewSecrets)
        #expect(!summary.isEditable && !summary.canDelete)
        #expect(detail.notes == nil)
        #expect(detail.attachments.allSatisfy { !$0.canDownload })
        #expect(throws: VaultItemDraftError.readOnly) {
            _ = try SDKVaultItemDraftMapper.makeDraft(from: original)
        }
        switch detail.payload {
        case let .login(login):
            #expect(login.password == nil)
            #expect(!login.hasTotp && !login.hasPasskeys)
        case let .card(card):
            #expect(card.number == nil && card.securityCode == nil && card.cardholderName == nil)
            #expect(card.expiration.isEmpty)
        case let .identity(identity):
            #expect(identity.fullName.isEmpty)
            #expect(identity.username == nil && identity.email == nil && identity.phone == nil)
            #expect(summary.subtitle == nil)
        case let .sshKey(key): #expect(key.privateKey == nil && key.publicKey == nil)
        case .secureNote: #expect(summary.subtitle == nil)
        default: Issue.record("Unexpected fixture type")
        }
    }

    @Test
    func oldCachesAndRetainedAutoFillSelectionsCannotAuthorizeProtectedItems() throws {
        let view = fixture(type: .login)
        let current = try JSONDecoder().decode(CipherResponseDTO.self, from: Data("""
        {"id":"cipher-1","type":1,"name":"fake-encrypted-name",
         "revisionDate":"1970-01-01T00:01:40.000Z",
         "login":{"username":"fake-encrypted-user","password":"fake-encrypted-password"}}
        """.utf8))
        #expect(SDKVaultAccessPolicy.isEligibleForAutoFill(view))
        #expect(SDKVaultAccessPolicy.isEligibleForAutoFill(current))
        #expect(SDKVaultAccessPolicy.isCurrentAutoFillItem(view, in: [current]))

        var protected = current
        protected.reprompt = 1
        let serializedOldCache = try JSONEncoder().encode([protected])
        let decodedOldCache = try JSONDecoder().decode([CipherResponseDTO].self, from: serializedOldCache)
        #expect(!SDKVaultAccessPolicy.isCurrentAutoFillItem(view, in: decodedOldCache))
        #expect(!SDKVaultAccessPolicy.allowsUnpromptedSecretAccess(try protected.toSDKCipher()))
        #expect(!SDKVaultAccessPolicy.isEligibleForAutoFill(fixture(type: .login, reprompt: .password)))
        #expect(!SDKVaultAccessPolicy.isCurrentAutoFillItem(view, in: []))
        #expect(!SDKVaultAccessPolicy.isCurrentAutoFillItem(view, in: [current, current]))
        #expect(!SDKVaultAccessPolicy.isCurrentAutoFillItem(
            fixture(type: .login, revision: Date(timeIntervalSince1970: 101)), in: [current]
        ))

        for flag in [-1, 2, 999] {
            protected.reprompt = flag
            #expect(!SDKVaultAccessPolicy.isEligibleForAutoFill(protected))
        }
        var hidden = current
        hidden.viewPassword = false
        #expect(!SDKVaultAccessPolicy.isCurrentAutoFillItem(view, in: [hidden]))
        var deleted = current
        deleted.deletedDate = "1970-01-01T00:01:40.000Z"
        #expect(!SDKVaultAccessPolicy.isCurrentAutoFillItem(view, in: [deleted]))
        #expect(!SDKVaultAccessPolicy.isEligibleForAutoFill(fixture(type: .login, id: nil)))
        #expect(!SDKVaultAccessPolicy.isEligibleForAutoFill(fixture(type: .login, id: "")))
    }

    @Test
    func unknownOrAmbiguousCollectionPermissionsFailClosed() {
        let original = fixture(type: .login, reprompt: .none)
        let missing = SDKVaultPresentationMapper.permissions(for: original, collections: [])
        let duplicate = SDKVaultPresentationMapper.permissions(
            for: original,
            collections: presentationCollections + presentationCollections
        )
        let crossOrganization = SDKVaultPresentationMapper.permissions(for: original, collections: [
            VaultCollectionSummary(
                id: CollectionID(rawValue: "collection-1"),
                organizationID: OrganizationID(rawValue: "other-org"),
                name: "Other",
                isReadOnly: false,
                hidesPasswords: false
            ),
        ])
        for permissions in [missing, duplicate, crossOrganization] {
            #expect(permissions.editRestriction == .unresolvedCollection)
            #expect(!permissions.canEdit)
            #expect(!permissions.canDelete)
            #expect(!permissions.canViewSecrets)
        }
    }

    @Test
    func collectionRestrictionsSeparateEditingFromSecretViewing() {
        let original = fixture(type: .login, reprompt: .none)
        let readOnly = SDKVaultPresentationMapper.permissions(for: original, collections: [
            VaultCollectionSummary(
                id: CollectionID(rawValue: "collection-1"),
                organizationID: OrganizationID(rawValue: "org-1"),
                name: "Read Only",
                isReadOnly: true,
                hidesPasswords: false
            ),
        ])
        #expect(readOnly.editRestriction == .collectionReadOnly)
        #expect(readOnly.canViewSecrets)
        let hidden = SDKVaultPresentationMapper.permissions(for: original, collections: [
            VaultCollectionSummary(
                id: CollectionID(rawValue: "collection-1"),
                organizationID: OrganizationID(rawValue: "org-1"),
                name: "Hidden",
                isReadOnly: false,
                hidesPasswords: true
            ),
        ])
        #expect(hidden.editRestriction == .secretsHidden)
        #expect(!hidden.canViewSecrets)
    }

    @Test
    func duplicateAttachmentsStayVisibleWithoutAnActionableReference() throws {
        let duplicate = AttachmentView(
            id: "same-id",
            url: nil,
            size: nil,
            sizeName: nil,
            fileName: "test.txt",
            key: "fake-key"
        )
        let original = fixture(type: .login, reprompt: .none, attachments: [duplicate, duplicate])
        let detail = try #require(
            SDKVaultPresentationMapper.detail(from: original, collections: presentationCollections)
        )
        #expect(detail.attachments.count == 2)
        #expect(detail.attachments.allSatisfy { $0.reference == nil && !$0.canDownload })
    }

    @Test
    func passkeyProjectionCarriesOnlyDisplayMetadata() {
        let original = Fido2CredentialView(
            credentialId: "fake-id", keyType: "public-key", keyAlgorithm: "ECDSA", keyCurve: "P-256",
            keyValue: "fake-enc-key-value", rpId: "example.com", userHandle: "fake-user-handle",
            userName: "user", counter: "0", rpName: "Example", userDisplayName: "Display User",
            discoverable: "true", creationDate: revision
        )
        let summaries = SDKVaultPresentationMapper.passkeys(from: [original, original])
        #expect(summaries == [VaultPasskeySummary(id: "fake-id", relyingPartyName: "Example", userName: "Display User")])
        #expect(!String(reflecting: summaries).contains("fake-enc-key-value"))
        #expect(!String(reflecting: summaries).contains("fake-user-handle"))
    }

    @Test
    func batchSummaryProjectionHasTheSamePermissionsAndFieldsAsIndividualProjection() {
        let originals = [fixture(type: .login, reprompt: .none), fixture(type: .card, reprompt: .none)]
        #expect(SDKVaultPresentationMapper.summaries(from: originals, collections: presentationCollections)
            == originals.compactMap { SDKVaultPresentationMapper.summary(from: $0, collections: presentationCollections) })
    }

    @Test
    func listSearchUsesOnlyTheExistingNameUsernameAndURIInputs() throws {
        let original = fixture(type: .login, reprompt: .none)
        let login = try #require(
            SDKVaultPresentationMapper.summary(from: original, collections: presentationCollections)
        )
        #expect(login.matches(searchQuery: "EXAMPLE.COM"))
        #expect(login.matches(searchQuery: ""))
        #expect(!login.matches(searchQuery: "fake-test-totp"))
        let ssh = try #require(
            SDKVaultPresentationMapper.summary(
                from: fixture(type: .sshKey, reprompt: .none),
                collections: presentationCollections
            )
        )
        #expect(!ssh.matches(searchQuery: "fake-private"))
    }

    @Test
    func missingOrDuplicateFolderAndCollectionIDsAreNotInteractiveRows() {
        let folders = [
            FolderView(id: nil, name: "Missing", revisionDate: revision),
            FolderView(id: "duplicate", name: "One", revisionDate: revision),
            FolderView(id: "duplicate", name: "Two", revisionDate: revision),
            FolderView(id: "valid", name: "Valid", revisionDate: revision),
        ]
        #expect(
            SDKVaultPresentationMapper.folders(from: folders) == [
                VaultFolderSummary(id: FolderID(rawValue: "valid"), name: "Valid"),
            ]
        )
        let duplicate = CollectionView(
            id: "duplicate", organizationId: "org-1", name: "Duplicate", externalId: nil,
            hidePasswords: false, readOnly: false, manage: false, type: .sharedCollection
        )
        #expect(SDKVaultPresentationMapper.collections(from: [duplicate, duplicate]).isEmpty)
    }

    @Test
    func inactiveAndMissingIDItemsDoNotBecomeSelectablePresentationValues() {
        for original in [
            fixture(type: .login, id: nil),
            fixture(type: .login, deleted: true),
            fixture(type: .login, archived: true),
        ] {
            #expect(SDKVaultPresentationMapper.summary(from: original, collections: presentationCollections) == nil)
            #expect(SDKVaultPresentationMapper.detail(from: original, collections: presentationCollections) == nil)
        }
    }

    private var presentationCollections: [VaultCollectionSummary] {
        [VaultCollectionSummary(
            id: CollectionID(rawValue: "collection-1"),
            organizationID: OrganizationID(rawValue: "org-1"),
            name: "Test Collection",
            isReadOnly: false,
            hidesPasswords: false
        )]
    }

    private func fixture(
        type: CipherType, id: String? = "cipher-1", revision: Date? = nil,
        edit: Bool = true, viewPassword: Bool = true, deleted: Bool = false,
        archived: Bool = false, attachmentFailure: Bool = false, reprompt: CipherRepromptType = .none,
        notes: String? = "", attachments: [AttachmentView]? = nil
    ) -> CipherView {
        let attachment = AttachmentView(
            id: "attachment-1", url: "https://vault.example.com/attachment-1",
            size: "42", sizeName: "42 B", fileName: "test.txt", key: "fake-enc-attachment-key"
        )
        return CipherView(
            id: id, organizationId: "org-1", folderId: "folder-1", collectionIds: ["collection-1"],
            key: "fake-enc-cipher-key", name: "Example", notes: notes, type: type,
            login: type == .login ? LoginView(
                username: nil, password: "", passwordRevisionDate: self.revision,
                uris: [
                    LoginUriView(uri: nil, match: .never, uriChecksum: "nil-row"),
                    LoginUriView(uri: "", match: .exact, uriChecksum: "empty-row"),
                    LoginUriView(uri: "https://example.com", match: .exact, uriChecksum: "uri-row"),
                ],
                totp: "fake-test-totp", autofillOnPageLoad: false,
                fido2Credentials: [Fido2Credential(
                    credentialId: "fake-credential-id", keyType: "public-key", keyAlgorithm: "ECDSA",
                    keyCurve: "P-256", keyValue: "fake-enc-key", rpId: "example.com", userHandle: nil,
                    userName: nil, counter: "0", rpName: nil, userDisplayName: nil,
                    discoverable: "true", creationDate: self.revision
                )]
            ) : nil,
            identity: type == .identity ? IdentityView(
                title: "Dr", firstName: "First", middleName: "Middle", lastName: "Last",
                address1: "Address 1", address2: "Address 2", address3: "Address 3", city: "City",
                state: "State", postalCode: "Postal", country: "Country", company: "Company",
                email: "", phone: nil, ssn: "fake-ssn", username: "test-user",
                passportNumber: "fake-passport", licenseNumber: "fake-license"
            ) : nil,
            card: type == .card ? CardView(
                cardholderName: "", expMonth: nil, expYear: "2030", code: "fake-code", brand: "Visa",
                number: "fake-number"
            ) : nil,
            secureNote: type == .secureNote ? SecureNoteView(type: .generic) : nil,
            sshKey: type == .sshKey ? SshKeyView(
                privateKey: "fake-private", publicKey: "fake-public", fingerprint: "fake-fingerprint"
            ) : nil,
            bankAccount: nil, driversLicense: nil, passport: nil, favorite: true,
            reprompt: reprompt, organizationUseTotp: true, edit: edit,
            permissions: CipherPermissions(delete: false, restore: true), viewPassword: viewPassword,
            localData: LocalDataView(lastUsedDate: self.revision, lastLaunched: nil),
            attachments: attachments ?? [attachment],
            attachmentDecryptionFailures: attachmentFailure ? [attachment] : nil,
            fields: [FieldView(name: "Hidden", value: "fake-field-value", type: .hidden, linkedId: nil)],
            passwordHistory: [PasswordHistoryView(password: "fake-old-password", lastUsedDate: self.revision)],
            creationDate: Date(timeIntervalSince1970: 50), deletedDate: deleted ? self.revision : nil,
            revisionDate: revision ?? self.revision, archivedDate: archived ? self.revision : nil
        )
    }
}
