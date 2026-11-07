import SecurityStorage
import SwiftUI

/// Composition either succeeds once for all scenes, or presents configuration recovery without
/// creating the auth repository/view tree. Configuration failures never trigger credential cleanup.
@MainActor
enum AppStartup {
    case ready(AppComposition, VaultwardenAppModel)
    case unavailable(AppStorageConfigurationError)

    static func load() -> AppStartup {
        do {
            let composition = try AppComposition()
            return .ready(composition, composition.makeModel())
        } catch let error as AppStorageConfigurationError {
            return .unavailable(error)
        } catch {
            return .unavailable(.sharedContainerUnavailable)
        }
    }

    var model: VaultwardenAppModel? {
        guard case let .ready(_, model) = self else { return nil }
        return model
    }
}

struct AppStartupRootView: View {
    let startup: AppStartup
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        switch startup {
        case let .ready(composition, model):
            RootView(appModel: model, composition: composition)
                .onChange(of: scenePhase) { _, newPhase in
                    Task { await model.scenePhaseChanged(to: newPhase) }
                }
                .vaultTimeoutTicker(appModel: model)
        case let .unavailable(error):
            AppConfigurationFailureView(error: error)
        }
    }
}

struct AppConfigurationFailureView: View {
    let error: AppStorageConfigurationError

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.shield").font(.largeTitle)
            Text("App configuration unavailable").font(.title2)
            Text(
                "Secure shared storage is not configured. Sign-in is disabled; your saved credentials have not been changed."
            )
            .multilineTextAlignment(.center)
            #if DEBUG
                Text(error.localizedDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            #else
                Text("Reinstall a correctly signed build or contact the build's maintainer.")
                    .foregroundStyle(.secondary)
            #endif
        }
        .padding()
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
