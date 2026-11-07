import BitwardenSdk
import Domain
import Foundation

/// Pure SDK -> Domain projections for repository snapshots; no second mutable UI authority.
public enum SDKVaultPresentationMapper {
    public static func permissions(
        for cipher: CipherView, collections: [VaultCollectionSummary], supportsLosslessEditing: Bool = true
    ) -> VaultItemPermissions {
        permissions(for: cipher, lookup: collectionLookup(collections), supportsLosslessEditing: supportsLosslessEditing)
    }

    private static func permissions(
        for cipher: CipherView, lookup: [String: VaultCollectionSummary], supportsLosslessEditing: Bool = true
    ) -> VaultItemPermissions {
        let assignedIDs = Set(cipher.collectionIds)
        let assigned = assignedIDs.compactMap { lookup[$0] }
        let resolved = assigned.count == assignedIDs.count
            && assigned.allSatisfy { cipher.organizationId == nil || $0.organizationID.rawValue == cipher.organizationId }
        let isActive = cipher.deletedDate == nil && cipher.archivedDate == nil
        let canView = SDKVaultAccessPolicy.allowsUnpromptedSecretAccess(cipher)
            && resolved && !assigned.contains(where: \.hidesPasswords)
        let restriction: VaultEditRestriction?
        if !isActive { restriction = .inactiveItem }
        else if cipher.reprompt != .none { restriction = .repromptRequired }
        else if !SDKVaultItemDraftMapper.itemKind(for: cipher.type).supportsEditing { restriction = .unsupportedKind }
        else if !supportsLosslessEditing { restriction = .unsupportedPayload }
        else if !cipher.edit { restriction = .editDenied }
        else if !(cipher.attachmentDecryptionFailures ?? []).isEmpty { restriction = .attachmentDecryptionFailure }
        else if !resolved { restriction = .unresolvedCollection }
        else if !canView { restriction = .secretsHidden }
        else if assigned.contains(where: \.isReadOnly) { restriction = .collectionReadOnly }
        else { restriction = nil }
        return VaultItemPermissions(
            editRestriction: restriction,
            canDelete: restriction == nil && cipher.permissions?.delete != false,
            canViewSecrets: canView
        )
    }

    public static func summary(
        from cipher: CipherView, collections: [VaultCollectionSummary]
    ) -> VaultItemSummary? {
        summary(from: cipher, lookup: collectionLookup(collections))
    }

    /// Index collection permissions once for a list projection, not once per vault item.
    public static func summaries(
        from ciphers: [CipherView], collections: [VaultCollectionSummary], unsupportedPayloadIDs: Set<String> = []
    ) -> [VaultItemSummary] {
        let lookup = collectionLookup(collections)
        return ciphers.compactMap { summary(
            from: $0, lookup: lookup,
            supportsLosslessEditing: $0.id.map { !unsupportedPayloadIDs.contains($0) } ?? true
        ) }
    }

    private static func summary(
        from cipher: CipherView, lookup: [String: VaultCollectionSummary], supportsLosslessEditing: Bool = true
    ) -> VaultItemSummary? {
        guard let id = activeID(cipher) else { return nil }
        let permissions = permissions(for: cipher, lookup: lookup, supportsLosslessEditing: supportsLosslessEditing)
        let subtitle: String?
        switch cipher.type {
        case .login: subtitle = cipher.login?.username
        case .card:
            subtitle = [cipher.card?.brand, permissions.canViewSecrets ? cipher.card?.number.map(maskedCardNumber) : nil]
                .compactMap { $0 }.joined(separator: " ")
        case .identity:
            subtitle = permissions.canViewSecrets
                ? [cipher.identity?.firstName, cipher.identity?.lastName].compactMap { $0 }.joined(separator: " ") : nil
        case .secureNote: subtitle = permissions.canViewSecrets ? cipher.notes : nil
        case .sshKey: subtitle = cipher.sshKey?.fingerprint
        case .bankAccount, .driversLicense, .passport: subtitle = nil
        }
        return VaultItemSummary(
            id: id, kind: SDKVaultItemDraftMapper.itemKind(for: cipher.type), name: cipher.name,
            subtitle: subtitle, isFavorite: cipher.favorite, isEditable: permissions.canEdit,
            canDelete: permissions.canDelete, hasPasskeys: !(cipher.login?.fido2Credentials ?? []).isEmpty,
            folderID: cipher.folderId.map { FolderID(rawValue: $0) },
            collectionIDs: cipher.collectionIds.map { CollectionID(rawValue: $0) },
            searchTerms: [cipher.login?.username].compactMap { $0 } + (cipher.login?.uris ?? []).compactMap(\.uri)
        )
    }

    public static func detail(
        from cipher: CipherView, collections: [VaultCollectionSummary], organizationName: String? = nil,
        supportsLosslessEditing: Bool = true
    ) -> VaultItemDetail? {
        guard let id = activeID(cipher) else { return nil }
        let permissions = permissions(
            for: cipher,
            collections: collections,
            supportsLosslessEditing: supportsLosslessEditing
        )
        let payload: VaultItemPayload
        switch cipher.type {
        case .login:
            payload = .login(VaultLoginDetail(
                username: cipher.login?.username,
                password: permissions.canViewSecrets ? cipher.login?.password : nil,
                hasPassword: !(cipher.login?.password ?? "").isEmpty,
                uris: (cipher.login?.uris ?? []).compactMap(\.uri).filter { !$0.isEmpty },
                hasTotp: permissions.canViewSecrets && !(cipher.login?.totp ?? "").isEmpty,
                hasPasskeys: permissions.canViewSecrets && !(cipher.login?.fido2Credentials ?? []).isEmpty
            ))
        case .card:
            payload = .card(VaultCardDetail(
                cardholderName: permissions.canViewSecrets ? cipher.card?.cardholderName : nil,
                number: permissions.canViewSecrets ? cipher.card?.number : nil,
                expiration: permissions.canViewSecrets
                    ? [cipher.card?.expMonth, cipher.card?.expYear].compactMap { $0 }.joined(separator: "/") : "",
                securityCode: permissions.canViewSecrets ? cipher.card?.code : nil
            ))
        case .identity:
            payload = .identity(VaultIdentityDetail(
                fullName: permissions.canViewSecrets
                    ? [cipher.identity?.firstName, cipher.identity?.lastName].compactMap { $0 }.joined(separator: " ") : "",
                username: permissions.canViewSecrets ? cipher.identity?.username : nil,
                email: permissions.canViewSecrets ? cipher.identity?.email : nil,
                phone: permissions.canViewSecrets ? cipher.identity?.phone : nil
            ))
        case .secureNote: payload = .secureNote
        case .sshKey:
            payload = .sshKey(VaultSSHKeyDetail(
                publicKey: permissions.canViewSecrets ? cipher.sshKey?.publicKey : nil,
                privateKey: permissions.canViewSecrets ? cipher.sshKey?.privateKey : nil,
                fingerprint: cipher.sshKey?.fingerprint
            ))
        case .bankAccount, .driversLicense, .passport: payload = .unsupported
        }
        let attachments = cipher.attachments ?? []
        let idCounts = attachments.reduce(into: [String: Int]()) { counts, attachment in
            if let id = attachment.id { counts[id, default: 0] += 1 }
        }
        return VaultItemDetail(
            context: VaultItemContext(id: id, revision: cipher.revisionDate),
            kind: SDKVaultItemDraftMapper.itemKind(for: cipher.type), name: cipher.name,
            notes: permissions.canViewSecrets ? cipher.notes : nil, isFavorite: cipher.favorite,
            organizationName: organizationName, permissions: permissions, payload: payload,
            attachments: attachments.map { attachment in
                let reference = attachment.id.flatMap { attachmentID -> VaultAttachmentReference? in
                    guard !attachmentID.isEmpty, idCounts[attachmentID] == 1 else { return nil }
                    return VaultAttachmentReference(cipherID: id, attachmentID: AttachmentID(rawValue: attachmentID))
                }
                return VaultAttachmentSummary(
                    reference: reference, fileName: attachment.fileName ?? "Attachment",
                    sizeName: attachment.sizeName, canDownload: permissions.canViewSecrets && reference != nil
                )
            }
        )
    }

    public static func folders(from folders: [FolderView]) -> [VaultFolderSummary] {
        let counts = folders.reduce(into: [String: Int]()) { counts, folder in
            if let id = folder.id { counts[id, default: 0] += 1 }
        }
        return folders.compactMap { folder in
            guard let id = folder.id, !id.isEmpty, counts[id] == 1 else { return nil }
            return VaultFolderSummary(id: FolderID(rawValue: id), name: folder.name)
        }
    }

    public static func collections(from collections: [CollectionView]) -> [VaultCollectionSummary] {
        let counts = collections.reduce(into: [String: Int]()) { counts, collection in
            if let id = collection.id { counts[id, default: 0] += 1 }
        }
        return collections.compactMap { collection in
            guard let id = collection.id, !id.isEmpty, counts[id] == 1 else { return nil }
            return VaultCollectionSummary(
                id: CollectionID(rawValue: id), organizationID: OrganizationID(rawValue: collection.organizationId),
                name: collection.name, isReadOnly: collection.readOnly, hidesPasswords: collection.hidePasswords
            )
        }
    }

    public static func passkeys(from credentials: [Fido2CredentialView]) -> [VaultPasskeySummary] {
        var seen: Set<String> = []
        return credentials.compactMap { credential in
            guard !credential.credentialId.isEmpty, seen.insert(credential.credentialId).inserted else { return nil }
            return VaultPasskeySummary(
                id: credential.credentialId, relyingPartyName: credential.rpName ?? credential.rpId,
                userName: credential.userDisplayName ?? credential.userName
            )
        }
    }

    private static func activeID(_ cipher: CipherView) -> CipherID? {
        guard let id = cipher.id, !id.isEmpty, cipher.deletedDate == nil, cipher.archivedDate == nil else { return nil }
        return CipherID(rawValue: id)
    }

    private static func collectionLookup(_ collections: [VaultCollectionSummary]) -> [String: VaultCollectionSummary] {
        var lookup: [String: VaultCollectionSummary] = [:]
        var ambiguous: Set<String> = []
        for collection in collections {
            if lookup.updateValue(collection, forKey: collection.id.rawValue) != nil {
                ambiguous.insert(collection.id.rawValue)
            }
        }
        for id in ambiguous { lookup.removeValue(forKey: id) }
        return lookup
    }

    private static func maskedCardNumber(_ number: String) -> String {
        number.count >= 4 ? "••••\(number.suffix(4))" : "••••"
    }
}
