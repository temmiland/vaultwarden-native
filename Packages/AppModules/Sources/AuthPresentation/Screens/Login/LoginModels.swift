import Domain
import Foundation

struct LoginState: Equatable {
    let environment: ServerEnvironment
    var email: String = ""
    var password: String = ""
    var isLoading: Bool = false
    var errorMessage: String?
}

enum LoginAction: Equatable {
    case emailChanged(String)
    case passwordChanged(String)
}

enum LoginEffect: Equatable {
    case loginTapped
    case useDifferentServerTapped
}
