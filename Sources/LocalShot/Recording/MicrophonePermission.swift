import AVFoundation
import AppKit

enum MicrophonePermission {
    enum Status: Equatable {
        case authorized
        case notDetermined
        case denied
        case restricted

        var isGranted: Bool { self == .authorized }

        var displayName: String {
            switch self {
            case .authorized:
                "已允许"
            case .notDetermined:
                "使用时询问"
            case .denied:
                "未允许"
            case .restricted:
                "受系统限制"
            }
        }
    }

    static var status: Status {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            .authorized
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .denied
        }
    }

    static func request() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            true
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: .audio)
        default:
            false
        }
    }

    static func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
