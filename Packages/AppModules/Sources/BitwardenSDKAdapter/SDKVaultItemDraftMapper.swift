import BitwardenSdk
import Domain
import Foundation

/// A transitional value mapper used by the live editor until Data owns the edit base and write
/// transaction. No SDK model or hidden metadata is stored in the Domain draft itself.
public enum SDKVaultItemDraftMapper {
    public static func itemKind(for type: CipherType) -> VaultItemKind {
        switch type {
        case .login: .login
        case .secureNote: .secureNote
        case .card: .card
        case .identity: .identity
        case .sshKey: .sshKey
        case .bankAccount: .bankAccount
        case .driversLicense: .driversLicense
        case .passport: .passport
        }
    }

    public static func makeDraft(from cipher: CipherView) throws -> VaultItemDraft {
        guard let id = cipher.id, !id.isEmpty else { throw VaultItemDraftError.missingItem }
        try requireEditable(cipher)
        var draft = VaultItemDraft(
            editingID: CipherID(rawValue: id), kind: itemKind(for: cipher.type),
            baseRevision: cipher.revisionDate, folderID: cipher.folderId.map { FolderID(rawValue: $0) }
        )
        draft.name = cipher.name
        draft.notes = cipher.notes ?? ""
        draft.favorite = cipher.favorite
        if let login = cipher.login {
            draft.username = login.username ?? ""
            draft.password = login.password ?? ""
            draft.totpSeed = login.totp ?? ""
            let uris = (login.uris ?? []).map { $0.uri ?? "" }
            draft.uris = uris.isEmpty ? [""] : uris
        }
        if let card = cipher.card {
            draft.cardholderName = card.cardholderName ?? ""
            draft.cardNumber = card.number ?? ""
            draft.cardBrand = card.brand ?? ""
            draft.cardExpMonth = card.expMonth ?? ""
            draft.cardExpYear = card.expYear ?? ""
            draft.cardCode = card.code ?? ""
        }
        if let identity = cipher.identity {
            draft.firstName = identity.firstName ?? ""
            draft.lastName = identity.lastName ?? ""
            draft.identityUsername = identity.username ?? ""
            draft.identityEmail = identity.email ?? ""
            draft.identityPhone = identity.phone ?? ""
        }
        if let sshKey = cipher.sshKey {
            draft.sshPrivateKey = sshKey.privateKey
            draft.sshPublicKey = sshKey.publicKey
            draft.sshFingerprint = sshKey.fingerprint
        }
        return draft
    }

    /// Only form fields change. The caller must provide the exact, still-current edit base; an
    /// edit can never fall back to a new item, switch type, or write against a different item id.
    public static func applying(
        _ draft: VaultItemDraft, to existing: CipherView?, now: Date = Date()
    ) throws -> CipherView {
        guard draft.kind.supportsEditing else { throw VaultItemDraftError.unsupportedItemKind }
        if let editingID = draft.editingID {
            guard let existing else { throw VaultItemDraftError.missingItem }
            guard existing.id == editingID.rawValue, itemKind(for: existing.type) == draft.kind else {
                throw VaultItemDraftError.draftMismatch
            }
            guard draft.baseRevision == existing.revisionDate else { throw VaultItemDraftError.staleDraft }
            try requireEditable(existing)
        } else {
            guard existing == nil, draft.baseRevision == nil else { throw VaultItemDraftError.draftMismatch }
        }
        let type = try sdkType(for: draft.kind)
        return CipherView(
            id: existing?.id,
            organizationId: existing?.organizationId,
            folderId: draft.folderID?.rawValue,
            collectionIds: existing?.collectionIds ?? [],
            key: existing?.key,
            name: draft.name,
            notes: merged(draft.notes, original: existing?.notes),
            type: type,
            login: type == .login ? loginView(draft, original: existing?.login) : nil,
            identity: type == .identity ? identityView(draft, original: existing?.identity) : nil,
            card: type == .card ? cardView(draft, original: existing?.card) : nil,
            secureNote: type == .secureNote ? (existing?.secureNote ?? SecureNoteView(type: .generic)) : nil,
            sshKey: type == .sshKey ? SshKeyView(
                privateKey: draft.sshPrivateKey, publicKey: draft.sshPublicKey, fingerprint: draft.sshFingerprint
            ) : nil,
            bankAccount: existing?.bankAccount,
            driversLicense: existing?.driversLicense,
            passport: existing?.passport,
            favorite: draft.favorite,
            reprompt: existing?.reprompt ?? .none,
            organizationUseTotp: existing?.organizationUseTotp ?? false,
            edit: existing?.edit ?? true,
            permissions: existing?.permissions,
            viewPassword: existing?.viewPassword ?? true,
            localData: existing?.localData,
            attachments: existing?.attachments,
            attachmentDecryptionFailures: existing?.attachmentDecryptionFailures,
            fields: existing?.fields,
            passwordHistory: existing?.passwordHistory,
            creationDate: existing?.creationDate ?? now,
            deletedDate: existing?.deletedDate,
            revisionDate: now,
            archivedDate: existing?.archivedDate
        )
    }

    private static func requireEditable(_ cipher: CipherView) throws {
        guard itemKind(for: cipher.type).supportsEditing else { throw VaultItemDraftError.unsupportedItemKind }
        guard cipher.edit, SDKVaultAccessPolicy.allowsUnpromptedSecretAccess(cipher),
              (cipher.attachmentDecryptionFailures ?? []).isEmpty
        else { throw VaultItemDraftError.readOnly }
    }

    private static func sdkType(for kind: VaultItemKind) throws -> CipherType {
        switch kind {
        case .login: .login
        case .secureNote: .secureNote
        case .card: .card
        case .identity: .identity
        case .sshKey: .sshKey
        case .bankAccount, .driversLicense, .passport, .unknown:
            throw VaultItemDraftError.unsupportedItemKind
        }
    }

    /// Preserve optional/empty distinctions when the corresponding text field was not changed.
    private static func merged(_ value: String, original: String?) -> String? {
        if value == (original ?? "") { return original }
        return value.isEmpty ? nil : value
    }

    private static func loginView(_ draft: VaultItemDraft, original: LoginView?) -> LoginView {
        let originalURIs = original?.uris ?? []
        let displayedURIs = originalURIs.isEmpty ? [""] : originalURIs.map { $0.uri ?? "" }
        let uris: [LoginUriView]?
        if draft.uris == displayedURIs {
            uris = original?.uris
        } else {
            // The existing form only appends or changes URI fields. Preserve metadata at each
            // source position, including unchanged nil/empty rows, and omit newly empty rows.
            uris = draft.uris.enumerated().compactMap { index, value in
                let preserved = originalURIs.indices.contains(index) ? originalURIs[index] : nil
                guard !value.isEmpty else { return preserved?.uri?.isEmpty != false ? preserved : nil }
                return LoginUriView(uri: value, match: preserved?.match, uriChecksum: preserved?.uriChecksum)
            }
        }
        return LoginView(
            username: merged(draft.username, original: original?.username),
            password: merged(draft.password, original: original?.password),
            passwordRevisionDate: original?.passwordRevisionDate,
            uris: uris,
            totp: merged(draft.totpSeed, original: original?.totp),
            autofillOnPageLoad: original?.autofillOnPageLoad,
            fido2Credentials: original?.fido2Credentials
        )
    }

    private static func cardView(_ draft: VaultItemDraft, original: CardView?) -> CardView {
        CardView(
            cardholderName: merged(draft.cardholderName, original: original?.cardholderName),
            expMonth: merged(draft.cardExpMonth, original: original?.expMonth),
            expYear: merged(draft.cardExpYear, original: original?.expYear),
            code: merged(draft.cardCode, original: original?.code),
            brand: merged(draft.cardBrand, original: original?.brand),
            number: merged(draft.cardNumber, original: original?.number)
        )
    }

    private static func identityView(_ draft: VaultItemDraft, original: IdentityView?) -> IdentityView {
        IdentityView(
            title: original?.title,
            firstName: merged(draft.firstName, original: original?.firstName),
            middleName: original?.middleName,
            lastName: merged(draft.lastName, original: original?.lastName),
            address1: original?.address1, address2: original?.address2, address3: original?.address3,
            city: original?.city, state: original?.state, postalCode: original?.postalCode,
            country: original?.country, company: original?.company,
            email: merged(draft.identityEmail, original: original?.email),
            phone: merged(draft.identityPhone, original: original?.phone),
            ssn: original?.ssn,
            username: merged(draft.identityUsername, original: original?.username),
            passportNumber: original?.passportNumber, licenseNumber: original?.licenseNumber
        )
    }
}
