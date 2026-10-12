import AppKit
import LocalShotCore
import SwiftUI

@MainActor
final class OCRResultController {
    private let windowCoordinator = SingleWindowCoordinator()

    func open(asset: CaptureAsset) {
        let model = OCRResultModel(asset: asset)
        let hostingController = NSHostingController(rootView: OCRResultView(model: model))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "文字识别 — \(asset.url.lastPathComponent)"
        window.contentViewController = hostingController
        window.minSize = NSSize(width: 520, height: 420)
        window.center()
        window.isReleasedWhenClosed = false

        windowCoordinator.show(window)
    }
}
