import ServiceManagement

/// Opening Penumbra at login, through the system's Login Items list.
@MainActor
public enum LoginItem {
    public enum State: Sendable {
        case enabled, disabled
        /// Registered, but switched off in System Settings, so the user has to allow it there.
        case needsApproval
    }

    public static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .needsApproval
        default: .disabled
        }
    }

    public static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    public static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
