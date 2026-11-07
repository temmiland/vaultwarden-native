import BitwardenSDKAdapter
import Domain
import Foundation

/// Password/hash are private retry material, not observable route data. Successful completion
/// clears them and transfers the resource; a late revoke of this challenge cannot kill its successor.
actor PasswordSecondFactorChallenge: AuthSecondFactorChallenge, CustomStringConvertible, CustomDebugStringConvertible {
    nonisolated let id: UUID
    nonisolated let environment: ServerEnvironment
    nonisolated let availableProviders: [Int]
    private struct Inputs { let email: String; let password: String; let hash: String }
    private var inputs: Inputs?
    private let kdf: KeyDerivationParameters
    private let device: DeviceInfo
    private let crypto: any AuthCredentialCryptography
    private let provider: AppAuthTokenProvider
    private let store: AuthCredentialStore
    private let tokens: any IdentityTokenService
    private var submitting = false
    private var transferred = false

    init(
        email: String,
        password: String,
        hash: String,
        kdf: KeyDerivationParameters,
        environment: ServerEnvironment,
        device: DeviceInfo,
        availableProviders: [Int],
        crypto: any AuthCredentialCryptography,
        provider: AppAuthTokenProvider,
        store: AuthCredentialStore,
        tokens: any IdentityTokenService
    ) {
        id = provider.id
        self.environment = environment
        self.availableProviders = availableProviders
        inputs = Inputs(email: email, password: password, hash: hash)
        self.kdf = kdf; self.device = device; self.crypto = crypto
        self.provider = provider; self.store = store; self.tokens = tokens
    }

    func submitTOTP(code: String, remember: Bool) async throws -> PasswordSignInResult {
        guard let inputs else { throw CancellationError() }
        guard !submitting else { throw AuthRepositoryError.invalidTransition }
        guard availableProviders.contains(0), !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .rejected(.invalidTwoFactor)
        }
        submitting = true
        defer { submitting = false }
        try await provider.validateFreshLoginAuthority()
        let result = try await tokens.requestToken(
            identityURL: environment.identityURL,
            username: inputs.email,
            passwordHash: inputs.hash,
            device: device,
            twoFactor: TwoFactorSubmission(
                code: code.trimmingCharacters(in: .whitespacesAndNewlines),
                provider: 0,
                remember: remember
            )
        )
        try await provider.validateFreshLoginAuthority()
        switch result {
        case let .success(response):
            let pending = try await AuthPasswordUnlockFlow.complete(
                response: response,
                email: inputs.email,
                kdf: kdf,
                password: inputs.password,
                environment: environment,
                crypto: crypto,
                provider: provider,
                store: store
            )
            self.inputs = nil
            transferred = true
            return .unlocked(pending)
        case .twoFactorRequired: return .rejected(.invalidTwoFactor)
        case let .failure(message): return .rejected(PasswordSignInService.rejection(message))
        }
    }

    func revoke() async {
        guard !transferred else { return }
        inputs = nil
        crypto.resource.revoke()
        await provider.revoke()
    }

    nonisolated var description: String { "PasswordSecondFactorChallenge(<redacted>)" }
    nonisolated var debugDescription: String { description }
}
