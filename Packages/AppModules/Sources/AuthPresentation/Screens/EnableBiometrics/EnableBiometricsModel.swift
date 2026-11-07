import Domain
import Foundation
import Observation

/// Shown once, immediately after any successful unlock (password login, 2FA login, or a returning
/// user's password re-entry) - "after the first successful password unlock in a session" per the
/// feature spec. Declining just proceeds; the account was already persisted by whichever screen
/// produced the pending capability, so declining doesn't lose anything, it just skips writing
/// the biometric-gated key to the Keychain.
@MainActor
@Observable
final class EnableBiometricsModel {
    private(set) var state: EnableBiometricsState
    @ObservationIgnored private let lifetime = AuthOperationLifetime()
    @ObservationIgnored private var context: (any PendingAuthentication)?
    @ObservationIgnored private let biometricClient: any BiometricClient
    @ObservationIgnored private let onFinished: (any PendingAuthentication) -> Void
    @ObservationIgnored private var didFinish = false

    init(
        context: any PendingAuthentication,
        biometricClient: any BiometricClient,
        onFinished: @escaping (any PendingAuthentication) -> Void
    ) {
        self.context = context
        self.biometricClient = biometricClient
        self.onFinished = onFinished
        state = EnableBiometricsState(email: context.account.email)
    }

    func perform(_ effect: EnableBiometricsEffect) async {
        guard !lifetime.isRetired, !Task.isCancelled else { return }
        switch effect {
        case .appeared:
            guard !didFinish else { return }
            switch biometricClient.availability() {
            case let .available(kind):
                state.isBiometricAvailable = true
                state.biometryKind = kind
            case .unavailable:
                state.isBiometricAvailable = false
                state.biometryKind = .unknown
            }
            await lifetime.run {
                guard let context = self.context else { return }
                await context.publishAutoFillUnlock()
            }
        case .enableTapped:
            guard !didFinish else { return }
            await lifetime.run { await self.enable() }
        case .skipTapped:
            guard !lifetime.isRunning, !state.isProcessing else { return }
            finishOnce()
        }
    }

    func retire() {
        lifetime.retire()
        context = nil
        state.errorMessage = nil
    }

    private func enable() async {
        defer {
            if lifetime.isRetired || Task.isCancelled { state.errorMessage = nil }
        }
        guard !state.isProcessing, let context else { return }
        state.isProcessing = true
        state.errorMessage = nil

        let reason = "Enable \(state.biometryKind.displayName) to unlock your vault faster next time."
        let outcome = await biometricClient.evaluate(reason: reason)
        guard !Task.isCancelled else { state.isProcessing = false; return }
        switch outcome {
        case .succeeded:
            break
        case .cancelled:
            state.isProcessing = false
            state.errorMessage = "\(state.biometryKind.displayName) wasn't confirmed."
            return
        case .unavailable:
            state.isProcessing = false
            state.errorMessage = "Biometric unlock isn't currently available. You can continue with your master password."
            return
        case .failed:
            state.isProcessing = false
            state.errorMessage = "\(state.biometryKind.displayName) couldn't be confirmed."
            return
        }

        do {
            try Task.checkCancellation()
            try await context.enableBiometricUnlock()
            state.isProcessing = false
            finishOnce()
        } catch is CancellationError {
            state.isProcessing = false
            state.errorMessage = nil
        } catch {
            state.isProcessing = false
            state.errorMessage = "Couldn't enable \(state.biometryKind.displayName) securely. Try again or use your master password."
        }
    }

    private func finishOnce() {
        guard !didFinish, !lifetime.isRetired, !Task.isCancelled, let context else { return }
        didFinish = true
        self.context = nil
        onFinished(context)
    }
}
