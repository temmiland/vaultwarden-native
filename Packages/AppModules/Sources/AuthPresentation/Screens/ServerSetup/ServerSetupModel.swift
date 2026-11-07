import Domain
import Foundation
import Observation

@MainActor
@Observable
final class ServerSetupModel {
    private(set) var state: ServerSetupState
    @ObservationIgnored private let lifetime = AuthOperationLifetime()
    @ObservationIgnored private let onContinue: (ServerEnvironment) -> Void

    init(onContinue: @escaping (ServerEnvironment) -> Void) {
        self.onContinue = onContinue
        state = ServerSetupState()
    }

    func receive(_ action: ServerSetupAction) {
        guard !lifetime.isRetired else { return }
        switch action {
        case let .urlTextChanged(text):
            state.urlText = text
            state.errorMessage = nil
        }
    }

    func perform(_ effect: ServerSetupEffect) async {
        guard !lifetime.isRetired, !Task.isCancelled else { return }
        switch effect {
        case .continueTapped:
            validateAndContinue()
        }
    }

    func retire() {
        lifetime.retire()
        state.urlText = ""
        state.errorMessage = nil
    }

    /// Non-empty, well-formed HTTPS URL with a host. Debug builds may use a literal loopback HTTP
    /// address for a local Vaultwarden instance; release builds never permit cleartext transport.
    private func validateAndContinue() {
        let trimmed = state.urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state.errorMessage = "Enter your Vaultwarden server URL."
            return
        }

        var candidate = trimmed
        if !candidate.contains("://") {
            candidate = "https://" + candidate
        }

        guard let url = URL(string: candidate), ServerURLPolicy.isPermitted(url),
              let environment = try? ServerEnvironment(baseURL: url)
        else {
            state.errorMessage = "Enter a valid HTTPS server URL."
            return
        }

        state.errorMessage = nil
        onContinue(environment)
    }
}
