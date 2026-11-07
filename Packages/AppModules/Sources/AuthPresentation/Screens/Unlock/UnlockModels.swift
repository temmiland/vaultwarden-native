import Domain
import Foundation

struct UnlockState: Equatable {
    /// `var`, not `let`: exhausting the PIN attempt limit turns PIN unlock off, which has to be
    /// reflected here so the screen stops offering the PIN field for the rest of this session.
    var account: ReturningUnlockAccount
    var password: String = ""
    var pin: String = ""
    var isLoading: Bool = false
    var errorMessage: String?
    var isBiometricAvailable: Bool = false
    var biometryKind: BiometryKind = .unknown
    var isPinAvailable: Bool = false
}

enum UnlockAction: Equatable {
    case passwordChanged(String)
    case pinChanged(String)
}

enum UnlockEffect: Equatable {
    case appeared
    case unlockWithBiometricsTapped
    case unlockWithPasswordTapped
    case unlockWithPinTapped
    case logoutTapped
}
