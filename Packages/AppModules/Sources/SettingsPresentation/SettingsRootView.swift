import Domain
import Foundation
import SwiftUI

/// Entry point for the Settings feature: account info, PIN unlock, vault-timeout preference, the web
/// vault escape hatch, lock/logout, and a best-effort device list. Multi-account switching is
/// explicitly out of scope - it would need a real multi-account data model in `AuthCredentialStore`,
/// which is a much bigger change than this screen.
public struct SettingsRootView: View {
    @State private var model: SettingsModel

    public init(
        account: AccountSession,
        checkSessionAccess: @escaping @Sendable () throws -> Void,
        sessionStates: @escaping @Sendable () async -> AsyncStream<SessionState>,
        settingsRepository: any SettingsRepository,
        timeoutSettings: any VaultTimeoutSettingsRepository,
        pinSettings: any PinUnlockSettings,
        openURLClient: any OpenURLClient,
        onLockNow: @escaping () -> Void,
        onLogout: @escaping () -> Void
    ) {
        _model = State(initialValue: SettingsModel(
            account: account,
            checkSessionAccess: checkSessionAccess,
            sessionStates: sessionStates,
            settingsRepository: settingsRepository,
            timeoutSettings: timeoutSettings,
            pinSettings: pinSettings,
            openURLClient: openURLClient,
            onLockNow: onLockNow,
            onLogout: onLogout
        ))
    }

    public var body: some View {
        #if os(iOS)
            // A tab in the iOS app, so it brings its own navigation bar for the title. No minimum
            // frame: 480pt is wider than an iPhone, which would force the whole screen to scroll
            // sideways.
            NavigationStack {
                form.navigationTitle("Settings")
            }
        #else
            form
                .frame(minWidth: 480, minHeight: 560)
        #endif
    }

    private var form: some View {
        Form {
            accountSection
            pinSection
            timeoutSection
            devicesSection
            actionsSection
        }
        .formStyle(.grouped)
        .task { await model.perform(.appeared) }
        .alert(
            "Couldn't open the web vault",
            isPresented: Binding(
                get: { model.state.openURLErrorMessage != nil },
                set: { isPresented in if !isPresented { model.receive(.openURLErrorDismissed) } }
            )
        ) {
            Button("OK", role: .cancel) { model.receive(.openURLErrorDismissed) }
        } message: {
            Text(model.state.openURLErrorMessage ?? "Check that a browser is available and try again.")
        }
    }

    private var accountSection: some View {
        Section("Account") {
            LabeledContent("Email", value: model.state.email)
            LabeledContent("Server", value: model.state.serverBaseURL.absoluteString)
        }
    }

    private var pinSection: some View {
        Section("PIN Unlock") {
            if let error = model.state.pinErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if model.state.isPinUnlockEnabled {
                LabeledContent("PIN unlock") {
                    Text("Enabled")
                        .foregroundStyle(.secondary)
                }
                Button("Disable PIN Unlock", role: .destructive) {
                    Task { await model.perform(.disablePinTapped) }
                }
            } else {
                SecureField("New PIN", text: Binding(
                    get: { model.state.pinInput }, set: { model.receive(.pinInputChanged($0)) }
                ))
                SecureField("Confirm PIN", text: Binding(
                    get: { model.state.pinConfirmInput }, set: { model.receive(.pinConfirmInputChanged($0)) }
                ))

                Button {
                    Task { await model.perform(.enablePinTapped) }
                } label: {
                    if model.state.isSavingPin {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Enable PIN Unlock")
                    }
                }
                .disabled(model.state.isSavingPin)
            }
        }
    }

    private var timeoutSection: some View {
        Section("Vault Timeout") {
            Picker("Lock after", selection: Binding(
                get: { model.state.timeoutPreference.duration },
                set: { duration in Task { await model.perform(.timeoutDurationChanged(duration)) } }
            )) {
                ForEach(VaultTimeoutPreference.Duration.allCases, id: \.self) { duration in
                    Text(duration.displayName).tag(duration)
                }
            }
            .disabled(model.state.isSavingTimeoutPreference)

            Picker("Timeout action", selection: Binding(
                get: { model.state.timeoutPreference.action },
                set: { action in Task { await model.perform(.timeoutActionChanged(action)) } }
            )) {
                ForEach(VaultTimeoutPreference.Action.allCases, id: \.self) { action in
                    Text(action.displayName).tag(action)
                }
            }
            .disabled(model.state.isSavingTimeoutPreference)

            if let error = model.state.timeoutErrorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var devicesSection: some View {
        Section("Devices") {
            if let error = model.state.devicesErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if model.state.isLoadingDevices {
                ProgressView().controlSize(.small)
            } else if model.state.devices.isEmpty {
                if model.state.devicesErrorMessage == nil {
                    Text("No devices found.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(model.state.devices) { device in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(device.name)
                            if let lastActivity = device.lastActivityDate {
                                Text("Last active \(lastActivity.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Revoke", role: .destructive) {
                            Task { await model.perform(.revokeDeviceTapped(id: device.id)) }
                        }
                        .buttonStyle(.borderless)
                        .disabled(model.state.revokingDeviceIDs.contains(device.id))
                    }
                }
            }

            Button("Refresh") {
                Task { await model.perform(.refreshDevicesTapped) }
            }
            .disabled(model.state.isLoadingDevices)
        }
        .confirmationDialog(
            "Revoke this device?",
            isPresented: Binding(
                get: { model.state.deviceIDPendingRevocation != nil },
                set: { isPresented in
                    if !isPresented { model.receive(.deviceRevocationConfirmationDismissed) }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Revoke Device", role: .destructive) {
                Task { await model.perform(.confirmDeviceRevocation) }
            }
            Button("Cancel", role: .cancel) { model.receive(.deviceRevocationConfirmationDismissed) }
        } message: {
            Text("This device will lose access to the account.")
        }
    }

    private var actionsSection: some View {
        Section {
            Button("Open Web Vault") {
                Task { await model.perform(.openWebVaultTapped) }
            }
            Button("Lock Now") {
                Task { await model.perform(.lockNowTapped) }
            }
            Button("Log Out", role: .destructive) {
                Task { await model.perform(.logoutTapped) }
            }
        }
    }
}
