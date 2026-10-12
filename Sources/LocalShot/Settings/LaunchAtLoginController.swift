import AppKit
import ServiceManagement

enum LaunchAtLoginState: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable

    var isRequested: Bool {
        self == .enabled || self == .requiresApproval
    }

    var displayName: String {
        switch self {
        case .disabled: "未启用"
        case .enabled: "已启用"
        case .requiresApproval: "等待系统批准"
        case .unavailable: "当前应用不可用"
        }
    }
}

@MainActor
final class LaunchAtLoginController {
    func currentState() -> LaunchAtLoginState {
        switch SMAppService.mainApp.status {
        case .notRegistered:
            .disabled
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .disabled
        @unknown default:
            .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginState {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        return currentState()
    }

    func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
