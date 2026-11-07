import Domain
import Foundation
import Observation

/// Submits email + master password through Domain commands. On success, hands a pending
/// capability to `onUnlocked` so the
/// coordinator can offer Touch ID enrollment before the session is considered "done".
@MainActor
@Observable
final class LoginModel {
    private(set) var state: LoginState
    @ObservationIgnored private let lifetime = AuthOperationLifetime()
    @ObservationIgnored private let commands: any PasswordSignInCommands
    @ObservationIgnored private let onChangeServer: () -> Void
    @ObservationIgnored private let onTwoFactorRequired: (any AuthSecondFactorChallenge) -> Void
    @ObservationIgnored private let onUnlocked: (any PendingAuthentication) -> Void

    init(
        environment: ServerEnvironment,
        commands: any PasswordSignInCommands,
        onChangeServer: @escaping () -> Void,
        onTwoFactorRequired: @escaping (any AuthSecondFactorChallenge) -> Void,
        onUnlocked: @escaping (any PendingAuthentication) -> Void
    ) {
        self.commands = commands
        self.onChangeServer = onChangeServer
        self.onTwoFactorRequired = onTwoFactorRequired
        self.onUnlocked = onUnlocked
        state = LoginState(environment: environment)
    }

    func receive(_ action: LoginAction) {
        guard !lifetime.isRetired, !lifetime.isRunning, !state.isLoading else { return }
        switch action {
        case let .emailChanged(text):
            state.email = text
            state.errorMessage = nil
        case let .passwordChanged(text):
            state.password = text
            state.errorMessage = nil
        }
    }

    func perform(_ effect: LoginEffect) async {
        guard !lifetime.isRetired, !Task.isCancelled else { return }
        switch effect {
        case .loginTapped:
            await lifetime.run { await self.login() }
        case .useDifferentServerTapped:
            guard !lifetime.isRunning, !state.isLoading else { return }
            retire()
            onChangeServer()
        }
    }

    func retire() {
        lifetime.retire()
        state.password = ""
        state.errorMessage = nil
    }

    private func login() async {
        defer {
            state.isLoading = false
            if lifetime.isRetired || Task.isCancelled { state.password = ""; state.errorMessage = nil }
        }
        let email = state.email.normalizedEmail
        guard !email.isEmpty, !state.password.isEmpty else {
            state.errorMessage = "Enter your email and master password."
            return
        }
        state.isLoading = true
        state.errorMessage = nil
        do {
            let outcome = try await commands.signIn(
                email: email, password: state.password, environment: state.environment
            )
            switch outcome {
            case let .unlocked(pending):
                guard !lifetime.isRetired, !Task.isCancelled else { await pending.revoke(); return }
                state.password = ""
                state.isLoading = false
                onUnlocked(pending)
            case let .twoFactorRequired(challenge):
                guard !lifetime.isRetired, !Task.isCancelled else { await challenge.revoke(); return }
                state.password = ""
                state.isLoading = false
                onTwoFactorRequired(challenge)
            case let .rejected(reason):
                try Task.checkCancellation()
                state.errorMessage = reason.localizedDescription
            }
        } catch is CancellationError {
            state.password = ""
        } catch let error as AuthFlowError {
            state.errorMessage = error.localizedDescription
        } catch {
            state.errorMessage = "Couldn't sign in securely. Check the server connection and try again."
        }
    }
}
