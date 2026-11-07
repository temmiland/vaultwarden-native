import Foundation

struct TwoFactorState {
    let availableProviders: [Int]
    var code: String = ""
    var remember: Bool = false
    var isLoading: Bool = false
    var errorMessage: String?

    /// The 2FA providers the server offered, in the same order it returned them.
    var providers: [TwoFactorProviderType] {
        availableProviders.compactMap(TwoFactorProviderType.init(rawValue:))
    }
}

enum TwoFactorAction: Equatable {
    case codeChanged(String)
    case rememberToggled(Bool)
}

enum TwoFactorEffect: Equatable {
    case submitTapped
    case cancelTapped
}
