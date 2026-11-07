import BitwardenSdk
import Foundation

// Compatibility wire models for the existing field-level cipher format. All JSON/SDK mapping
// lives at this boundary; Domain and the new presentation targets must not use these types.

// MARK: - Response (sync / create / update)

public struct CipherLoginUriDTO: Codable, Sendable {
    public var uri: String?
    public var uriChecksum: String?
    public var match: Int?

    public init(uri: String?, uriChecksum: String?, match: Int?) {
        self.uri = uri
        self.uriChecksum = uriChecksum
        self.match = match
    }
}

/// Mirrors `CipherFido2CredentialModel`. All sub-fields stay opaque strings at this layer (still
/// encrypted) - only `client.vault().ciphers().decryptFido2Credentials(cipherView:)` produces
/// human-readable values, and only that call is used for display.
public struct CipherLoginFido2CredentialDTO: Codable, Sendable {
    public var credentialId: String?
    public var keyType: String?
    public var keyAlgorithm: String?
    public var keyCurve: String?
    public var keyValue: String?
    public var rpId: String?
    public var rpName: String?
    public var userHandle: String?
    public var userName: String?
    public var userDisplayName: String?
    public var counter: String?
    public var discoverable: String?
    public var creationDate: String

    public init(
        credentialId: String?, keyType: String?, keyAlgorithm: String?, keyCurve: String?, keyValue: String?,
        rpId: String?, rpName: String?, userHandle: String?, userName: String?, userDisplayName: String?,
        counter: String?, discoverable: String?, creationDate: String
    ) {
        self.credentialId = credentialId
        self.keyType = keyType
        self.keyAlgorithm = keyAlgorithm
        self.keyCurve = keyCurve
        self.keyValue = keyValue
        self.rpId = rpId
        self.rpName = rpName
        self.userHandle = userHandle
        self.userName = userName
        self.userDisplayName = userDisplayName
        self.counter = counter
        self.discoverable = discoverable
        self.creationDate = creationDate
    }
}

public struct CipherLoginDTO: Codable, Sendable {
    public var username: String?
    public var password: String?
    public var passwordRevisionDate: String?
    public var uris: [CipherLoginUriDTO]?
    public var totp: String?
    public var autofillOnPageLoad: Bool?
    public var fido2Credentials: [CipherLoginFido2CredentialDTO]?

    public init(
        username: String?, password: String?, passwordRevisionDate: String?, uris: [CipherLoginUriDTO]?,
        totp: String?, autofillOnPageLoad: Bool?, fido2Credentials: [CipherLoginFido2CredentialDTO]?
    ) {
        self.username = username
        self.password = password
        self.passwordRevisionDate = passwordRevisionDate
        self.uris = uris
        self.totp = totp
        self.autofillOnPageLoad = autofillOnPageLoad
        self.fido2Credentials = fido2Credentials
    }
}

public struct CipherCardDTO: Codable, Sendable {
    public var cardholderName: String?
    public var brand: String?
    public var number: String?
    public var expMonth: String?
    public var expYear: String?
    public var code: String?

    public init(
        cardholderName: String?,
        brand: String?,
        number: String?,
        expMonth: String?,
        expYear: String?,
        code: String?
    ) {
        self.cardholderName = cardholderName
        self.brand = brand
        self.number = number
        self.expMonth = expMonth
        self.expYear = expYear
        self.code = code
    }
}

public struct CipherIdentityDTO: Codable, Sendable {
    public var title: String?
    public var firstName: String?
    public var middleName: String?
    public var lastName: String?
    public var address1: String?
    public var address2: String?
    public var address3: String?
    public var city: String?
    public var state: String?
    public var postalCode: String?
    public var country: String?
    public var company: String?
    public var email: String?
    public var phone: String?
    public var ssn: String?
    public var username: String?
    public var passportNumber: String?
    public var licenseNumber: String?

    public init(
        title: String?, firstName: String?, middleName: String?, lastName: String?, address1: String?,
        address2: String?, address3: String?, city: String?, state: String?, postalCode: String?,
        country: String?, company: String?, email: String?, phone: String?, ssn: String?, username: String?,
        passportNumber: String?, licenseNumber: String?
    ) {
        self.title = title
        self.firstName = firstName
        self.middleName = middleName
        self.lastName = lastName
        self.address1 = address1
        self.address2 = address2
        self.address3 = address3
        self.city = city
        self.state = state
        self.postalCode = postalCode
        self.country = country
        self.company = company
        self.email = email
        self.phone = phone
        self.ssn = ssn
        self.username = username
        self.passportNumber = passportNumber
        self.licenseNumber = licenseNumber
    }
}

public struct CipherSecureNoteDTO: Codable, Sendable {
    public var type: Int?

    public init(type: Int?) {
        self.type = type
    }
}

public struct CipherSshKeyDTO: Codable, Sendable {
    public var privateKey: String?
    public var publicKey: String?
    public var keyFingerprint: String?

    public init(privateKey: String?, publicKey: String?, keyFingerprint: String?) {
        self.privateKey = privateKey
        self.publicKey = publicKey
        self.keyFingerprint = keyFingerprint
    }
}

/// Encrypted custom fields are carried through even though this client has no field editor.
public struct CipherFieldDTO: Codable, Sendable {
    public var type: Int?
    public var name: String?
    public var value: String?
    public var linkedId: Int?

    public init(type: Int?, name: String?, value: String?, linkedId: Int?) {
        self.type = type
        self.name = name
        self.value = value
        self.linkedId = linkedId
    }
}

public struct CipherPasswordHistoryDTO: Codable, Sendable {
    public var password: String
    public var lastUsedDate: String

    public init(password: String, lastUsedDate: String) {
        self.password = password
        self.lastUsedDate = lastUsedDate
    }
}

public struct CipherPermissionsDTO: Codable, Sendable {
    public var delete: Bool?
    public var restore: Bool?

    public init(delete: Bool?, restore: Bool?) {
        self.delete = delete
        self.restore = restore
    }
}

public struct CipherAttachmentDTO: Codable, Sendable {
    public var fileName: String?
    public var key: String?

    public init(fileName: String?, key: String?) {
        self.fileName = fileName
        self.key = key
    }
}

public struct CipherResponseDTO: Codable, Sendable {
    /// Nonsecret local safety fence. Unknown server fields are NOT supported by the SDK mapper;
    /// never allow a lossy replacement. Persist this fence when projecting the encrypted cache.
    public private(set) var hasUnrecognizedPayload = false
    public var id: String?
    public var organizationId: String?
    public var folderId: String?
    public var collectionIds: [String]?
    public var type: Int
    public var name: String?
    public var notes: String?
    public var favorite: Bool?
    public var reprompt: Int?
    public var key: String?
    /// Identity whose key encrypted this cipher. Older servers may omit it from responses.
    public var encryptedFor: String?
    public var login: CipherLoginDTO?
    public var card: CipherCardDTO?
    public var identity: CipherIdentityDTO?
    public var secureNote: CipherSecureNoteDTO?
    public var sshKey: CipherSshKeyDTO?
    public var organizationUseTotp: Bool?
    public var edit: Bool?
    public var viewPassword: Bool?
    public var attachments: [AttachmentResponseDTO]?
    public var revisionDate: String?
    public var creationDate: String?
    public var deletedDate: String?
    public var archivedDate: String?
    public var fields: [CipherFieldDTO]?
    public var passwordHistory: [CipherPasswordHistoryDTO]?
    public var permissions: CipherPermissionsDTO?
    public var data: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, organizationId, folderId, collectionIds, type, name, notes, favorite, reprompt, key, encryptedFor
        case login, card, identity, secureNote, sshKey, organizationUseTotp, edit, viewPassword
        case attachments, revisionDate, creationDate, deletedDate, archivedDate, fields
        case passwordHistory, permissions, data
        case hasUnrecognizedPayload = "_nativeHasUnrecognizedPayload"
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decodeIfPresent(String.self, forKey: .id),
            organizationId: try values.decodeIfPresent(String.self, forKey: .organizationId),
            folderId: try values.decodeIfPresent(String.self, forKey: .folderId),
            collectionIds: try values.decodeIfPresent([String].self, forKey: .collectionIds),
            type: try values.decode(Int.self, forKey: .type),
            name: try values.decodeIfPresent(String.self, forKey: .name),
            notes: try values.decodeIfPresent(String.self, forKey: .notes),
            favorite: try values.decodeIfPresent(Bool.self, forKey: .favorite),
            reprompt: try values.decodeIfPresent(Int.self, forKey: .reprompt),
            key: try values.decodeIfPresent(String.self, forKey: .key),
            encryptedFor: try values.decodeIfPresent(String.self, forKey: .encryptedFor),
            login: try values.decodeIfPresent(CipherLoginDTO.self, forKey: .login),
            card: try values.decodeIfPresent(CipherCardDTO.self, forKey: .card),
            identity: try values.decodeIfPresent(CipherIdentityDTO.self, forKey: .identity),
            secureNote: try values.decodeIfPresent(CipherSecureNoteDTO.self, forKey: .secureNote),
            sshKey: try values.decodeIfPresent(CipherSshKeyDTO.self, forKey: .sshKey),
            organizationUseTotp: try values.decodeIfPresent(Bool.self, forKey: .organizationUseTotp),
            edit: try values.decodeIfPresent(Bool.self, forKey: .edit),
            viewPassword: try values.decodeIfPresent(Bool.self, forKey: .viewPassword),
            attachments: try values.decodeIfPresent([AttachmentResponseDTO].self, forKey: .attachments),
            revisionDate: try values.decodeIfPresent(String.self, forKey: .revisionDate),
            creationDate: try values.decodeIfPresent(String.self, forKey: .creationDate),
            deletedDate: try values.decodeIfPresent(String.self, forKey: .deletedDate),
            archivedDate: try values.decodeIfPresent(String.self, forKey: .archivedDate),
            fields: try values.decodeIfPresent([CipherFieldDTO].self, forKey: .fields),
            passwordHistory: try values.decodeIfPresent([CipherPasswordHistoryDTO].self, forKey: .passwordHistory),
            permissions: try values.decodeIfPresent(CipherPermissionsDTO.self, forKey: .permissions),
            data: try values.decodeIfPresent(String.self, forKey: .data)
        )
        hasUnrecognizedPayload = try values.decodeIfPresent(Bool.self, forKey: .hasUnrecognizedPayload) == true
            || CipherPayloadSupport.hasUnrecognizedFields(in: decoder)
        // Also persist edit=false for older readers that do not understand the local fence.
        if hasUnrecognizedPayload { edit = false }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(id, forKey: .id)
        try values.encodeIfPresent(organizationId, forKey: .organizationId)
        try values.encodeIfPresent(folderId, forKey: .folderId)
        try values.encodeIfPresent(collectionIds, forKey: .collectionIds)
        try values.encode(type, forKey: .type)
        try values.encodeIfPresent(name, forKey: .name)
        try values.encodeIfPresent(notes, forKey: .notes)
        try values.encodeIfPresent(favorite, forKey: .favorite)
        try values.encodeIfPresent(reprompt, forKey: .reprompt)
        try values.encodeIfPresent(key, forKey: .key)
        try values.encodeIfPresent(encryptedFor, forKey: .encryptedFor)
        try values.encodeIfPresent(login, forKey: .login)
        try values.encodeIfPresent(card, forKey: .card)
        try values.encodeIfPresent(identity, forKey: .identity)
        try values.encodeIfPresent(secureNote, forKey: .secureNote)
        try values.encodeIfPresent(sshKey, forKey: .sshKey)
        try values.encodeIfPresent(organizationUseTotp, forKey: .organizationUseTotp)
        try values.encodeIfPresent(hasUnrecognizedPayload ? false : edit, forKey: .edit)
        try values.encodeIfPresent(viewPassword, forKey: .viewPassword)
        try values.encodeIfPresent(attachments, forKey: .attachments)
        try values.encodeIfPresent(revisionDate, forKey: .revisionDate)
        try values.encodeIfPresent(creationDate, forKey: .creationDate)
        try values.encodeIfPresent(deletedDate, forKey: .deletedDate)
        try values.encodeIfPresent(archivedDate, forKey: .archivedDate)
        try values.encodeIfPresent(fields, forKey: .fields)
        try values.encodeIfPresent(passwordHistory, forKey: .passwordHistory)
        try values.encodeIfPresent(permissions, forKey: .permissions)
        try values.encodeIfPresent(data, forKey: .data)
        if hasUnrecognizedPayload { try values.encode(true, forKey: .hasUnrecognizedPayload) }
    }

    public init(
        id: String?, organizationId: String?, folderId: String?, collectionIds: [String]?, type: Int,
        name: String?, notes: String?, favorite: Bool?, reprompt: Int?, key: String?, encryptedFor: String? = nil,
        login: CipherLoginDTO?,
        card: CipherCardDTO?, identity: CipherIdentityDTO?, secureNote: CipherSecureNoteDTO?,
        sshKey: CipherSshKeyDTO?, organizationUseTotp: Bool?, edit: Bool?, viewPassword: Bool?,
        attachments: [AttachmentResponseDTO]?, revisionDate: String?, creationDate: String?,
        deletedDate: String?, archivedDate: String?, fields: [CipherFieldDTO]? = nil,
        passwordHistory: [CipherPasswordHistoryDTO]? = nil, permissions: CipherPermissionsDTO? = nil,
        data: String? = nil
    ) {
        self.id = id
        self.organizationId = organizationId
        self.folderId = folderId
        self.collectionIds = collectionIds
        self.type = type
        self.name = name
        self.notes = notes
        self.favorite = favorite
        self.reprompt = reprompt
        self.key = key
        self.encryptedFor = encryptedFor
        self.login = login
        self.card = card
        self.identity = identity
        self.secureNote = secureNote
        self.sshKey = sshKey
        self.organizationUseTotp = organizationUseTotp
        self.edit = edit
        self.viewPassword = viewPassword
        self.attachments = attachments
        self.revisionDate = revisionDate
        self.creationDate = creationDate
        self.deletedDate = deletedDate
        self.archivedDate = archivedDate
        self.fields = fields
        self.passwordHistory = passwordHistory
        self.permissions = permissions
        self.data = data
    }
}

public struct FolderResponseDTO: Codable, Sendable {
    public var id: String?
    public var name: String?
    public var revisionDate: String?
}

/// One entry from `profile.organizations[]` - just enough to unlock org-owned cipher decryption
/// (`key`) and label things in the UI (`name`). The full model has ~50 policy/permission flags we
/// don't need yet.
public struct ProfileOrganizationDTO: Codable, Sendable {
    public var id: String?
    public var name: String?
    public var key: String?
}

public struct ProfileDTO: Codable, Sendable {
    public var organizations: [ProfileOrganizationDTO]?
}

/// Mirrors `CollectionDetailsResponseModel` - a collection scoped to the current user, including
/// their effective permissions on it (`readOnly`, `manage`).
public struct CollectionResponseDTO: Codable, Sendable {
    public var id: String?
    public var organizationId: String?
    public var name: String?
    public var externalId: String?
    public var type: Int?
    public var readOnly: Bool?
    public var hidePasswords: Bool?
    public var manage: Bool?
}

public struct SyncResponseDTO: Codable, Sendable {
    public var profile: ProfileDTO?
    public var folders: [FolderResponseDTO]?
    public var collections: [CollectionResponseDTO]?
    public var ciphers: [CipherResponseDTO]?
}

// MARK: - Response -> SDK domain mapping

public enum CipherMappingError: Error, Equatable, Sendable {
    case missingRequiredField(String)
    case invalidField(String)
    case unsupportedPayload
}

private enum CipherWireValidation {
    static func enumValue<Value: RawRepresentable>(
        _ rawValue: Int, as type: Value.Type, field: String
    ) throws -> Value where Value.RawValue == UInt8 {
        guard let byte = UInt8(exactly: rawValue), let value = Value(rawValue: byte) else {
            throw CipherMappingError.invalidField(field)
        }
        return value
    }

    static func date(_ value: String?, field: String) throws -> Date? {
        guard let value else { return nil }
        guard let date = ServerDateParsing.parse(value) else {
            throw CipherMappingError.invalidField(field)
        }
        return date
    }
}

public extension CipherResponseDTO {
    /// Maps the server's (still-encrypted) response into the SDK's `Cipher`, ready to hand to
    /// `CiphersClient.decrypt(cipher:)`.
    func toSDKCipher() throws -> Cipher {
        // Blob-format support is outside this refactor's scope. Never silently discard its data
        // and then allow a legacy editor to overwrite the item with an empty field-level payload.
        guard data == nil else { throw CipherMappingError.unsupportedPayload }
        guard let name else { throw CipherMappingError.missingRequiredField("name") }
        let type = try CipherWireValidation.enumValue(type, as: CipherType.self, field: "type")
        guard let revisionDate = try CipherWireValidation.date(revisionDate, field: "revisionDate") else {
            throw CipherMappingError.missingRequiredField("revisionDate")
        }
        let creationDate = try CipherWireValidation.date(creationDate, field: "creationDate") ?? revisionDate

        return Cipher(
            id: id,
            organizationId: organizationId,
            folderId: folderId,
            collectionIds: collectionIds ?? [],
            key: key,
            name: name,
            notes: notes,
            type: type,
            login: try login?.toSDKLogin(),
            identity: identity?.toSDKIdentity(),
            card: card?.toSDKCard(),
            secureNote: try secureNote.map {
                SecureNote(
                    type: try CipherWireValidation.enumValue(
                        $0.type ?? 0,
                        as: SecureNoteType.self,
                        field: "secureNote.type"
                    )
                )
            },
            sshKey: try sshKey?.toSDKSshKey(),
            bankAccount: nil,
            driversLicense: nil,
            passport: nil,
            favorite: favorite ?? false,
            reprompt: try CipherWireValidation.enumValue(reprompt ?? 0, as: CipherRepromptType.self, field: "reprompt"),
            organizationUseTotp: organizationUseTotp ?? false,
            edit: (edit ?? true) && !hasUnrecognizedPayload,
            permissions: permissions.map { CipherPermissions(delete: $0.delete ?? false, restore: $0.restore ?? false) },
            viewPassword: viewPassword ?? true,
            localData: nil,
            attachments: attachments?.map { $0.toSDKAttachment() },
            fields: try fields?.map { try $0.toSDKField() },
            passwordHistory: try passwordHistory?.map { try $0.toSDKPasswordHistory() },
            creationDate: creationDate,
            deletedDate: try CipherWireValidation.date(deletedDate, field: "deletedDate"),
            revisionDate: revisionDate,
            archivedDate: try CipherWireValidation.date(archivedDate, field: "archivedDate"),
            data: nil
        )
    }
}

extension CipherLoginDTO {
    func toSDKLogin() throws -> Login {
        Login(
            username: username,
            password: password,
            passwordRevisionDate: try CipherWireValidation.date(
                passwordRevisionDate,
                field: "login.passwordRevisionDate"
            ),
            uris: try uris?.map {
                LoginUri(
                    uri: $0.uri,
                    match: try $0.match.map { try CipherWireValidation.enumValue(
                        $0,
                        as: UriMatchType.self,
                        field: "login.uris.match"
                    ) },
                    uriChecksum: $0.uriChecksum
                )
            },
            totp: totp,
            autofillOnPageLoad: autofillOnPageLoad,
            fido2Credentials: try fido2Credentials?.map { try $0.toSDKFido2Credential() }
        )
    }
}

private extension CipherLoginFido2CredentialDTO {
    /// Never omit malformed passkeys and then allow an edit to erase them server-side. The sync
    /// loader reports an unavailable item; its original encrypted DTO remains in the cache input.
    func toSDKFido2Credential() throws -> Fido2Credential {
        guard let credentialId, let keyType, let keyAlgorithm, let keyCurve, let keyValue,
              let rpId, let counter, let discoverable,
              let creationDateParsed = ServerDateParsing.parse(creationDate)
        else { throw CipherMappingError.invalidField("login.fido2Credentials") }
        return Fido2Credential(
            credentialId: credentialId,
            keyType: keyType,
            keyAlgorithm: keyAlgorithm,
            keyCurve: keyCurve,
            keyValue: keyValue,
            rpId: rpId,
            userHandle: userHandle,
            userName: userName,
            counter: counter,
            rpName: rpName,
            userDisplayName: userDisplayName,
            discoverable: discoverable,
            creationDate: creationDateParsed
        )
    }
}

private extension CipherFieldDTO {
    func toSDKField() throws -> Field {
        let linkedId: UInt32? = try linkedId.map {
            guard let value = UInt32(exactly: $0) else { throw CipherMappingError.invalidField("fields.linkedId") }
            return value
        }
        return Field(
            name: name, value: value,
            type: try CipherWireValidation.enumValue(type ?? 0, as: FieldType.self, field: "fields.type"),
            linkedId: linkedId
        )
    }
}

private extension CipherPasswordHistoryDTO {
    func toSDKPasswordHistory() throws -> PasswordHistory {
        guard let date = ServerDateParsing.parse(lastUsedDate) else {
            throw CipherMappingError.invalidField("passwordHistory.lastUsedDate")
        }
        return PasswordHistory(password: password, lastUsedDate: date)
    }
}

extension Fido2Credential {
    func toDTO() -> CipherLoginFido2CredentialDTO {
        CipherLoginFido2CredentialDTO(
            credentialId: credentialId,
            keyType: keyType,
            keyAlgorithm: keyAlgorithm,
            keyCurve: keyCurve,
            keyValue: keyValue,
            rpId: rpId,
            rpName: rpName,
            userHandle: userHandle,
            userName: userName,
            userDisplayName: userDisplayName,
            counter: counter,
            discoverable: discoverable,
            creationDate: ServerDateParsing.format(creationDate)
        )
    }
}

private extension CipherCardDTO {
    func toSDKCard() -> Card {
        Card(
            cardholderName: cardholderName,
            expMonth: expMonth,
            expYear: expYear,
            code: code,
            brand: brand,
            number: number
        )
    }
}

private extension CipherIdentityDTO {
    func toSDKIdentity() -> Identity {
        Identity(
            title: title, firstName: firstName, middleName: middleName, lastName: lastName,
            address1: address1, address2: address2, address3: address3, city: city, state: state,
            postalCode: postalCode, country: country, company: company, email: email, phone: phone,
            ssn: ssn, username: username, passportNumber: passportNumber, licenseNumber: licenseNumber
        )
    }
}

private extension CipherSshKeyDTO {
    func toSDKSshKey() throws -> SshKey {
        guard let privateKey else { throw CipherMappingError.missingRequiredField("sshKey.privateKey") }
        return SshKey(privateKey: privateKey, publicKey: publicKey, fingerprint: keyFingerprint)
    }
}

public extension FolderResponseDTO {
    func toSDKFolder() throws -> Folder {
        guard let name else { throw CipherMappingError.missingRequiredField("name") }
        let revisionDate = try CipherWireValidation.date(revisionDate, field: "folders.revisionDate") ?? Date()
        return Folder(id: id, name: name, revisionDate: revisionDate)
    }
}

public extension CollectionResponseDTO {
    func toSDKCollection() throws -> Collection {
        guard let organizationId else { throw CipherMappingError.missingRequiredField("organizationId") }
        guard let name else { throw CipherMappingError.missingRequiredField("name") }
        return Collection(
            id: id,
            organizationId: organizationId,
            name: name,
            externalId: externalId,
            hidePasswords: hidePasswords ?? false,
            readOnly: readOnly ?? false,
            manage: manage ?? false,
            defaultUserCollectionEmail: nil,
            type: try CipherWireValidation.enumValue(type ?? 0, as: CollectionType.self, field: "collections.type")
        )
    }
}

// MARK: - SDK domain (post-encrypt) -> Request mapping

/// Mirrors the server's `CipherRequestModel` for create/update calls.
public struct CipherRequestDTO: Codable, Sendable {
    public var type: Int
    /// Required by current Bitwarden/Vaultwarden cipher-write APIs. This is the user whose key
    /// encrypted the cipher, including organization-owned ciphers.
    public var encryptedFor: String
    /// Server-side stale-write guard for updates. Creates omit it.
    public var lastKnownRevisionDate: String?
    public var organizationId: String?
    public var folderId: String?
    public var favorite: Bool
    public var reprompt: Int
    public var key: String?
    public var name: String
    public var notes: String?
    public var login: CipherLoginDTO?
    public var card: CipherCardDTO?
    public var identity: CipherIdentityDTO?
    public var secureNote: CipherSecureNoteDTO?
    public var sshKey: CipherSshKeyDTO?
    public var fields: [CipherFieldDTO]?
    public var passwordHistory: [CipherPasswordHistoryDTO]?
    public var attachments2: [String: CipherAttachmentDTO]?

    public init(cipher: Cipher, encryptedFor: String, lastKnownRevisionDate: Date? = nil) throws {
        // The response mapper marks non-roundtrip-safe SDK backing read-only. Enforce that
        // fence again at every existing CipherRequest path, including passkey writes.
        guard cipher.edit else { throw CipherMappingError.unsupportedPayload }
        guard cipher.data == nil else { throw CipherMappingError.unsupportedPayload }
        guard !encryptedFor.isEmpty else { throw CipherMappingError.missingRequiredField("encryptedFor") }
        guard let encryptedName = cipher.name else { throw CipherMappingError.missingRequiredField("name") }
        switch cipher.type {
        case .login, .secureNote, .card, .identity, .sshKey:
            break
        case .bankAccount, .driversLicense, .passport:
            throw CipherMappingError.unsupportedPayload
        }
        type = Int(cipher.type.rawValue)
        self.encryptedFor = encryptedFor
        self.lastKnownRevisionDate = lastKnownRevisionDate.map(ServerDateParsing.format)
        organizationId = cipher.organizationId
        folderId = cipher.folderId
        favorite = cipher.favorite
        reprompt = cipher.reprompt == .password ? 1 : 0
        key = cipher.key
        name = encryptedName
        notes = cipher.notes
        login = cipher.login.map {
            CipherLoginDTO(
                username: $0.username,
                password: $0.password,
                passwordRevisionDate: $0.passwordRevisionDate.map(ServerDateParsing.format),
                uris: $0.uris?.map { CipherLoginUriDTO(
                    uri: $0.uri,
                    uriChecksum: $0.uriChecksum,
                    match: $0.match.map { Int($0.rawValue) }
                ) },
                totp: $0.totp,
                autofillOnPageLoad: $0.autofillOnPageLoad,
                // Preserves any existing passkey across unrelated edits - this app has no UI to
                // create/modify passkeys, so this is always either "carried over" or absent.
                fido2Credentials: $0.fido2Credentials?.map { $0.toDTO() }
            )
        }
        card = cipher.card.map {
            CipherCardDTO(
                cardholderName: $0.cardholderName,
                brand: $0.brand,
                number: $0.number,
                expMonth: $0.expMonth,
                expYear: $0.expYear,
                code: $0.code
            )
        }
        identity = cipher.identity.map {
            CipherIdentityDTO(
                title: $0.title, firstName: $0.firstName, middleName: $0.middleName, lastName: $0.lastName,
                address1: $0.address1, address2: $0.address2, address3: $0.address3, city: $0.city, state: $0.state,
                postalCode: $0.postalCode, country: $0.country, company: $0.company, email: $0.email, phone: $0.phone,
                ssn: $0.ssn, username: $0.username, passportNumber: $0.passportNumber, licenseNumber: $0.licenseNumber
            )
        }
        secureNote = cipher.secureNote.map { CipherSecureNoteDTO(type: Int($0.type.rawValue)) }
        sshKey = cipher.sshKey.map { CipherSshKeyDTO(
            privateKey: $0.privateKey,
            publicKey: $0.publicKey,
            keyFingerprint: $0.fingerprint
        ) }
        fields = cipher.fields?.map {
            CipherFieldDTO(
                type: Int($0.type.rawValue),
                name: $0.name,
                value: $0.value,
                linkedId: $0.linkedId.map(Int.init)
            )
        }
        passwordHistory = cipher.passwordHistory?.map {
            CipherPasswordHistoryDTO(password: $0.password, lastUsedDate: ServerDateParsing.format($0.lastUsedDate))
        }
        attachments2 = try cipher.attachments.map { attachments in
            var result: [String: CipherAttachmentDTO] = [:]
            for attachment in attachments {
                guard let id = attachment.id, !id.isEmpty else {
                    throw CipherMappingError.missingRequiredField("attachments.id")
                }
                guard result[id] == nil else { throw CipherMappingError.invalidField("attachments.id") }
                guard let fileName = attachment.fileName else {
                    throw CipherMappingError.missingRequiredField("attachments.fileName")
                }
                result[id] = CipherAttachmentDTO(fileName: fileName, key: attachment.key)
            }
            return result
        }
    }
}
