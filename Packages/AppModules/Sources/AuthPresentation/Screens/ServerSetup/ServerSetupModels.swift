import Foundation

struct ServerSetupState: Equatable {
    var urlText: String = ""
    var errorMessage: String?
    var isValidating: Bool = false
}

enum ServerSetupAction: Equatable {
    case urlTextChanged(String)
}

enum ServerSetupEffect: Equatable {
    case continueTapped
}
