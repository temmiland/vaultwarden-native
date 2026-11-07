import Foundation

extension String {
    /// Bitwarden clients trim and lowercase the email before using it as the prelogin lookup key,
    /// the KDF salt, and the `hashPassword` input - the server does the same normalization, so this
    /// must match exactly or the derived hash won't match what the server expects.
    var normalizedEmail: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
