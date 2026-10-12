import AppKit

@MainActor
final class ScrollingCaptureSelectionBorderController {
    private var panel: NSPanel?

    func show(selectionRect: CGRect) {
        dismiss()
        guard selectionRect.width >= 4, selectionRect.height >= 4 else {
            return
        }
        let borderPadding: CGFloat = 3
        let panelRect = selectionRect.insetBy(dx: -borderPadding, dy: -borderPadding)
        let panel = NSPanel(
            contentRect: panelRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = ScrollingCaptureSelectionBorderView(frame: CGRect(
            origin: .zero,
            size: panelRect.size
        ))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func dismiss() {
        panel?.close()
        panel = nil
    }
}

private final class ScrollingCaptureSelectionBorderView: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.clear.setFill()
        dirtyRect.fill()

        let rect = bounds.insetBy(dx: 3, dy: 3)
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1.5
        NSColor(srgbRed: 0.18, green: 0.58, blue: 1, alpha: 0.96).setStroke()
        path.stroke()
    }
}
