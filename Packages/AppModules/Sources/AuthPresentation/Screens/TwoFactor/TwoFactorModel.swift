import Domain
import Foundation
import Observation

/// Handles the TOTP (authenticator app) path of two-factor login. Email and WebAuthn are listed in
/// the UI so the user knows the server offered them, but attempting to use them shows a "not yet
/// supported" message instead of a working challenge - see the final report for follow-up scope.
@MainActor
@Observable
final class TwoFactorModel {
    private(set) var state: TwoFactorState
    @ObservationIgnored private let lifetime = AuthOperationLifetime()
    @ObservationIgnored private var context: (any AuthSecondFactorChallenge)?
    @ObservationIgnored private let onCancel: () -> Void
    @ObservationIgnored private let onUnlocked: (any PendingAuthentication) -> Void

    init(
        context: any AuthSecondFactorChallenge,
        onCancel: @escaping () -> Void,
        onUnlocked: @escaping (any PendingAuthentication) -> Void
    ) {
        self.context = context
        self.onCancel = onCancel
        self.onUnlocked = onUnlocked
        state = TwoFactorState(availableProviders: context.availableProviders)
    }

    func receive(_ action: TwoFactorAction) {
        guard !lifetime.isRetired, !lifetime.isRunning, !state.isLoading else { return }
        switch action {
        case let .codeChanged(text):
            state.code = text
            state.errorMessage = nil
        case let .rememberToggled(value):
            state.remember = value
        }
    }

    func perform(_ effect: TwoFactorEffect) async {
        guard !lifetime.isRetired, !Task.isCancelled else { return }
        switch effect {
        case .submitTapped:
            await lifetime.run { await self.submit() }
        case .cancelTapped:
            guard !lifetime.isRunning, !state.isLoading else { return }
            retire()
            onCancel()
        }
    }

    func retire() {
        lifetime.retire()
        if let context { Task { await context.revoke() } }
        context = nil
        state.code = ""
        state.errorMessage = nil
    }

    private func submit() async {
        defer {
            state.isLoading = false
            if lifetime.isRetired || Task.isCancelled {
                state.code = ""
                state.errorMessage = nil
            }
        }
        guard !state.isLoading else { return }
        let code = state.code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            state.errorMessage = "Enter your authenticator code."
            return
        }

        state.isLoading = true
        state.errorMessage = nil

        guard let context else { state.isLoading = false; return }
        do {
            let outcome = try await context.submitTOTP(code: code, remember: state.remember)
            switch outcome {
            case let .unlocked(pending):
                guard !lifetime.isRetired, !Task.isCancelled else { await pending.revoke(); return }
                state.isLoading = false
                state.code = ""
                onUnlocked(pending)
            case .twoFactorRequired:
                state.isLoading = false
                state.errorMessage = PasswordSignInRejection.invalidTwoFactor.localizedDescription
            case let .rejected(reason):
                try Task.checkCancellation()
                state.isLoading = false
                state.errorMessage = reason.localizedDescription
            }
        } catch is CancellationError {
            await context.revoke()
            state.isLoading = false
            state.code = ""
            return
        } catch let error as AuthFlowError {
            state.isLoading = false
            state.code = ""
            state.errorMessage = error.localizedDescription
        } catch {
            state.isLoading = false
            state.code = ""
            state.errorMessage = "Couldn't verify the code. Check the server connection and try again."
        }
    }
}
