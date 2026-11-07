import Foundation

/// Bitwarden's two-factor provider type codes, as returned in the `connect/token` 2FA-required
/// error body's `TwoFactorProviders` array. Only `.authenticator` (TOTP) is actually implemented
/// here; the rest are surfaced in the UI as "not yet supported" placeholders.
enum TwoFactorProviderType: Int, CaseIterable, Sendable {
    case authenticator = 0
    case email = 1
    case duo = 2
    case yubiKey = 3
    case u2f = 4
    case remember = 5
    case organizationDuo = 6
    case webAuthn = 7

    var displayName: String {
        switch self {
        case .authenticator: "Authenticator app"
        case .email: "Email"
        case .duo: "Duo"
        case .yubiKey: "YubiKey"
        case .u2f: "U2F Security Key"
        case .remember: "Remembered device"
        case .organizationDuo: "Duo (Organization)"
        case .webAuthn: "WebAuthn"
        }
    }

    /// Whether this app can actually complete a challenge for this provider yet.
    var isSupported: Bool {
        self == .authenticator
    }
}
