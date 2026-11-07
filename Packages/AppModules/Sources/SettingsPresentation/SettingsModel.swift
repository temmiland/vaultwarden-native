import Domain
import Foundation
import Observation

/// Drives the single Settings screen: account info display, PIN unlock enrollment (via
/// a session-scoped Domain port), vault-timeout preference editing (via a Domain repository), opening
/// the web vault for everything this app doesn't implement yet, lock/logout, and best-effort device
/// management.
@MainActor
@Observable
final class SettingsModel {
    private let account: AccountSession
    private let checkSessionAccess: @Sendable () throws -> Void
    private let sessionStates: @Sendable () async -> AsyncStream<SessionState>
    private let settingsRepository: any SettingsRepository
    private let timeoutSettings: any VaultTimeoutSettingsRepository
    private let pinSettings: any PinUnlockSettings
    private let openURLClient: any OpenURLClient
    private let onLockNow: () -> Void
    private let onLogout: () -> Void
    @ObservationIgnored
    private var sessionObserver: Task<Void, Never>?
    @ObservationIgnored
    private var deviceOperationGeneration: UInt64 = 0

    deinit { sessionObserver?.cancel() }

    init(
        account: AccountSession,
        checkSessionAccess: @escaping @Sendable () throws -> Void,
        sessionStates: @escaping @Sendable () async -> AsyncStream<SessionState>,
        settingsRepository: any SettingsRepository,
        timeoutSettings: any VaultTimeoutSettingsRepository,
        pinSettings: any PinUnlockSettings,
        openURLClient: any OpenURLClient,
        onLockNow: @escaping () -> Void,
        onLogout: @escaping () -> Void
    ) {
        self.account = account
        self.checkSessionAccess = checkSessionAccess
        self.sessionStates = sessionStates
        self.settingsRepository = settingsRepository
        self.timeoutSettings = timeoutSettings
        self.pinSettings = pinSettings
        self.openURLClient = openURLClient
        self.onLockNow = onLockNow
        self.onLogout = onLogout
        state = SettingsState(
            email: account.email,
            serverBaseURL: account.environment.baseURL,
            timeoutPreference: .default
        )
        sessionObserver = Task { [weak self, sessionStates] in
            let states = await sessionStates()
            for await state in states {
                if Task.isCancelled { return }
                if case .unlocked = state { continue }
                self?.invalidateSession()
                return
            }
        }
    }

    var state: SettingsState

    func receive(_ action: SettingsAction) {
        guard hasSessionAccess() else { return }
        switch action {
        case let .pinInputChanged(text):
            state.pinInput = text
            state.pinErrorMessage = nil
        case let .pinConfirmInputChanged(text):
            state.pinConfirmInput = text
            state.pinErrorMessage = nil
        case .openURLErrorDismissed:
            state.openURLErrorMessage = nil
        case .deviceRevocationConfirmationDismissed:
            state.deviceIDPendingRevocation = nil
        }
    }

    func perform(_ effect: SettingsEffect) async {
        guard hasSessionAccess() else { return }
        switch effect {
        case .appeared:
            await loadTimeoutPreference()
            await refreshPinState()
            await refreshDevices()
        case .enablePinTapped:
            await enablePin()
        case .disablePinTapped:
            do {
                try await pinSettings.remove()
                state.isPinUnlockEnabled = false
                state.pinInput = ""
                state.pinConfirmInput = ""
                state.pinErrorMessage = nil
            } catch {
                state.pinErrorMessage = "Couldn't safely disable PIN unlock. Try again or use your master password."
                state.isPinUnlockEnabled = (try? await pinSettings.isEnabled()) ?? state.isPinUnlockEnabled
            }
        case .openWebVaultTapped:
            // Intentional escape hatch: Admin Console, Provider Portal, Reports/Watchtower, and
            // organization policy administration aren't implemented natively - the web vault covers
            // all of them until (if ever) this app grows its own screens for them.
            do {
                try await openURLClient.open(account.environment.webVaultURL)
                state.openURLErrorMessage = nil
            } catch {
                state.openURLErrorMessage = "Couldn't open the web vault. Check that a browser is available and try again."
            }
        case .lockNowTapped:
            onLockNow()
        case .logoutTapped:
            onLogout()
        case let .timeoutDurationChanged(duration):
            await saveTimeoutPreference(duration: duration, action: state.timeoutPreference.action)
        case let .timeoutActionChanged(action):
            await saveTimeoutPreference(duration: state.timeoutPreference.duration, action: action)
        case .refreshDevicesTapped:
            await refreshDevices()
        case let .revokeDeviceTapped(id):
            guard state.devices.contains(where: { $0.id == id }), !state.revokingDeviceIDs.contains(id) else { return }
            state.deviceIDPendingRevocation = id
        case .confirmDeviceRevocation:
            guard let id = state.deviceIDPendingRevocation else { return }
            state.deviceIDPendingRevocation = nil
            await revokeDevice(id: id)
        }
        _ = hasSessionAccess()
    }

    private func hasSessionAccess() -> Bool {
        do { try checkSessionAccess(); return true }
        catch { invalidateSession(); return false }
    }

    private func invalidateSession() {
        deviceOperationGeneration &+= 1
        state.pinInput = ""
        state.pinConfirmInput = ""
        state.devices = []
        state.isSavingPin = false
        state.isLoadingDevices = false
        state.deviceIDPendingRevocation = nil
        state.revokingDeviceIDs = []
    }

    private func enablePin() async {
        guard !state.pinInput.isEmpty else {
            state.pinErrorMessage = "Enter a PIN."
            return
        }
        guard state.pinInput == state.pinConfirmInput else {
            state.pinErrorMessage = "PINs don't match."
            return
        }

        state.isSavingPin = true
        state.pinErrorMessage = nil
        do {
            try await pinSettings.enroll(pin: state.pinInput)
            state.isSavingPin = false
            state.isPinUnlockEnabled = true
            state.pinInput = ""
            state.pinConfirmInput = ""
        } catch {
            state.isSavingPin = false
            state.pinErrorMessage = "Couldn't safely enable PIN unlock. Make sure the vault is unlocked and try again."
        }
    }

    private func refreshPinState() async {
        do {
            state.isPinUnlockEnabled = try await pinSettings.isEnabled()
            state.pinErrorMessage = nil
        } catch {
            state.isPinUnlockEnabled = false
            state.pinErrorMessage = "Couldn't safely read PIN unlock settings. Try again or use your master password."
        }
    }

    private func refreshDevices() async {
        deviceOperationGeneration &+= 1
        let generation = deviceOperationGeneration
        state.isLoadingDevices = true
        state.devicesErrorMessage = nil
        do {
            let devices = try await settingsRepository.fetchDevices()
            guard hasSessionAccess(), generation == deviceOperationGeneration else { return }
            state.devices = devices
            state.isLoadingDevices = false
        } catch let error as SettingsRepositoryError {
            guard hasSessionAccess(), generation == deviceOperationGeneration else { return }
            state.isLoadingDevices = false
            if case let .server(statusCode) = error {
                state.devicesErrorMessage = "Couldn't load devices (server response \(statusCode))."
            } else {
                state.devicesErrorMessage = "Couldn't load devices. Check the server connection and try again."
            }
        } catch {
            guard hasSessionAccess(), generation == deviceOperationGeneration else { return }
            state.isLoadingDevices = false
            state.devicesErrorMessage = (error as? SessionAuthorizationError)?.errorDescription ?? "Couldn't load devices. Check the server connection and try again."
        }
    }

    private func loadTimeoutPreference() async {
        do {
            state.timeoutPreference = try timeoutSettings.load()
            state.timeoutErrorMessage = nil
        } catch {
            state.timeoutErrorMessage = "Couldn't load the vault timeout setting. The saved value was left unchanged."
        }
    }

    private func saveTimeoutPreference(duration: VaultTimeoutPreference.Duration, action: VaultTimeoutPreference.Action) async {
        guard !state.isSavingTimeoutPreference else { return }
        state.isSavingTimeoutPreference = true
        defer { state.isSavingTimeoutPreference = false }
        let preference = VaultTimeoutPreference(duration: duration, action: action)
        do {
            try timeoutSettings.save(preference)
            state.timeoutPreference = preference
            state.timeoutErrorMessage = nil
        } catch {
            state.timeoutErrorMessage = "Couldn't save the vault timeout setting. Your previous value is still active."
        }
    }

    private func revokeDevice(id: String) async {
        guard !state.revokingDeviceIDs.contains(id), state.devices.contains(where: { $0.id == id }) else { return }
        deviceOperationGeneration &+= 1
        let generation = deviceOperationGeneration
        state.isLoadingDevices = false
        state.devicesErrorMessage = nil
        state.revokingDeviceIDs.insert(id)
        defer { state.revokingDeviceIDs.remove(id) }
        do {
            try await settingsRepository.revokeDevice(id: id)
            guard hasSessionAccess() else { return }
            state.devices.removeAll { $0.id == id }
            deviceOperationGeneration &+= 1
            state.isLoadingDevices = false
            state.devicesErrorMessage = nil
        } catch let error as SettingsRepositoryError {
            guard hasSessionAccess(), generation == deviceOperationGeneration else { return }
            if case let .server(statusCode) = error {
                state.devicesErrorMessage = [404, 405].contains(statusCode)
                    ? "This device was not found, or the server does not support revoking individual devices. Check device management in the web vault."
                    : "Couldn't revoke device (server response \(statusCode))."
            } else {
                state.devicesErrorMessage = "Couldn't revoke device. Check the server connection and try again."
            }
        } catch {
            guard hasSessionAccess(), generation == deviceOperationGeneration else { return }
            state.devicesErrorMessage = (error as? SessionAuthorizationError)?.errorDescription ?? "Couldn't revoke device. Check the server connection and try again."
        }
    }
}
