import AppKit
import LocalShotCore
import SwiftUI

struct QuickAccessActions {
    let copy: () -> Void
    let annotate: () -> Void
    let beautify: () -> Void
    let pin: () -> Void
    let recognizeText: () -> Void
    let translate: () -> Void
    let saveAs: () -> Void
    let reveal: () -> Void
    let delete: () -> Void
    let dismiss: () -> Void
}

@MainActor
final class QuickAccessPanelController {
    private var panel: NSPanel?
    private var autoCloseTimer: Timer?

    func show(
        asset: CaptureAsset,
        autoCloseInterval: TimeInterval = 15,
        actions: QuickAccessActions
    ) {
        dismiss()

        let rootView = QuickAccessView(asset: asset, actions: actions)
        let hostingController = NSHostingController(rootView: rootView)
        let size = NSSize(width: 456, height: 112)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true

        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visibleFrame = screen.visibleFrame
            panel.setFrameOrigin(
                NSPoint(
                    x: visibleFrame.maxX - size.width - 20,
                    y: visibleFrame.minY + 20
                )
            )
        }

        panel.orderFrontRegardless()
        self.panel = panel
        if autoCloseInterval > 0 {
            autoCloseTimer = Timer.scheduledTimer(
                withTimeInterval: autoCloseInterval,
                repeats: false
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.dismiss()
                }
            }
        }
    }

    func dismiss() {
        autoCloseTimer?.invalidate()
        autoCloseTimer = nil
        panel?.close()
        panel = nil
    }
}
