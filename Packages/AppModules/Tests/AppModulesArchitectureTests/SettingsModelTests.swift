import Domain
import Foundation
@testable import SettingsPresentation
import Testing

@MainActor
@Suite
struct SettingsModelTests {
    private func makeAccount(email: String = "user@example.com") throws -> AccountSession {
        let environment = try ServerEnvironment(baseURL: URL(string: "https://vault.example.com")!)
        return AccountSession(accountID: AccountID(rawValue: "user-1"), email: email, environment: environment)
    }

    private func makeModel(
        account: AccountSession? = nil,
        accessGate: SessionAccessGate = SessionAccessGate(),
        settingsRepository: MockDeviceManagementService = MockDeviceManagementService(),
        timeoutSettings: MockTimeoutSettingsRepository = MockTimeoutSettingsRepository(),
        pinSettings: MockPinUnlockSettings = MockPinUnlockSettings(),
        openURLClient: MockOpenURLClient? = nil,
        onLockNow: @escaping () -> Void = {},
        onLogout: @escaping () -> Void = {}
    ) throws -> SettingsModel {
        let account = try account ?? makeAccount()
        return SettingsModel(
            account: account,
            checkSessionAccess: { try accessGate.check() },
            sessionStates: {
                AsyncStream { continuation in
                    continuation.yield(.unlocked(account))
                    continuation.finish()
                }
            },
            settingsRepository: settingsRepository,
            timeoutSettings: timeoutSettings,
            pinSettings: pinSettings,
            openURLClient: openURLClient ?? MockOpenURLClient(),
            onLockNow: onLockNow,
            onLogout: onLogout
        )
    }

    @Test
    func initialStateReflectsSessionAccountInfo() throws {
        let processor = try makeModel(account: makeAccount(email: "someone@example.com"))

        #expect(processor.state.email == "someone@example.com")
        #expect(processor.state.serverBaseURL == URL(string: "https://vault.example.com")!)
    }

    @Test
    func webVaultActionUsesTheInjectedOpenURLClient() async throws {
        let openURLClient = MockOpenURLClient()
        let account = try makeAccount()
        let processor = try makeModel(account: account, openURLClient: openURLClient)

        await processor.perform(.openWebVaultTapped)

        #expect(openURLClient.openedURLs == [account.environment.webVaultURL])
        #expect(processor.state.openURLErrorMessage == nil)
    }

    @Test
    func failedWebVaultOpenIsPresentedAsARecoverableError() async throws {
        let openURLClient = MockOpenURLClient()
        openURLClient.shouldFail = true
        let processor = try makeModel(openURLClient: openURLClient)

        await processor.perform(.openWebVaultTapped)

        #expect(processor.state.openURLErrorMessage?.contains("Couldn't open the web vault") == true)
        processor.receive(.openURLErrorDismissed)
        #expect(processor.state.openURLErrorMessage == nil)
    }

    @Test
    func enablePinWithEmptyInputShowsErrorWithoutAttemptingEnrollment() async throws {
        let processor = try makeModel()

        await processor.perform(.enablePinTapped)

        #expect(processor.state.pinErrorMessage == "Enter a PIN.")
        #expect(processor.state.isPinUnlockEnabled == false)
    }

    @Test
    func enablePinWithMismatchedConfirmationShowsError() async throws {
        let processor = try makeModel()
        processor.receive(.pinInputChanged("1234"))
        processor.receive(.pinConfirmInputChanged("9999"))

        await processor.perform(.enablePinTapped)

        #expect(processor.state.pinErrorMessage == "PINs don't match.")
        #expect(processor.state.isPinUnlockEnabled == false)
    }

    @Test
    func enablePinWithMatchingPinsUsesTheInjectedSettingsPort() async throws {
        let settings = MockPinUnlockSettings()
        let processor = try makeModel(pinSettings: settings)
        processor.receive(.pinInputChanged("1234"))
        processor.receive(.pinConfirmInputChanged("1234"))

        await processor.perform(.enablePinTapped)

        #expect(processor.state.pinErrorMessage == nil)
        #expect(processor.state.isSavingPin == false)
        #expect(processor.state.isPinUnlockEnabled)
        #expect(processor.state.pinInput.isEmpty)
        #expect(processor.state.pinConfirmInput.isEmpty)
        #expect(await settings.enrollCallCount == 1)
    }

    @Test
    func failedPinEnrollmentKeepsEnrollmentDisabledAndShowsSafeError() async throws {
        let settings = MockPinUnlockSettings()
        await settings.setEnrollmentError(MockDeviceManagementError())
        let processor = try makeModel(pinSettings: settings)
        processor.receive(.pinInputChanged("1234"))
        processor.receive(.pinConfirmInputChanged("1234"))

        await processor.perform(.enablePinTapped)

        #expect(
            processor.state.pinErrorMessage == "Couldn't safely enable PIN unlock. Make sure the vault is unlocked and try again."
        )
        #expect(!processor.state.isPinUnlockEnabled)
        #expect(!processor.state.isSavingPin)
        #expect(await settings.enrollCallCount == 1)
    }

    @Test
    func disablePinOnlyReportsSuccessAfterTheSettingsPortConfirms() async throws {
        let settings = MockPinUnlockSettings(initiallyEnabled: true)
        let processor = try makeModel(pinSettings: settings)
        await processor.perform(.appeared)
        #expect(processor.state.isPinUnlockEnabled)

        await processor.perform(.disablePinTapped)

        #expect(!processor.state.isPinUnlockEnabled)
        #expect(await settings.removeCallCount == 1)
    }

    @Test
    func pinInputChangeClearsPreviousError() throws {
        let processor = try makeModel()
        processor.receive(.pinInputChanged(""))
        processor.receive(.pinConfirmInputChanged(""))

        processor.receive(.pinInputChanged("1"))

        #expect(processor.state.pinErrorMessage == nil)
    }

    @Test
    func timeoutDurationChangeUpdatesStateOnlyAfterSaving() async throws {
        let timeoutSettings = MockTimeoutSettingsRepository()
        let processor = try makeModel(timeoutSettings: timeoutSettings)

        await processor.perform(.timeoutDurationChanged(.oneHour))

        #expect(processor.state.timeoutPreference.duration == .oneHour)
        #expect(timeoutSettings.savedPreferences.last?.duration == .oneHour)
    }

    @Test
    func timeoutActionChangeUpdatesStateOnlyAfterSaving() async throws {
        let timeoutSettings = MockTimeoutSettingsRepository()
        let processor = try makeModel(timeoutSettings: timeoutSettings)

        await processor.perform(.timeoutActionChanged(.logOut))

        #expect(processor.state.timeoutPreference.action == .logOut)
        #expect(timeoutSettings.savedPreferences.last?.action == .logOut)
    }

    @Test
    func timeoutSaveFailureKeepsPreviousValueAndShowsRecoverableError() async throws {
        let timeoutSettings = MockTimeoutSettingsRepository()
        timeoutSettings.shouldFailSave = true
        let processor = try makeModel(timeoutSettings: timeoutSettings)

        await processor.perform(.timeoutDurationChanged(.oneHour))

        #expect(processor.state.timeoutPreference == .default)
        #expect(
            processor.state.timeoutErrorMessage == "Couldn't save the vault timeout setting. Your previous value is still active."
        )
    }

    @Test
    func appearedLoadsTimeoutPreferenceThroughTheInjectedRepository() async throws {
        let timeoutSettings = MockTimeoutSettingsRepository()
        timeoutSettings.preference = VaultTimeoutPreference(duration: .thirtyMinutes, action: .logOut)
        let processor = try makeModel(timeoutSettings: timeoutSettings)

        await processor.perform(.appeared)

        #expect(processor.state.timeoutPreference == timeoutSettings.preference)
        #expect(processor.state.timeoutErrorMessage == nil)
    }

    @Test
    func failedTimeoutLoadIsVisibleWithoutOverwritingTheCurrentSelection() async throws {
        let timeoutSettings = MockTimeoutSettingsRepository()
        timeoutSettings.shouldFailLoad = true
        let processor = try makeModel(timeoutSettings: timeoutSettings)

        await processor.perform(.appeared)

        #expect(processor.state.timeoutPreference == .default)
        #expect(
            processor.state.timeoutErrorMessage == "Couldn't load the vault timeout setting. The saved value was left unchanged."
        )
    }

    @Test
    func appearedLoadsDevicesFromService() async throws {
        let settingsRepository = MockDeviceManagementService()
        settingsRepository.devicesToReturn = [
            RegisteredDevice(id: "device-1", name: "MacBook Pro", isTrusted: true, lastActivityDate: nil),
        ]
        let processor = try makeModel(settingsRepository: settingsRepository)

        await processor.perform(.appeared)

        #expect(processor.state.devices.map(\.id) == ["device-1"])
        #expect(processor.state.isLoadingDevices == false)
        #expect(processor.state.devicesErrorMessage == nil)
        #expect(settingsRepository.fetchCallCount == 1)
    }

    @Test
    func appearedSurfacesDeviceFetchError() async throws {
        let settingsRepository = MockDeviceManagementService()
        settingsRepository.fetchErrorToThrow = MockDeviceManagementError()
        let processor = try makeModel(settingsRepository: settingsRepository)

        await processor.perform(.appeared)

        #expect(processor.state.devices.isEmpty)
        #expect(
            processor.state.devicesErrorMessage == "Couldn't load devices. Check the server connection and try again."
        )
    }

    @Test
    func lateOlderDeviceFetchCannotReplaceNewerResultOrLoadingAndErrorState() async throws {
        let settingsRepository = MockDeviceManagementService()
        let model = try makeModel(settingsRepository: settingsRepository)
        let staleGate = MockDeviceFetchGate()
        settingsRepository.enqueueFetchFailure(MockDeviceManagementError(), gate: staleGate)
        let stale = Task { await model.perform(.refreshDevicesTapped) }
        await staleGate.waitUntilPaused()

        let current = RegisteredDevice(id: "current", name: "Current", isTrusted: true, lastActivityDate: nil)
        settingsRepository.enqueueFetch(devices: [current])
        await model.perform(.refreshDevicesTapped)
        await staleGate.release()
        await stale.value

        #expect(model.state.devices == [current])
        #expect(model.state.devicesErrorMessage == nil)
        #expect(!model.state.isLoadingDevices)
    }

    @Test
    func aFetchStartedBeforeSuccessfulRevocationCannotRestoreTheRevokedDevice() async throws {
        let settingsRepository = MockDeviceManagementService()
        let revoked = RegisteredDevice(id: "device-1", name: "Old device", isTrusted: false, lastActivityDate: nil)
        let retained = RegisteredDevice(id: "device-2", name: "Current device", isTrusted: true, lastActivityDate: nil)
        settingsRepository.devicesToReturn = [revoked, retained]
        let model = try makeModel(settingsRepository: settingsRepository)
        await model.perform(.appeared)

        let staleGate = MockDeviceFetchGate()
        settingsRepository.enqueueFetch(devices: [revoked, retained], gate: staleGate)
        let stale = Task { await model.perform(.refreshDevicesTapped) }
        await staleGate.waitUntilPaused()
        await model.perform(.revokeDeviceTapped(id: revoked.id))
        await model.perform(.confirmDeviceRevocation)
        await staleGate.release()
        await stale.value

        #expect(model.state.devices == [retained])
        #expect(settingsRepository.revokedIDs == [revoked.id])
        #expect(!model.state.isLoadingDevices)
        #expect(model.state.devicesErrorMessage == nil)
    }

    @Test
    func revokeDeviceRemovesItFromStateOnSuccess() async throws {
        let settingsRepository = MockDeviceManagementService()
        settingsRepository.devicesToReturn = [
            RegisteredDevice(id: "device-1", name: "MacBook Pro", isTrusted: true, lastActivityDate: nil),
            RegisteredDevice(id: "device-2", name: "iPhone", isTrusted: false, lastActivityDate: nil),
        ]
        let processor = try makeModel(settingsRepository: settingsRepository)
        await processor.perform(.appeared)

        await processor.perform(.revokeDeviceTapped(id: "device-1"))
        #expect(processor.state.devices.map(\.id) == ["device-1", "device-2"])
        #expect(processor.state.deviceIDPendingRevocation == "device-1")
        await processor.perform(.confirmDeviceRevocation)

        #expect(processor.state.devices.map(\.id) == ["device-2"])
        #expect(settingsRepository.revokedIDs == ["device-1"])
    }

    @Test
    func revokeDeviceFailureKeepsDeviceInStateAndShowsError() async throws {
        let settingsRepository = MockDeviceManagementService()
        settingsRepository.devicesToReturn = [
            RegisteredDevice(id: "device-1", name: "MacBook Pro", isTrusted: true, lastActivityDate: nil),
        ]
        settingsRepository.revokeErrorToThrow = MockDeviceManagementError()
        let processor = try makeModel(settingsRepository: settingsRepository)
        await processor.perform(.appeared)

        await processor.perform(.revokeDeviceTapped(id: "device-1"))
        await processor.perform(.confirmDeviceRevocation)

        #expect(processor.state.devices.map(\.id) == ["device-1"])
        #expect(
            processor.state.devicesErrorMessage == "Couldn't revoke device. Check the server connection and try again."
        )
    }

    @Test(arguments: [404, 405])
    func missingDeviceRevocationEndpointKeepsDeviceAndExplainsWebVaultRecovery(status: Int) async throws {
        let repository = MockDeviceManagementService()
        repository.devicesToReturn = [
            RegisteredDevice(id: "device-1", name: "Synthetic", isTrusted: false, lastActivityDate: nil),
        ]
        repository.revokeErrorToThrow = SettingsRepositoryError.server(statusCode: status)
        let model = try makeModel(settingsRepository: repository)
        await model.perform(.appeared)
        await model.perform(.revokeDeviceTapped(id: "device-1"))
        await model.perform(.confirmDeviceRevocation)
        #expect(model.state.devices.map(\.id) == ["device-1"])
        #expect(model.state.devicesErrorMessage?.contains("does not support revoking individual devices") == true)
        #expect(model.state.devicesErrorMessage?.contains("web vault") == true)
    }

    @Test
    func lockNowTappedInvokesCallback() async throws {
        var lockCalled = false
        let processor = try makeModel(onLockNow: { lockCalled = true })

        await processor.perform(.lockNowTapped)

        #expect(lockCalled)
    }

    @Test
    func logoutTappedInvokesCallback() async throws {
        var logoutCalled = false
        let processor = try makeModel(onLogout: { logoutCalled = true })

        await processor.perform(.logoutTapped)

        #expect(logoutCalled)
    }

    @Test
    func aRevokedSessionClearsPINInputsAndRejectsFurtherActions() async throws {
        let accessGate = SessionAccessGate()
        let processor = try makeModel(accessGate: accessGate)
        processor.receive(.pinInputChanged("fake-test-pin"))
        processor.receive(.pinConfirmInputChanged("fake-test-pin"))
        accessGate.revoke()
        processor.receive(.pinInputChanged("late-input"))
        await processor.perform(.enablePinTapped)
        #expect(processor.state.pinInput.isEmpty)
        #expect(processor.state.pinConfirmInput.isEmpty)
        #expect(!processor.state.isSavingPin)
        #expect(processor.state.devices.isEmpty)
    }

    @Test
    func dismissingDeviceRevocationConfirmationDoesNotCallRepository() async throws {
        let settingsRepository = MockDeviceManagementService()
        settingsRepository.devicesToReturn = [
            RegisteredDevice(id: "device-1", name: "MacBook", isTrusted: true, lastActivityDate: nil),
        ]
        let processor = try makeModel(settingsRepository: settingsRepository)
        await processor.perform(.appeared)
        await processor.perform(.revokeDeviceTapped(id: "device-1"))

        processor.receive(.deviceRevocationConfirmationDismissed)

        #expect(processor.state.deviceIDPendingRevocation == nil)
        #expect(settingsRepository.revokedIDs.isEmpty)
    }

    @Test
    func confirmedDeviceRevocationShowsBusyStateAndRejectsDuplicateActions() async throws {
        let settingsRepository = MockDeviceManagementService()
        settingsRepository.devicesToReturn = [
            RegisteredDevice(id: "device-1", name: "MacBook", isTrusted: true, lastActivityDate: nil),
        ]
        let gate = MockDeviceRevocationGate()
        settingsRepository.revocationGate = gate
        let processor = try makeModel(settingsRepository: settingsRepository)
        await processor.perform(.appeared)
        await processor.perform(.revokeDeviceTapped(id: "device-1"))

        let revocation = Task { await processor.perform(.confirmDeviceRevocation) }
        await gate.waitUntilPaused()
        #expect(processor.state.revokingDeviceIDs == ["device-1"])

        await processor.perform(.revokeDeviceTapped(id: "device-1"))
        await processor.perform(.confirmDeviceRevocation)
        #expect(processor.state.deviceIDPendingRevocation == nil)
        #expect(settingsRepository.revokeCallCount == 1)

        await gate.release()
        await revocation.value
        #expect(settingsRepository.revokedIDs == ["device-1"])
        #expect(processor.state.revokingDeviceIDs.isEmpty)
    }
}

private final class SessionAccessGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isRevoked = false

    func check() throws {
        lock.lock()
        defer { lock.unlock() }
        if isRevoked { throw SessionAccessError.revoked }
    }

    func revoke() {
        lock.lock()
        defer { lock.unlock() }
        isRevoked = true
    }
}

private enum SessionAccessError: Error { case revoked }

private final class MockTimeoutSettingsRepository: VaultTimeoutSettingsRepository, @unchecked Sendable {
    var preference = VaultTimeoutPreference.default
    var shouldFailLoad = false
    var shouldFailSave = false
    private(set) var savedPreferences: [VaultTimeoutPreference] = []

    func load() throws -> VaultTimeoutPreference {
        if shouldFailLoad { throw MockDeviceManagementError() }
        return preference
    }

    func save(_ preference: VaultTimeoutPreference) throws {
        if shouldFailSave { throw MockDeviceManagementError() }
        self.preference = preference
        savedPreferences.append(preference)
    }
}

private actor MockPinUnlockSettings: PinUnlockSettings {
    private(set) var isPinEnabled: Bool
    private(set) var enrollCallCount = 0
    private(set) var removeCallCount = 0
    private var enrollmentError: (any Error)?

    init(initiallyEnabled: Bool = false) { isPinEnabled = initiallyEnabled }

    func isEnabled() -> Bool { isPinEnabled }

    func enroll(pin: String) throws {
        enrollCallCount += 1
        if let enrollmentError { throw enrollmentError }
        isPinEnabled = true
    }

    func remove() {
        removeCallCount += 1
        isPinEnabled = false
    }

    func setEnrollmentError(_ error: (any Error)?) { enrollmentError = error }
}
