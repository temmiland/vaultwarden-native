import Domain
import Foundation

struct EnableBiometricsState {
    let email: String
    var isBiometricAvailable: Bool = false
    var biometryKind: BiometryKind = .unknown
    var isProcessing: Bool = false
    var errorMessage: String?
}

enum EnableBiometricsEffect: Equatable {
    case appeared
    case enableTapped
    case skipTapped
}
