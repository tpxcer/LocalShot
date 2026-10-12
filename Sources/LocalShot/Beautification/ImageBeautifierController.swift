import AppKit
import LocalShotCore
import SwiftUI

@MainActor
final class ImageBeautifierController {
    private let windowCoordinator = SingleWindowCoordinator()

    func open(asset: CaptureAsset, onError: @escaping (String) -> Void) {
        do {
            let model = try ImageBeautifierModel(asset: asset)
            let hostingController = NSHostingController(rootView: ImageBeautifierView(model: model))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "图片美化 — \(asset.url.lastPathComponent)"
            window.contentViewController = hostingController
            window.minSize = NSSize(width: 820, height: 560)
            window.center()
            window.isReleasedWhenClosed = false

            windowCoordinator.show(window)
        } catch {
            onError("打开图片美化失败：\(error.localizedDescription)")
        }
    }
}
