import Domain

public extension VaultItemKind {
    var displayName: String {
        switch self {
        case .login: "Login"
        case .secureNote: "Secure Note"
        case .card: "Card"
        case .identity: "Identity"
        case .sshKey: "SSH Key"
        case .bankAccount: "Bank Account"
        case .driversLicense: "Driver's License"
        case .passport: "Passport"
        case .unknown: "Unknown Item"
        }
    }

    var symbolName: String {
        switch self {
        case .login: "person.badge.key.fill"
        case .secureNote: "note.text"
        case .card: "creditcard.fill"
        case .identity: "person.text.rectangle.fill"
        case .sshKey: "key.fill"
        case .bankAccount, .driversLicense, .passport, .unknown: "doc.fill"
        }
    }
}
