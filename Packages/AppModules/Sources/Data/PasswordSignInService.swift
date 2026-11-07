import BitwardenSDKAdapter
import Domain
import Foundation

public typealias SignInCryptographyFactory = @Sendable (ServerEnvironment, DeviceInfo, AppAuthTokenProvider) throws -> any AuthCredentialCryptography

/// Owns the fresh password flow. Presentation supplies user inputs and renders Domain results;
/// credentials, wire payloads, cryptography and persistence never enter route contexts.
public struct PasswordSignInService: PasswordSignInCommands {
    private let store: AuthCredentialStore
    private let prelogin: any PreloginService
    private let tokens: any IdentityTokenService
    private let deviceName: any DeviceNameClient
    private let makeCrypto: SignInCryptographyFactory

    public init(
        store: AuthCredentialStore,
        prelogin: any PreloginService,
        tokens: any IdentityTokenService,
        deviceName: any DeviceNameClient,
        applicationVersion: String,
        unlockService: any VaultUnlockService = SDKVaultUnlockService(),
        makeCryptography: SignInCryptographyFactory? = nil
    ) {
        self.store = store
        self.prelogin = prelogin
        self.tokens = tokens
        self.deviceName = deviceName
        makeCrypto = makeCryptography ?? { environment, device, provider in
            SDKAuthCredentialCryptography(
                resource: SDKSessionClient(
                    tokenProvider: SDKManagedTokenAdapter(accessToken: { await provider.getAccessToken() }),
                    settings: SDKClientFactory.makeSettings(
                        identityURL: environment.identityURL,
                        apiURL: environment.apiURL,
                        deviceIdentifier: device.identifier,
                        applicationVersion: applicationVersion
                    )
                ),
                unlockService: unlockService
            )
        }
    }

    public func signIn(email: String, password: String, environment: ServerEnvironment) async throws -> PasswordSignInResult {
        try Task.checkCancellation()
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !email.isEmpty, !password.isEmpty else { throw PasswordSignInRejection.invalidCredentials }
        let identifier = try store.deviceIdentifier()
        let provider = try store.makeTokenProvider(identityURL: environment.identityURL, tokenService: tokens)
        var crypto: (any AuthCredentialCryptography)?
        do {
            // Authority is captured before even the device-name hop, not after HTTP/crypto.
            let device = DeviceInfo(identifier: identifier, name: await deviceName.currentDeviceName())
            try await provider.validateFreshLoginAuthority()
            let kdf = try await prelogin.fetchKdf(email: email, identityURL: environment.identityURL)
            try await provider.validateFreshLoginAuthority()
            let resource = try makeCrypto(environment, device, provider)
            crypto = resource
            let hash = try await resource.hashPassword(email: email, password: password, kdf: kdf)
            try await provider.validateFreshLoginAuthority()
            let result = try await tokens.requestToken(
                identityURL: environment.identityURL,
                username: email,
                passwordHash: hash,
                device: device,
                twoFactor: nil
            )
            try await provider.validateFreshLoginAuthority()
            switch result {
            case let .success(response):
                return .unlocked(try await AuthPasswordUnlockFlow.complete(
                    response: response,
                    email: email,
                    kdf: kdf,
                    password: password,
                    environment: environment,
                    crypto: resource,
                    provider: provider,
                    store: store
                ))
            case let .twoFactorRequired(providers):
                return .twoFactorRequired(PasswordSecondFactorChallenge(
                    email: email,
                    password: password,
                    hash: hash,
                    kdf: kdf,
                    environment: environment,
                    device: device,
                    availableProviders: providers,
                    crypto: resource,
                    provider: provider,
                    store: store,
                    tokens: tokens
                ))
            case let .failure(message):
                resource.resource.revoke()
                await provider.revoke()
                return .rejected(Self.rejection(message))
            }
        } catch {
            crypto?.resource.revoke()
            await provider.revoke()
            throw error
        }
    }

    static func rejection(_ message: String) -> PasswordSignInRejection {
        // Wire/transport already returns safe text. A whitelist also prevents injected or future
        // diagnostics becoming a Domain/UI error verbatim.
        switch message {
        case "Username or password is incorrect.": .invalidCredentials
        case "The server is busy. Please try again shortly.": .busy
        case "The server is temporarily unavailable. Please try again.": .unavailable
        case "The server returned an unrecognized response.": .invalidResponse
        default: .failed
        }
    }
}

enum AuthPasswordUnlockFlow {
    static func complete(
        response: TokenSuccessResponse,
        email: String,
        kdf: KeyDerivationParameters,
        password: String,
        environment: ServerEnvironment,
        crypto: any AuthCredentialCryptography,
        provider: AppAuthTokenProvider,
        store: AuthCredentialStore
    ) async throws -> PendingAuthSession {
        try await provider.validateFreshLoginAuthority()
        guard let refresh = response.refreshToken, !refresh.isEmpty,
              response.expiresIn > 0 else { throw AuthFlowError.missingCryptoState }
        guard let userID = JWTPayload.subject(from: response.accessToken), !userID.isEmpty else {
            throw AuthFlowError.invalidAccessToken
        }
        let account = try response.makeStoredAccount(
            userID: userID,
            email: email,
            serverBaseURL: environment.baseURL,
            parameters: kdf
        )
        try await crypto.unlockPassword(
            userID: userID,
            email: email,
            kdf: kdf,
            password: password,
            wrappedUserKey: account.encryptedUserKey,
            wrappedPrivateKey: account.encryptedPrivateKey
        )
        try await provider.validateFreshLoginAuthority()
        try await provider.storeSession(
            account: account,
            tokens: TokenPair(
                accessToken: response.accessToken,
                refreshToken: refresh,
                expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn))
            )
        )
        return PendingAuthSession(
            account: try AccountSession(storedAccount: account),
            cryptography: crypto,
            provider: provider,
            store: store
        )
    }
}
