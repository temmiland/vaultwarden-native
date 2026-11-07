import Domain
import Foundation
import Observation

/// Returning-account presentation. Credential/storage/SDK work is owned by the injected command.
@MainActor
@Observable
final class UnlockModel {
    private(set) var state: UnlockState
    @ObservationIgnored private let lifetime = AuthOperationLifetime()
    @ObservationIgnored private let commands: any ReturningUnlockCommands
    @ObservationIgnored private let onLogout: () -> Void
    @ObservationIgnored private let onUnlocked: (any PendingAuthentication) -> Void
    @ObservationIgnored private let onAlreadyEnabledUnlock: (any PendingAuthentication) -> Void

    init(
        commands: any ReturningUnlockCommands,
        onLogout: @escaping () -> Void,
        onUnlocked: @escaping (any PendingAuthentication) -> Void,
        onAlreadyEnabledUnlock: @escaping (any PendingAuthentication) -> Void
    ) {
        self.commands = commands; self.onLogout = onLogout
        self.onUnlocked = onUnlocked; self.onAlreadyEnabledUnlock = onAlreadyEnabledUnlock
        state = UnlockState(account: commands.account)
    }

    func receive(_ action: UnlockAction) {
        guard !lifetime.isRetired, !lifetime.isRunning else { return }
        switch action {
        case let .passwordChanged(text): state.password = text; state.errorMessage = nil
        case let .pinChanged(text): state.pin = text; state.errorMessage = nil
        }
    }

    func perform(_ effect: UnlockEffect) async {
        guard !lifetime.isRetired, !Task.isCancelled else { return }
        switch effect {
        case .appeared:
            guard !lifetime.isRunning else { return }
            let availability = commands.availability()
            state.account = commands.account
            state.isPinAvailable = availability.isPinAvailable
            state.isBiometricAvailable = availability.isBiometricAvailable
            state.biometryKind = availability.biometryKind
            state.errorMessage = availability.failure?.localizedDescription
        case .unlockWithPasswordTapped:
            await lifetime.run { await self.unlock(.password(self.state.password)) }
        case .unlockWithPinTapped:
            await lifetime.run { await self.unlock(.pin(self.state.pin)) }
        case .unlockWithBiometricsTapped:
            await lifetime.run { await self.unlock(.biometric) }
        case .logoutTapped: retire(); onLogout()
        }
    }

    func retire() {
        lifetime.retire()
        Task { await commands.revoke() }
        state.password = ""; state.pin = ""; state.errorMessage = nil
    }

    private func unlock(_ method: ReturningUnlockMethod) async {
        state.isLoading = true
        state.errorMessage = nil
        defer {
            state.isLoading = false
            if lifetime.isRetired || Task.isCancelled {
                state.password = ""; state.pin = ""; state.errorMessage = nil
            }
        }
        let result = await commands.unlock(using: method)
        state.account = commands.account
        state.isPinAvailable = state.isPinAvailable && state.account.isPinUnlockEnabled
        state.isBiometricAvailable = state.isBiometricAvailable && state.account.isBiometricUnlockEnabled
        switch result {
        case let .unlocked(pending, offerEnrollment):
            guard !lifetime.isRetired, !Task.isCancelled else { await pending.revoke(); return }
            state.password = ""; state.pin = ""; state.isLoading = false
            if offerEnrollment { onUnlocked(pending) } else { onAlreadyEnabledUnlock(pending) }
        case let .rejected(failure):
            if case .pin = method { state.pin = "" }
            if failure == .invalidEncryptionParameters { state.password = ""; state.pin = "" }
            state.errorMessage = failure.localizedDescription
        case .cancelled:
            state.password = ""; state.pin = ""
        }
    }
}
