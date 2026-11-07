import Domain
import Foundation

struct SettingsState: Equatable {
    let email: String
    let serverBaseURL: URL

    var isPinUnlockEnabled: Bool = false
    var pinInput: String = ""
    var pinConfirmInput: String = ""
    var pinErrorMessage: String?
    var isSavingPin: Bool = false

    var timeoutPreference: VaultTimeoutPreference = .default
    var isSavingTimeoutPreference = false
    var timeoutErrorMessage: String?

    var devices: [RegisteredDevice] = []
    var deviceIDPendingRevocation: String?
    var revokingDeviceIDs: Set<String> = []
    var isLoadingDevices: Bool = false
    var devicesErrorMessage: String?
    var openURLErrorMessage: String?
}

enum SettingsAction: Equatable {
    case pinInputChanged(String)
    case pinConfirmInputChanged(String)
    case openURLErrorDismissed
    case deviceRevocationConfirmationDismissed
}

enum SettingsEffect: Equatable {
    case appeared
    case enablePinTapped
    case disablePinTapped
    case openWebVaultTapped
    case lockNowTapped
    case logoutTapped
    case timeoutDurationChanged(VaultTimeoutPreference.Duration)
    case timeoutActionChanged(VaultTimeoutPreference.Action)
    case refreshDevicesTapped
    case revokeDeviceTapped(id: String)
    case confirmDeviceRevocation
}
