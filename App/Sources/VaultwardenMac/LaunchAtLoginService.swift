import ServiceManagement

/// Thin wrapper around `SMAppService.mainApp` (the modern replacement for the old
/// `SMLoginItemSetEnabled`/helper-app approach - registers this app bundle itself as a login item,
/// no separate launcher target needed).
enum LaunchAtLoginService {
    enum Status: Equatable {
        case enabled
        case disabled
        case requiresApproval
        case unavailable
    }

    static var status: Status {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered: .disabled
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
            try SMAppService.mainApp.unregister()
        }
    }
}
