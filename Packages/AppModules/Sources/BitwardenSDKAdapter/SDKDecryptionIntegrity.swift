import BitwardenSdk

public enum SDKDecryptionIntegrityError: Error, Sendable, Equatable {
    case incompleteCipher
}

/// The pinned SDK's legacy decryptor can turn field failures into nil/empty values instead of
/// throwing. Refuse that projection before it can be edited, cached or used for AutoFill. This
/// checks presence/cardinality, NOT cryptographic authenticity (that remains the SDK's job).
/// It never formats/logs ciphertext, plaintext or item identity and creates no JSON secret copy.
public enum SDKDecryptionIntegrity {
    public static func validate(_ cipher: Cipher, decrypted view: CipherView) throws {
        guard cipher.id == view.id, cipher.type == view.type,
              cipher.organizationId == view.organizationId,
              cipher.collectionIds == view.collectionIds,
              cipher.name == nil || !view.name.isEmpty else { throw SDKDecryptionIntegrityError.incompleteCipher }
        try retained(cipher.notes, view.notes)
        try retained(cipher.login, view.login)
        try retained(cipher.card, view.card)
        try retained(cipher.identity, view.identity)
        try retained(cipher.sshKey, view.sshKey)
        try retained(cipher.secureNote, view.secureNote)
        try retained(cipher.bankAccount, view.bankAccount)
        try retained(cipher.driversLicense, view.driversLicense)
        try retained(cipher.passport, view.passport)
        try retained(cipher.localData, view.localData)
        if let original = cipher.login, let result = view.login {
            try retained(original.username, result.username)
            try retained(original.password, result.password)
            try retained(original.totp, result.totp)
            try sameCount(original.uris, result.uris)
            for (source, decoded) in zip(original.uris ?? [], result.uris ?? []) {
                try retained(source.uri, decoded.uri)
                try retained(source.uriChecksum, decoded.uriChecksum)
                guard source.match == decoded.match else { throw SDKDecryptionIntegrityError.incompleteCipher }
            }
            // These credentials intentionally remain encrypted until the dedicated FIDO call.
            try sameCount(original.fido2Credentials, result.fido2Credentials)
        }
        if let original = cipher.card, let result = view.card {
            for (source, decoded) in [
                (original.cardholderName, result.cardholderName), (original.number, result.number),
                (original.brand, result.brand), (original.code, result.code),
                (original.expMonth, result.expMonth), (original.expYear, result.expYear),
            ] { try retained(source, decoded) }
        }
        if let original = cipher.identity, let result = view.identity {
            for (source, decoded) in [
                (original.title, result.title), (original.firstName, result.firstName),
                (original.middleName, result.middleName), (original.lastName, result.lastName),
                (original.address1, result.address1), (original.address2, result.address2),
                (original.address3, result.address3), (original.city, result.city),
                (original.state, result.state), (original.postalCode, result.postalCode),
                (original.country, result.country), (original.company, result.company),
                (original.email, result.email), (original.phone, result.phone), (original.ssn, result.ssn),
                (original.username, result.username), (original.passportNumber, result.passportNumber),
                (original.licenseNumber, result.licenseNumber),
            ] { try retained(source, decoded) }
        }
        if let original = cipher.sshKey, let result = view.sshKey {
            guard !result.privateKey.isEmpty else { throw SDKDecryptionIntegrityError.incompleteCipher }
            try retained(original.publicKey, result.publicKey)
            try retained(original.fingerprint, result.fingerprint)
        }
        try sameCount(cipher.fields, view.fields)
        for (source, decoded) in zip(cipher.fields ?? [], view.fields ?? []) {
            try retained(source.name, decoded.name)
            try retained(source.value, decoded.value)
            guard source.type == decoded.type, source.linkedId == decoded.linkedId else {
                throw SDKDecryptionIntegrityError.incompleteCipher
            }
        }
        try sameCount(cipher.passwordHistory, view.passwordHistory)
        // Attachments have a separate explicit failure list and existing read-only policy. A
        // failed attachment must not hide otherwise readable passwords or bypass that policy.
    }

    private static func retained<Source, Result>(_ source: Source?, _ result: Result?) throws {
        guard source == nil || result != nil else { throw SDKDecryptionIntegrityError.incompleteCipher }
    }

    private static func sameCount<Source, Result>(_ source: [Source]?, _ result: [Result]?) throws {
        guard (source?.count ?? 0) == (result?.count ?? 0) else { throw SDKDecryptionIntegrityError.incompleteCipher }
    }
}
