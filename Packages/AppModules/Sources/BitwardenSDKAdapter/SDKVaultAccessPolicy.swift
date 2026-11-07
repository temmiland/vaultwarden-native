import BitwardenSdk

/// Access boundary for the existing client, which has no session-bound master-password re-prompt
/// grant. An unlocked SDK client or a device biometric check is not such a grant. Keep protected
/// items fail-closed; never clear their flag or accept a caller-supplied authorization Boolean.
/// Collection permissions and session revocation must still be checked by the owning runtime.
public enum SDKVaultAccessPolicy {
    public static func allowsUnpromptedSecretAccess(_ cipher: CipherView) -> Bool {
        cipher.reprompt == .none && cipher.viewPassword
            && cipher.deletedDate == nil && cipher.archivedDate == nil
    }

    public static func allowsUnpromptedSecretAccess(_ cipher: Cipher) -> Bool {
        cipher.reprompt == .none && cipher.viewPassword
            && cipher.deletedDate == nil && cipher.archivedDate == nil
    }

    /// Reject unknown nonzero flags before SDK conversion as well as the known password flag.
    /// Missing fields retain the existing wire-format defaults, not a fabricated verification.
    public static func allowsUnpromptedSecretAccess(_ cipher: CipherResponseDTO) -> Bool {
        (cipher.reprompt ?? 0) == 0 && cipher.viewPassword != false
            && cipher.deletedDate == nil && cipher.archivedDate == nil
    }

    public static func isEligibleForAutoFill(_ cipher: CipherView) -> Bool {
        allowsUnpromptedSecretAccess(cipher) && cipher.id?.isEmpty == false
            && cipher.type == .login && cipher.login != nil
    }

    public static func isEligibleForAutoFill(_ cipher: CipherResponseDTO) -> Bool {
        allowsUnpromptedSecretAccess(cipher) && cipher.id?.isEmpty == false
            && cipher.type == Int(CipherType.login.rawValue) && cipher.login != nil
    }

    /// Revalidate a retained selection against the current encrypted cache, including old caches.
    /// Ambiguous IDs and changed revisions are not interchangeable authorization targets.
    public static func isCurrentAutoFillItem(_ view: CipherView, in ciphers: [CipherResponseDTO]) -> Bool {
        guard isEligibleForAutoFill(view) else { return false }
        let matches = ciphers.filter { $0.id == view.id }
        guard matches.count == 1, let current = matches.first else { return false }
        return isCurrentAutoFillItem(view, matching: current)
    }

    /// Indexed callers establish ID uniqueness once, then compare one DTO without rescanning the vault.
    public static func isCurrentAutoFillItem(_ view: CipherView, matching current: CipherResponseDTO) -> Bool {
        guard isEligibleForAutoFill(view), isEligibleForAutoFill(current), current.id == view.id,
              let encrypted = try? current.toSDKCipher(), encrypted.revisionDate == view.revisionDate else {
            return false
        }
        return true
    }
}
