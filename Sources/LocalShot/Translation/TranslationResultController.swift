import AppKit
import LocalShotCore
import SwiftUI

@MainActor
final class TranslationResultController {
    private let windowCoordinator = SingleWindowCoordinator()

    func open(asset: CaptureAsset, onError: @escaping (String) -> Void) {
        guard #available(macOS 15.0, *) else {
            onError("原位置系统翻译需要 macOS 15 或更高版本。")
            return
        }

        let model = TranslationResultModel(asset: asset)
        let hostingController = NSHostingController(rootView: TranslationResultView(model: model))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "原位置翻译 — \(asset.url.lastPathComponent)"
        window.contentViewController = hostingController
        window.minSize = NSSize(width: 920, height: 620)
        window.center()
        window.isReleasedWhenClosed = false

        windowCoordinator.show(window)
    }
}
