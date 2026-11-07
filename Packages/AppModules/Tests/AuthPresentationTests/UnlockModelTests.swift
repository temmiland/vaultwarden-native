@testable import AuthPresentation
@testable import Data
import Domain
import Foundation
import Testing

@MainActor
@Suite(.serialized)
struct UnlockModelTests {
    private func makeAccount(
        isBiometricUnlockEnabled: Bool = false,
        isPinUnlockEnabled: Bool = false,
        kdfType: Int? = 0,
        kdfIterations: Int? = 600_000
    ) -> StoredAuthAccount {
        StoredAuthAccount(
            userId: "user-1",
            email: "user@example.com",
            serverBaseURL: URL(string: "https://vault.example.com")!,
            kdfType: kdfType,
            kdfIterations: kdfIterations,
            kdfMemory: nil,
            kdfParallelism: nil,
            encryptedUserKey: "encrypted-user-key",
            encryptedPrivateKey: "encrypted-private-key",
            isBiometricUnlockEnabled: isBiometricUnlockEnabled,
            isPinUnlockEnabled: isPinUnlockEnabled
        )
    }

    private func makeDependencies(
        unlockService: MockVaultUnlockService = MockVaultUnlockService(),
        sharedKeychain: MockKeychainService = MockKeychainService(),
        keychain: MockKeychainService = MockKeychainService(),
        biometricClient: MockBiometricClient? = nil,
        deviceNameClient: MockDeviceNameClient? = nil
    ) -> (AuthDependencies, AuthCredentialStore) {
        let keychainStore = AuthCredentialStore(
            keychain: keychain,
            sharedKeychain: sharedKeychain,
            sharedLockPolicy: .processOnly
        )
        do {
            try keychainStore.saveSession(account: makeAccount(), tokens: TokenPair(
                accessToken: "fixture-access", refreshToken: "fixture-refresh", expiresAt: .distantFuture
            ))
        } catch { Issue.record("Could not seed the returning-session fixture") }
        let httpClient = MockHTTPClient()
        let dependencies = AuthDependencies(
            httpClient: httpClient,
            keychainStore: keychainStore,
            preloginService: DefaultPreloginService(httpClient: httpClient),
            tokenService: MockIdentityTokenService(),
            unlockService: unlockService,
            biometricClient: biometricClient ?? MockBiometricClient(),
            deviceNameClient: deviceNameClient ?? MockDeviceNameClient()
        )
        return (dependencies, keychainStore)
    }

    private func makeModel(
        account: StoredAuthAccount,
        dependencies: AuthDependencies,
        onLogout: @escaping () -> Void = {},
        beginUnlock: @escaping @Sendable (AccountSession) async throws -> Void = { _ in },
        unlockFailed: @escaping @Sendable (AccountSession) async -> Void = { _ in },
        onUnlocked: @escaping (any PendingAuthentication) -> Void = { _ in },
        onAlreadyEnabledUnlock: @escaping (any PendingAuthentication) -> Void = { _ in }
    ) -> UnlockModel {
        do {
            if try dependencies.keychainStore.loadSession() == nil {
                try dependencies.keychainStore.saveSession(account: account, tokens: TokenPair(
                    accessToken: "fixture-access", refreshToken: "fixture-refresh", expiresAt: .distantFuture
                ))
            } else {
                try dependencies.keychainStore.save(account: account)
            }
        } catch { Issue.record("Could not seed the returning-account fixture") }
        let scope: TokenScope = {
            do {
                guard let session = try dependencies.keychainStore.loadSession() else {
                    throw CancellationError()
                }
                return session.scope
            } catch {
                Issue.record("Could not read the returning-account fixture scope")
                return TokenScope(account: TokenAccountIdentity(
                    userID: account.userId,
                    serverBaseURL: account.serverBaseURL
                ))
            }
        }()
        return UnlockModel(
            commands: try! dependencies.returningUnlockCommands(
                account: account,
                scope: scope,
                beginUnlock: beginUnlock,
                unlockFailed: unlockFailed
            ),
            onLogout: onLogout,
            onUnlocked: onUnlocked,
            onAlreadyEnabledUnlock: onAlreadyEnabledUnlock
        )
    }

    @Test(arguments: [-1, 0, Int(UInt32.max) + 1])
    func invalidSavedKDFDeniesEveryUnlockPathWithoutConsumingPinBudget(_ count: Int) async throws {
        let unlock = MockVaultUnlockService()
        let biometric = MockBiometricClient()
        let (dependencies, store) = makeDependencies(unlockService: unlock, biometricClient: biometric)
        let account = makeAccount(isBiometricUnlockEnabled: true, isPinUnlockEnabled: true, kdfIterations: count)
        let model = makeModel(
            account: account,
            dependencies: dependencies,
            beginUnlock: { _ in Issue.record("Invalid KDF must not start repository unlock") },
            unlockFailed: { _ in Issue.record("No unlock transition was started") }
        )
        let scope = try #require(try store.loadSession()?.scope)
        try store.savePinProtectedUserKey("fixture-protected-pin-key")
        try store.saveBiometricUserKey("fixture-biometric-key")
        _ = try store.recordPinFailure(requiringScope: scope)
        _ = try store.recordPinFailure(requiringScope: scope)
        await model.perform(.appeared)
        for effect in [UnlockEffect.unlockWithPasswordTapped, .unlockWithPinTapped, .unlockWithBiometricsTapped] {
            model.receive(.passwordChanged("fixture-password"))
            model.receive(.pinChanged("1234"))
            await model.perform(effect)
            #expect(model.state.password.isEmpty && model.state.pin.isEmpty)
            #expect(model.state.errorMessage == AuthFlowError.invalidEncryptionParameters.localizedDescription)
            #expect(!model.state.isLoading)
        }
        #expect(unlock.calls.isEmpty && biometric.evaluationCount == 0)
        #expect(try store.pinUnlockState(requiringScope: scope).failureCount == 2)
        #expect(try store.readPinProtectedUserKey(requiringScope: scope) == "fixture-protected-pin-key")
        #expect(try store.loadAccount()?.isBiometricUnlockEnabled == true)
        #expect(try store.loadAccount()?.isPinUnlockEnabled == true)
    }

    @Test
    func unknownSavedKDFCannotBecomeAnIncorrectPassword() async {
        let unlock = MockVaultUnlockService()
        let (dependencies, _) = makeDependencies(unlockService: unlock)
        let model = makeModel(account: makeAccount(kdfType: 2), dependencies: dependencies)
        model.receive(.passwordChanged("fixture-password"))
        await model.perform(.unlockWithPasswordTapped)
        #expect(unlock.calls.isEmpty)
        #expect(model.state.password.isEmpty)
        #expect(model.state.errorMessage == AuthFlowError.invalidEncryptionParameters.localizedDescription)
    }

    @Test
    func simultaneousUnlockSubmissionIsIgnoredWhileStateTransitionSuspends() async throws {
        let (dependencies, _) = makeDependencies()
        let gate = UnlockAttemptGate()
        let model = makeModel(
            account: makeAccount(),
            dependencies: dependencies,
            beginUnlock: { _ in await gate.pause() }
        )

        let firstAttempt = Task { await model.perform(.unlockWithPasswordTapped) }
        await gate.waitUntilPaused()
        await model.perform(.unlockWithPasswordTapped)

        #expect(await gate.beginCount == 1)
        #expect(model.state.isLoading)
        await gate.resume()
        await firstAttempt.value
        #expect(model.state.isLoading == false)
    }

    @Test
    func pinSubmissionIsSerializedAcrossModelInstances() async throws {
        let unlockService = MockVaultUnlockService()
        let serviceGate = PinUnlockServiceGate()
        unlockService.beforePinUnlock = { await serviceGate.pauseUntilReleased() }
        let (dependencies, keychainStore) = makeDependencies(unlockService: unlockService)
        try keychainStore.savePinProtectedUserKey("stored-pin-protected-user-key")
        let account = makeAccount(isPinUnlockEnabled: true)
        let first = makeModel(account: account, dependencies: dependencies)
        let second = makeModel(account: account, dependencies: dependencies)
        await first.perform(.appeared)
        await second.perform(.appeared)
        first.receive(.pinChanged("1111"))
        second.receive(.pinChanged("2222"))

        let firstAttempt = Task { await first.perform(.unlockWithPinTapped) }
        await serviceGate.waitUntilStarted()
        await second.perform(.unlockWithPinTapped)
        await serviceGate.release()
        await firstAttempt.value

        let pinCalls = unlockService.calls.filter { call in
            if case .pin = call { return true }
            return false
        }
        #expect(pinCalls.count == 1)
        #expect(second.state.pin.isEmpty)
        #expect(second.state.errorMessage == "Another PIN unlock is already in progress. Try again.")
    }

    @Test
    func retiringDuringNoncooperativePinCryptoFailureDoesNotConsumeAttemptBudget() async throws {
        let service = MockVaultUnlockService()
        let gate = PinUnlockServiceGate()
        service.beforePinUnlock = { await gate.pauseUntilReleased() }
        service.errorToThrow = MockUnlockServiceError()
        let (dependencies, store) = makeDependencies(unlockService: service)
        try store.savePinProtectedUserKey("fixture-protected-pin-key")
        let model = makeModel(account: makeAccount(isPinUnlockEnabled: true), dependencies: dependencies)
        let scope = try #require(try store.loadSession()).scope
        await model.perform(.appeared)
        model.receive(.pinChanged("1234"))
        let submission = Task { await model.perform(.unlockWithPinTapped) }
        await gate.waitUntilStarted()

        model.retire()
        await gate.release()
        await submission.value

        #expect(try store.pinUnlockState(requiringScope: scope).failureCount == 0)
        #expect(try store.pinUnlockState(requiringScope: scope).isEnabled)
        #expect(model.state.pin.isEmpty)
        #expect(model.state.errorMessage == nil)
    }

    @Test
    func appearedShowsPinFieldOnlyWhenAccountEnabledAndKeyPresent() async throws {
        let (dependencies, keychainStore) = makeDependencies()
        try keychainStore.savePinProtectedUserKey("pin-protected-user-key")
        let model = makeModel(account: makeAccount(isPinUnlockEnabled: true), dependencies: dependencies)

        await model.perform(.appeared)

        #expect(model.state.isPinAvailable == true)
    }

    @Test
    func appearedHidesPinFieldWhenKeyMissingDespiteFlagSet() async {
        let (dependencies, _) = makeDependencies()
        let model = makeModel(account: makeAccount(isPinUnlockEnabled: true), dependencies: dependencies)

        await model.perform(.appeared)

        #expect(model.state.isPinAvailable == false)
    }

    @Test
    func unavailableBiometricsClearsThePersistedEnrollmentFlag() async throws {
        let biometricClient = MockBiometricClient()
        biometricClient.availabilityResult = .unavailable(.notEnrolled)
        let keychainStore = AuthCredentialStore(
            keychain: MockKeychainService(),
            sharedKeychain: MockKeychainService(),
            sharedLockPolicy: .processOnly
        )
        let httpClient = MockHTTPClient()
        let dependencies = AuthDependencies(
            httpClient: httpClient,
            keychainStore: keychainStore,
            preloginService: DefaultPreloginService(httpClient: httpClient),
            tokenService: MockIdentityTokenService(),
            unlockService: MockVaultUnlockService(),
            biometricClient: biometricClient,
            deviceNameClient: MockDeviceNameClient()
        )
        let account = makeAccount(isBiometricUnlockEnabled: true)
        try keychainStore.save(account: account)
        try keychainStore.saveBiometricUserKey("decrypted-user-key")
        let model = makeModel(account: account, dependencies: dependencies)

        await model.perform(.appeared)

        #expect(model.state.isBiometricAvailable == false)
        #expect(model.state.account.isBiometricUnlockEnabled == false)
        #expect(try keychainStore.loadAccount()?.isBiometricUnlockEnabled == false)
        #expect(try keychainStore.readBiometricUserKey() == nil)
    }

    @Test
    func biometricCryptoFailureUsesAStableUserMessage() async throws {
        let unlockService = MockVaultUnlockService()
        unlockService.errorToThrow = MockUnlockServiceError()
        let biometricClient = MockBiometricClient()
        let (dependencies, keychainStore) = makeDependencies(
            unlockService: unlockService,
            biometricClient: biometricClient
        )
        let account = makeAccount(isBiometricUnlockEnabled: true)
        try keychainStore.save(account: account)
        try keychainStore.saveBiometricUserKey("decrypted-user-key")
        let model = makeModel(account: account, dependencies: dependencies)

        await model.perform(.unlockWithBiometricsTapped)

        #expect(
            model.state.errorMessage == "Couldn't unlock with biometric data. Use your master password or try again."
        )
    }

    @Test
    func missingBiometricKeyAfterAuthenticationClearsEnrollmentForRecovery() async throws {
        let biometricClient = MockBiometricClient()
        biometricClient.availabilityResult = .available(.touchID)
        biometricClient.evaluationResult = .succeeded
        let keychainStore = AuthCredentialStore(
            keychain: MockKeychainService(),
            sharedKeychain: MockKeychainService(),
            sharedLockPolicy: .processOnly
        )
        let httpClient = MockHTTPClient()
        let dependencies = AuthDependencies(
            httpClient: httpClient,
            keychainStore: keychainStore,
            preloginService: DefaultPreloginService(httpClient: httpClient),
            tokenService: MockIdentityTokenService(),
            unlockService: MockVaultUnlockService(),
            biometricClient: biometricClient,
            deviceNameClient: MockDeviceNameClient()
        )
        let account = makeAccount(isBiometricUnlockEnabled: true)
        try keychainStore.save(account: account)
        let model = makeModel(account: account, dependencies: dependencies)

        await model.perform(.unlockWithBiometricsTapped)

        #expect(model.state.account.isBiometricUnlockEnabled == false)
        #expect(try keychainStore.loadAccount()?.isBiometricUnlockEnabled == false)
        #expect(model.state.errorMessage?.contains("isn't set up") == true)
    }

    @Test
    func cancellingBiometricUnlockKeepsEnrollmentAndOffersPasswordFallback() async throws {
        let biometricClient = MockBiometricClient()
        biometricClient.availabilityResult = .available(.touchID)
        biometricClient.evaluationResult = .cancelled
        let unlockService = MockVaultUnlockService()
        let (dependencies, keychainStore) = makeDependencies(
            unlockService: unlockService,
            biometricClient: biometricClient
        )
        try keychainStore.saveBiometricUserKey("decrypted-user-key")
        let model = makeModel(account: makeAccount(isBiometricUnlockEnabled: true), dependencies: dependencies)

        await model.perform(.unlockWithBiometricsTapped)

        #expect(model.state.errorMessage == nil)
        #expect(try keychainStore.readBiometricUserKey() == "decrypted-user-key")
        #expect(unlockService.calls.isEmpty)
    }

    @Test
    func cancellingKeychainBiometricPromptKeepsEnrollmentAndReturnsQuietly() async throws {
        let biometricClient = MockBiometricClient()
        biometricClient.availabilityResult = .available(.touchID)
        biometricClient.evaluationResult = .succeeded
        let keychain = MockKeychainService()
        let (dependencies, keychainStore) = makeDependencies(
            keychain: keychain,
            biometricClient: biometricClient
        )
        try keychainStore.saveBiometricUserKey("decrypted-user-key")
        keychain.accountsCancellingReads = ["auth.biometricUserKey"]
        let model = makeModel(account: makeAccount(isBiometricUnlockEnabled: true), dependencies: dependencies)

        await model.perform(.unlockWithBiometricsTapped)

        #expect(model.state.errorMessage == nil)
        #expect(model.state.account.isBiometricUnlockEnabled)
        #expect(try keychainStore.loadAccount()?.isBiometricUnlockEnabled == true)
    }

    @Test
    func unlockWithEmptyPinShowsErrorWithoutCallingUnlockService() async {
        let unlockService = MockVaultUnlockService()
        let (dependencies, _) = makeDependencies(unlockService: unlockService)
        let model = makeModel(account: makeAccount(isPinUnlockEnabled: true), dependencies: dependencies)

        await model.perform(.appeared)
        await model.perform(.unlockWithPinTapped)

        #expect(model.state.errorMessage != nil)
        #expect(unlockService.calls.isEmpty)
    }

    @Test
    func unlockWithPinButNoStoredKeyShowsSetupError() async {
        let unlockService = MockVaultUnlockService()
        let (dependencies, _) = makeDependencies(unlockService: unlockService)
        let model = makeModel(account: makeAccount(isPinUnlockEnabled: true), dependencies: dependencies)
        await model.perform(.appeared)
        model.receive(.pinChanged("1234"))

        await model.perform(.unlockWithPinTapped)

        #expect(model.state.errorMessage == "PIN unlock isn't available. Use your master password or try again.")
        #expect(unlockService.calls.isEmpty)
    }

    @Test
    func correctPinUnlocksAndRoutesToOnUnlockedWhenBiometricsNotYetEnabled() async throws {
        let unlockService = MockVaultUnlockService()
        let (dependencies, keychainStore) = makeDependencies(unlockService: unlockService)
        try keychainStore.savePinProtectedUserKey("stored-pin-protected-user-key")

        var unlockedContext: (any PendingAuthentication)?
        var alreadyEnabledCalled = false
        let model = makeModel(
            account: makeAccount(isBiometricUnlockEnabled: false, isPinUnlockEnabled: true),
            dependencies: dependencies,
            onUnlocked: { unlockedContext = $0 },
            onAlreadyEnabledUnlock: { _ in alreadyEnabledCalled = true }
        )
        await model.perform(.appeared)
        model.receive(.pinChanged("4321"))

        await model.perform(.unlockWithPinTapped)

        #expect(model.state.errorMessage == nil)
        #expect(model.state.isLoading == false)
        #expect(unlockedContext != nil)
        #expect(alreadyEnabledCalled == false)
        #expect(unlockService.calls == [.pin(pin: "4321", pinProtectedUserKey: "stored-pin-protected-user-key")])
    }

    @Test
    func correctPinUnlocksAndRoutesToOnAlreadyEnabledUnlockWhenBiometricsEnabled() async throws {
        let unlockService = MockVaultUnlockService()
        let (dependencies, keychainStore) = makeDependencies(unlockService: unlockService)
        try keychainStore.savePinProtectedUserKey("stored-pin-protected-user-key")

        var alreadyEnabledContext: (any PendingAuthentication)?
        let model = makeModel(
            account: makeAccount(isBiometricUnlockEnabled: true, isPinUnlockEnabled: true),
            dependencies: dependencies,
            onUnlocked: { _ in Issue.record("shouldn't offer to enable biometrics again") },
            onAlreadyEnabledUnlock: { alreadyEnabledContext = $0 }
        )
        await model.perform(.appeared)
        model.receive(.pinChanged("4321"))

        await model.perform(.unlockWithPinTapped)

        #expect(alreadyEnabledContext != nil)
    }

    @Test
    func incorrectPinShowsErrorAndStopsLoading() async throws {
        let unlockService = MockVaultUnlockService()
        unlockService.errorToThrow = MockUnlockServiceError()
        let (dependencies, keychainStore) = makeDependencies(unlockService: unlockService)
        try keychainStore.savePinProtectedUserKey("stored-pin-protected-user-key")

        let model = makeModel(account: makeAccount(isPinUnlockEnabled: true), dependencies: dependencies)
        await model.perform(.appeared)
        model.receive(.pinChanged("0000"))

        await model.perform(.unlockWithPinTapped)

        #expect(model.state.errorMessage == "Incorrect PIN. 4 attempts left.")
        #expect(model.state.isLoading == false)
        // The wrong PIN must not linger in published state for a shoulder-surfer to read back.
        #expect(model.state.pin.isEmpty)
    }

    /// A PIN is short enough to enumerate, and a wrong one fails locally against the SDK with no
    /// server involved - so nothing rate-limits guessing except this counter.
    @Test
    func exhaustingPinAttemptsDisablesPinUnlockEntirely() async throws {
        let unlockService = MockVaultUnlockService()
        unlockService.errorToThrow = MockUnlockServiceError()
        let (dependencies, keychainStore) = makeDependencies(unlockService: unlockService)
        try keychainStore.savePinProtectedUserKey("stored-pin-protected-user-key")

        let model = makeModel(account: makeAccount(isPinUnlockEnabled: true), dependencies: dependencies)
        await model.perform(.appeared)
        #expect(model.state.isPinAvailable)

        for _ in 0 ..< AuthCredentialStore.maxPinAttempts {
            model.receive(.pinChanged("0000"))
            await model.perform(.unlockWithPinTapped)
        }

        #expect(model.state.isPinAvailable == false)
        #expect(model.state.account.isPinUnlockEnabled == false)
        #expect(try keychainStore.readPinProtectedUserKey() == nil)
        #expect(model.state.errorMessage?.contains("Too many incorrect PINs") == true)
    }

    @Test
    func pinUnlockExplainsWhenAttemptAndRevocationWritesBothFail() async throws {
        let unlockService = MockVaultUnlockService()
        unlockService.errorToThrow = MockUnlockServiceError()
        let keychain = MockKeychainService()
        let (dependencies, keychainStore) = makeDependencies(unlockService: unlockService, keychain: keychain)
        try keychainStore.savePinProtectedUserKey("stored-pin-protected-user-key")

        let model = makeModel(account: makeAccount(isPinUnlockEnabled: true), dependencies: dependencies)
        await model.perform(.appeared)
        keychain.accountsFailingWrites = ["auth.pinFailureCount", PrivateAuthSessionStore.key]
        keychain.accountsFailingRemoval = ["auth.pinProtectedUserKey"]
        model.receive(.pinChanged("0000"))

        await model.perform(.unlockWithPinTapped)

        #expect(model.state.isPinAvailable == false)
        #expect(model.state.errorMessage?.contains("do not retry PIN unlock") == true)
        #expect(try keychainStore.readPinProtectedUserKey() == "stored-pin-protected-user-key")
    }

    @Test
    func aCorrectPinClearsTheFailureCountSoTheBudgetDoesNotCarryOver() async throws {
        let unlockService = MockVaultUnlockService()
        let (dependencies, keychainStore) = makeDependencies(unlockService: unlockService)
        try keychainStore.savePinProtectedUserKey("stored-pin-protected-user-key")

        unlockService.errorToThrow = MockUnlockServiceError()
        let model = makeModel(account: makeAccount(isPinUnlockEnabled: true), dependencies: dependencies)
        await model.perform(.appeared)
        model.receive(.pinChanged("0000"))
        await model.perform(.unlockWithPinTapped)
        #expect(try keychainStore.pinFailureCount() == 1)

        unlockService.errorToThrow = nil
        model.receive(.pinChanged("4321"))
        await model.perform(.unlockWithPinTapped)

        #expect(try keychainStore.pinFailureCount() == 0)
    }

    @Test
    func cancelledPinCryptoDoesNotConsumeTheAttemptBudget() async throws {
        let service = MockVaultUnlockService()
        service.errorToThrow = CancellationError()
        let (dependencies, store) = makeDependencies(unlockService: service)
        try store.savePinProtectedUserKey("stored-pin-protected-user-key")
        let model = makeModel(account: makeAccount(isPinUnlockEnabled: true), dependencies: dependencies)
        await model.perform(.appeared)
        model.receive(.pinChanged("1234"))

        await model.perform(.unlockWithPinTapped)

        #expect(try store.pinFailureCount() == 0)
        #expect(model.state.pin.isEmpty)
        #expect(model.state.errorMessage == nil)
        #expect(model.state.isPinAvailable)
    }

    @Test
    func acceptedPinWithCounterResetFailureDisablesPersistedPinEnrollment() async throws {
        let unlockService = MockVaultUnlockService()
        let keychain = MockKeychainService()
        let (dependencies, keychainStore) = makeDependencies(unlockService: unlockService, keychain: keychain)
        try keychainStore.savePinProtectedUserKey("stored-pin-protected-user-key")

        let model = makeModel(account: makeAccount(isPinUnlockEnabled: true), dependencies: dependencies)
        await model.perform(.appeared)
        keychain.accountsFailingWrites = ["auth.pinFailureCount"]
        model.receive(.pinChanged("4321"))

        await model.perform(.unlockWithPinTapped)

        #expect(model.state.isPinAvailable == false)
        #expect(model.state.account.isPinUnlockEnabled == false)
        #expect(try keychainStore.loadAccount()?.isPinUnlockEnabled == false)
        #expect(try keychainStore.readPinProtectedUserKey() == nil)
        #expect(model.state.errorMessage?.contains("PIN unlock is disabled") == true)
    }

    // MARK: - AutoFill key re-sharing
    //
    // Locking revokes the AutoFill extension's shared key, so *every* unlock route has to put it
    // back. The biometric route is the dangerous one: it skips the enable-biometrics screen, which
    // is where the re-share used to live - so a locked vault stayed un-autofillable until the user
    // did a full logout and login.

    @Test
    func unlockingWithBiometricsResharesTheKeyWithTheAutofillExtension() async throws {
        let unlockService = MockVaultUnlockService()
        let (dependencies, keychainStore) = makeDependencies(unlockService: unlockService)
        try keychainStore.save(account: makeAccount(isBiometricUnlockEnabled: true))
        try keychainStore.saveBiometricUserKey("decrypted-user-key")
        // Simulate the state right after a lock: the shared key is gone.
        try keychainStore.lockSession()
        #expect(keychainStore.loadSharedAutofillUserKeyForTesting() == nil)

        let model = makeModel(
            account: makeAccount(isBiometricUnlockEnabled: true),
            dependencies: dependencies
        )
        await model.perform(.unlockWithBiometricsTapped)

        #expect(keychainStore.loadSharedAutofillUserKeyForTesting() != nil)
        #expect(keychainStore.loadSharedAccountInfoForTesting() != nil)
    }

    @Test
    func unlockingWithThePasswordResharesTheKeyWithTheAutofillExtension() async throws {
        let unlockService = MockVaultUnlockService()
        let (dependencies, keychainStore) = makeDependencies(unlockService: unlockService)
        try keychainStore.save(account: makeAccount(isBiometricUnlockEnabled: true))
        try keychainStore.lockSession()

        let model = makeModel(
            account: makeAccount(isBiometricUnlockEnabled: true),
            dependencies: dependencies
        )
        model.receive(.passwordChanged("correct horse"))
        await model.perform(.unlockWithPasswordTapped)

        #expect(keychainStore.loadSharedAutofillUserKeyForTesting() != nil)
    }

    @Test
    func unlockingWithAPinResharesTheKeyWithTheAutofillExtension() async throws {
        let unlockService = MockVaultUnlockService()
        let (dependencies, keychainStore) = makeDependencies(unlockService: unlockService)
        try keychainStore.save(account: makeAccount(isPinUnlockEnabled: true))
        try keychainStore.savePinProtectedUserKey("stored-pin-protected-user-key")
        try keychainStore.lockSession()

        let model = makeModel(account: makeAccount(isPinUnlockEnabled: true), dependencies: dependencies)
        await model.perform(.appeared)
        model.receive(.pinChanged("4321"))
        await model.perform(.unlockWithPinTapped)

        #expect(keychainStore.loadSharedAutofillUserKeyForTesting() != nil)
    }

    /// The account record is what `SharedAccountInfo` is built from, so a locked-then-unlocked
    /// vault must also leave the extension able to reach the right server.
    @Test
    func resharedAccountInfoCarriesTheServerURL() async throws {
        let unlockService = MockVaultUnlockService()
        let (dependencies, keychainStore) = makeDependencies(unlockService: unlockService)
        try keychainStore.save(account: makeAccount(isBiometricUnlockEnabled: true))
        try keychainStore.saveBiometricUserKey("decrypted-user-key")

        let model = makeModel(
            account: makeAccount(isBiometricUnlockEnabled: true),
            dependencies: dependencies
        )
        await model.perform(.unlockWithBiometricsTapped)

        #expect(keychainStore.loadSharedAccountInfoForTesting()?.serverBaseURL != nil)
    }

    /// Saving a passkey needs the shared tokens, and `lockSession()` revokes them. Unlocking a
    /// returning session obtains no *new* tokens (it reads the ones already stored), so unless the
    /// unlock path explicitly puts the shared copy back, passkey saving reports a locked vault
    /// forever - while the app sits there plainly unlocked.
    @Test
    func unlockingRestoresTheSharedTokensAfterALock() async throws {
        let sharedKeychain = MockKeychainService()
        let unlockService = MockVaultUnlockService()
        let (dependencies, keychainStore) = makeDependencies(
            unlockService: unlockService, sharedKeychain: sharedKeychain
        )
        try keychainStore.save(account: makeAccount(isBiometricUnlockEnabled: true))
        try keychainStore.saveBiometricUserKey("decrypted-user-key")
        try keychainStore.save(tokens: TokenPair(
            accessToken: "access", refreshToken: "refresh", expiresAt: Date(timeIntervalSince1970: 2_000_000)
        ))

        try keychainStore.lockSession()
        #expect(try SharedTokenStore(keychain: sharedKeychain, lockPolicy: .processOnly).load() == nil)

        let model = makeModel(
            account: makeAccount(isBiometricUnlockEnabled: true),
            dependencies: dependencies
        )
        await model.perform(.unlockWithBiometricsTapped)

        #expect(try SharedTokenStore(keychain: sharedKeychain, lockPolicy: .processOnly).load()?.accessToken == "access")
    }

    @Test
    func unlockingWithAPasswordAlsoRestoresTheSharedTokens() async throws {
        let sharedKeychain = MockKeychainService()
        let (dependencies, keychainStore) = makeDependencies(sharedKeychain: sharedKeychain)
        try keychainStore.save(account: makeAccount(isBiometricUnlockEnabled: true))
        try keychainStore.save(tokens: TokenPair(
            accessToken: "access", refreshToken: "refresh", expiresAt: Date(timeIntervalSince1970: 2_000_000)
        ))
        try keychainStore.lockSession()

        let model = makeModel(
            account: makeAccount(isBiometricUnlockEnabled: true),
            dependencies: dependencies
        )
        model.receive(.passwordChanged("correct horse"))
        await model.perform(.unlockWithPasswordTapped)

        #expect(try SharedTokenStore(keychain: sharedKeychain, lockPolicy: .processOnly).load()?.accessToken == "access")
    }

    /// The biometric key is the one item an attacker with Keychain read access would want most,
    /// so it must carry the OS-enforced gate rather than relying on the app asking politely.
    @Test
    func biometricUserKeyIsStoredBehindAnOSEnforcedBiometricGate() throws {
        let keychain = MockKeychainService()
        let store = AuthCredentialStore(
            keychain: keychain,
            sharedKeychain: MockKeychainService(),
            sharedLockPolicy: .processOnly
        )

        try store.saveBiometricUserKey("decrypted-user-key")

        #expect(keychain.protections["auth.biometricUserKey"] == .biometryGated)
    }
}

private actor UnlockAttemptGate {
    private(set) var beginCount = 0
    private var didPause = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var pauseWaiters: [CheckedContinuation<Void, Never>] = []

    func pause() async {
        beginCount += 1
        didPause = true
        for waiter in pauseWaiters { waiter.resume() }
        pauseWaiters = []
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilPaused() async {
        if didPause { return }
        await withCheckedContinuation { pauseWaiters.append($0) }
    }

    func resume() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor PinUnlockServiceGate {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func pauseUntilReleased() async {
        if !started {
            started = true
            let waiters = startWaiters
            startWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
