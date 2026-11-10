import BitwardenSDKAdapter
import Domain
import Foundation
import SecurityStorage

/// Route-scoped orchestration, not UI state. MainActor serializes the existing device-local PIN
/// gate and platform prompts; SDK crypto still runs through the asynchronous adapter boundary.
@MainActor
public final class ReturningUnlockService: ReturningUnlockCommands {
    public nonisolated let id = UUID()
    public var account: ReturningUnlockAccount {
        ReturningUnlockAccount(
            session: domainAccount,
            isBiometricUnlockEnabled: stored.isBiometricUnlockEnabled,
            isPinUnlockEnabled: stored.isPinUnlockEnabled
        )
    }

    private var stored: StoredAuthAccount
    private let domainAccount: AccountSession
    private let scope: TokenScope
    private let store: AuthCredentialStore
    private let tokens: any TokenRefreshing
    private let deviceName: any DeviceNameClient
    private let biometric: any BiometricClient
    private let makeCrypto: SignInCryptographyFactory
    private let beginUnlock: @Sendable (AccountSession) async throws -> Void
    private let unlockFailed: @Sendable (AccountSession) async -> Void
    private var revoked = false
    private var completed = false
    private var busy = false
    private var activeCrypto: (any AuthCredentialCryptography)?
    private var activeProvider: AppAuthTokenProvider?
    private var kind: BiometryKind = .unknown

    public init(
        account: StoredAuthAccount,
        scope: TokenScope,
        store: AuthCredentialStore,
        tokens: any TokenRefreshing,
        deviceName: any DeviceNameClient,
        biometric: any BiometricClient,
        applicationVersion: String,
        beginUnlock: @escaping @Sendable (AccountSession) async throws -> Void,
        unlockFailed: @escaping @Sendable (AccountSession) async -> Void,
        unlockService: any VaultUnlockService = SDKVaultUnlockService(),
        makeCryptography: SignInCryptographyFactory? = nil
    ) throws {
        stored = account; domainAccount = try AccountSession(storedAccount: account)
        self.scope = scope; self.store = store; self.tokens = tokens
        self.deviceName = deviceName; self.biometric = biometric
        self.beginUnlock = beginUnlock; self.unlockFailed = unlockFailed
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

    public func revoke() async {
        revoked = true
        activeCrypto?.resource.revoke() // invalidate before actor/provider suspension
        await activeProvider?.revoke()
    }

    public func availability() -> ReturningUnlockAvailability {
        var pin = false, bio = false
        var failure: ReturningUnlockFailure?
        do {
            guard !busy, !completed else { throw CancellationError() }
            let epoch = try store.returningUnlockEpoch(requiringScope: scope)
            try validate(epoch)
            switch biometric.availability() {
            case let .available(value): kind = value; bio = stored.isBiometricUnlockEnabled
            case let .unavailable(reason):
                kind = .unknown
                if stored.isBiometricUnlockEnabled, reason == .notEnrolled,
                   try !disableBiometric(epoch) { failure = .biometricCleanupFailed }
            }
            if stored.isPinUnlockEnabled {
                do {
                    let status = try store.pinUnlockState(requiringScope: scope)
                    if status.failureCount >= AuthCredentialStore.maxPinAttempts {
                        failure = .pinLimit(cleanupConfirmed: try disablePIN(epoch), atAppearance: true)
                    } else { pin = status.isEnabled }
                } catch is CancellationError { throw CancellationError() }
                catch { failure = .pinStateFailed }
            }
        } catch { failure = .accountChanged }
        return ReturningUnlockAvailability(
            isPinAvailable: pin,
            isBiometricAvailable: bio,
            biometryKind: kind,
            failure: failure
        )
    }

    public func unlock(using method: ReturningUnlockMethod) async -> ReturningUnlockResult {
        guard !revoked, !completed, !Task.isCancelled else { return .cancelled }
        guard !busy else { return .cancelled }
        let isPIN: Bool = { if case .pin = method { return true }; return false }()
        if isPIN, !ReturningPINAttemptGate.acquire() { return .rejected(.anotherPinAttempt) }
        busy = true
        defer { busy = false; if isPIN { ReturningPINAttemptGate.release() } }
        var started = false, requested = false
        let result: ReturningUnlockResult
        do {
            let kdf: KeyDerivationParameters
            do { kdf = try stored.keyDerivationParameters }
            catch { throw ReturningUnlockFailure.invalidEncryptionParameters }
            let epoch: UUID
            do { epoch = try store.returningUnlockEpoch(requiringScope: scope) }
            catch is CancellationError { throw CancellationError() }
            catch { throw ReturningUnlockFailure.accountChanged }
            requested = true
            do { try await beginUnlock(domainAccount); started = true }
            catch is CancellationError { throw CancellationError() }
            catch { throw ReturningUnlockFailure.accountChanged }
            try validate(epoch)
            result = try await execute(method, kdf: kdf, epoch: epoch)
        } catch is CancellationError { result = .cancelled }
        catch let failure as ReturningUnlockFailure { result = .rejected(failure) }
        catch { result = .rejected(.accountChanged) }
        if !completed {
            activeCrypto?.resource.revoke()
            await activeProvider?.revoke()
            activeCrypto = nil; activeProvider = nil
            let cancelled: Bool = { if case .cancelled = result { return true }; return false }()
            if started || (requested && cancelled) { await unlockFailed(domainAccount) }
        }
        return result
    }

    private func execute(
        _ method: ReturningUnlockMethod,
        kdf: KeyDerivationParameters,
        epoch: UUID
    ) async throws -> ReturningUnlockResult {
        let key: String?
        switch method {
        case let .password(password):
            guard !password.isEmpty else { throw ReturningUnlockFailure.emptyPassword }
            key = nil
        case let .pin(pin):
            // Re-read the persistent flag/key/budget, never trust an earlier UI availability copy.
            do {
                let state = try store.pinUnlockState(requiringScope: scope)
                guard stored.isPinUnlockEnabled, state.isEnabled else { throw ReturningUnlockFailure.pinUnavailable }
                if state.failureCount >= AuthCredentialStore.maxPinAttempts {
                    throw ReturningUnlockFailure.pinLimit(cleanupConfirmed: try disablePIN(epoch), atAppearance: false)
                }
                guard !pin.isEmpty else { throw ReturningUnlockFailure.emptyPIN }
                key = try store.readPinProtectedUserKey(requiringScope: scope)
                guard key != nil else { throw ReturningUnlockFailure.pinNotSetup }
            } catch let failure as ReturningUnlockFailure { throw failure }
            catch is CancellationError { throw CancellationError() }
            catch { throw ReturningUnlockFailure.pinReadFailed }
        case .biometric:
            guard stored.isBiometricUnlockEnabled else {
                throw ReturningUnlockFailure.biometricNotSetup(kind, cleanupFailed: false)
            }
            let outcome: BiometricEvaluationResult
            do {
                let evaluation = try await biometric.performAuthenticated(reason: "Unlock your vault") {
                    try self.validate(epoch)
                    return try self.store.readBiometricUserKey(requiringScope: self.scope)
                }
                outcome = evaluation.0
                key = evaluation.1.flatMap { $0 }
            } catch KeychainStoreError.interactionCancelled { throw CancellationError() }
            catch is CancellationError { throw CancellationError() }
            catch { throw ReturningUnlockFailure.biometricReadFailed }
            try validate(epoch) // including noncooperative unavailable/failure responses
            switch outcome {
            case .succeeded: break
            case .cancelled: throw CancellationError()
            case let .unavailable(reason):
                let failed = reason == .notEnrolled ? try !disableBiometric(epoch) : false
                throw ReturningUnlockFailure.biometricUnavailable(cleanupFailed: failed)
            case .failed: throw ReturningUnlockFailure.biometricNotConfirmed(kind)
            }
            guard key != nil else {
                throw ReturningUnlockFailure.biometricNotSetup(kind, cleanupFailed: try !disableBiometric(epoch))
            }
        }
        try validate(epoch)
        let provider: AppAuthTokenProvider
        let crypto: any AuthCredentialCryptography
        do {
            provider = try store.makeTokenProvider(
                identityURL: domainAccount.environment.identityURL,
                restoringAccount: stored,
                expectedScope: scope,
                expectedPublicationEpoch: epoch,
                tokenService: tokens
            )
            activeProvider = provider
            let device = DeviceInfo(identifier: try store.deviceIdentifier(), name: deviceName.currentDeviceName())
            crypto = try makeCrypto(domainAccount.environment, device, provider)
            activeCrypto = crypto
        } catch is CancellationError { throw CancellationError() }
        catch { throw ReturningUnlockFailure.storageUnavailable(
            password: { if case .password = method { return true }; return false }()
        ) }
        do {
            switch method {
            case let .password(value):
                try await crypto.unlockPassword(
                    userID: stored.userId,
                    email: stored.email,
                    kdf: kdf,
                    password: value,
                    wrappedUserKey: stored.encryptedUserKey,
                    wrappedPrivateKey: stored.encryptedPrivateKey
                )
            case let .pin(value):
                guard let key else { throw ReturningUnlockFailure.pinNotSetup }
                try await crypto.unlockPIN(
                    userID: stored.userId,
                    email: stored.email,
                    kdf: kdf,
                    wrappedPrivateKey: stored.encryptedPrivateKey,
                    pin: value,
                    protectedUserKey: key
                )
            case .biometric:
                guard let key else { throw ReturningUnlockFailure.biometricNotSetup(kind, cleanupFailed: false) }
                try await crypto.unlockBiometric(
                    userID: stored.userId,
                    email: stored.email,
                    kdf: kdf,
                    wrappedPrivateKey: stored.encryptedPrivateKey,
                    decryptedUserKey: key
                )
            }
        } catch {
            try validate(epoch) // late non-cancellation error must not consume a PIN attempt
            if error is CancellationError { throw CancellationError() }
            switch method {
            case .password: throw ReturningUnlockFailure.incorrectPassword
            case .biometric: throw ReturningUnlockFailure.biometricCryptoFailed
            case .pin: throw try pinFailure(epoch)
            }
        }
        try validate(epoch)
        _ = try await provider.validatedScope()
        try validate(epoch)
        if case .pin = method {
            do { try store.resetPinFailureCount(requiringScope: scope, publicationEpoch: epoch) }
            catch is CancellationError { throw CancellationError() }
            catch { throw ReturningUnlockFailure.pinResetFailed(cleanupConfirmed: try disablePIN(epoch)) }
        }
        let pending = PendingAuthSession(account: domainAccount, cryptography: crypto, provider: provider, store: store)
        await pending.publishAutoFillUnlock() // same best-effort policy on every returning route
        try validate(epoch)
        try await pending.validateAuthorization()
        completed = true
        activeProvider = nil; activeCrypto = nil // the pending capability now owns them
        let offer = { if case .biometric = method { return false }; return !stored.isBiometricUnlockEnabled }()
        return .unlocked(pending, offerBiometricEnrollment: offer)
    }

    private func validate(_ epoch: UUID) throws {
        try Task.checkCancellation()
        guard !revoked, !completed else { throw CancellationError() }
        if let activeCrypto, !activeCrypto.resource.isActive { throw CancellationError() }
        _ = try store.returningUnlockEpoch(requiringScope: scope, expectedEpoch: epoch)
    }

    private func disableBiometric(_ epoch: UUID) throws -> Bool {
        try validate(epoch)
        do { try store.disableBiometricUnlock(requiringScope: scope, publicationEpoch: epoch) }
        catch is CancellationError { throw CancellationError() }
        catch { stored.isBiometricUnlockEnabled = false; return false }
        stored.isBiometricUnlockEnabled = false
        return true
    }

    private func disablePIN(_ epoch: UUID) throws -> Bool {
        try validate(epoch)
        let confirmed: Bool
        do { confirmed = try store.disablePinUnlock(requiringScope: scope, publicationEpoch: epoch) }
        catch is CancellationError { throw CancellationError() }
        catch { stored.isPinUnlockEnabled = false; return false }
        stored.isPinUnlockEnabled = false
        return confirmed
    }

    private func pinFailure(_ epoch: UUID) throws -> ReturningUnlockFailure {
        let failures: Int
        do { failures = try store.recordPinFailure(requiringScope: scope, publicationEpoch: epoch) }
        catch is CancellationError { throw CancellationError() }
        catch { return .pinCounterFailed(cleanupConfirmed: try disablePIN(epoch)) }
        let remaining = AuthCredentialStore.maxPinAttempts - failures
        if remaining <= 0 { return .pinLimit(cleanupConfirmed: try disablePIN(epoch), atAppearance: false) }
        return .incorrectPIN(remaining: remaining)
    }
}

/// Preserves the existing app-wide gate across overlapping returning route instances.
@MainActor
private enum ReturningPINAttemptGate {
    private static var active = false
    static func acquire() -> Bool { guard !active else { return false }; active = true; return true }
    static func release() { active = false }
}
