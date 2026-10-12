import AppKit

@MainActor
final class WindowSelectionOverlayView: NSView {
    struct HighlightedWindow {
        let id: CGWindowID
        let frame: CGRect
        let applicationName: String
        let title: String
    }

    var onPointerMoved: ((CGPoint) -> Void)?
    var onSelect: ((CGWindowID) -> Void)?
    var onCancel: (() -> Void)?
    var highlightedWindow: HighlightedWindow? {
        didSet {
            needsDisplay = true
        }
    }

    private let screenFrame: CGRect
    private let backgroundImage: CGImage?
    private var trackingArea: NSTrackingArea?

    init(frame: CGRect, screenFrame: CGRect, backgroundImage: CGImage? = nil) {
        self.screenFrame = screenFrame
        self.backgroundImage = backgroundImage
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseMoved],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseMoved(with event: NSEvent) {
        onPointerMoved?(globalLocation(for: event))
    }

    override func mouseDown(with event: NSEvent) {
        onPointerMoved?(globalLocation(for: event))
        if let windowID = highlightedWindow?.id {
            onSelect?(windowID)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    private func globalLocation(for event: NSEvent) -> CGPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? CGPoint(
            x: screenFrame.minX + event.locationInWindow.x,
            y: screenFrame.minY + event.locationInWindow.y
        )
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        if let backgroundImage {
            context.saveGState()
            context.interpolationQuality = .high
            context.draw(backgroundImage, in: bounds)
            context.restoreGState()
        }

        context.setFillColor(NSColor.black.withAlphaComponent(0.34).cgColor)
        context.fill(bounds)

        guard let highlightedWindow else {
            drawInstruction()
            return
        }

        let localFrame = highlightedWindow.frame.offsetBy(
            dx: -screenFrame.minX,
            dy: -screenFrame.minY
        ).intersection(bounds)
        guard !localFrame.isEmpty else {
            return
        }

        if let backgroundImage {
            context.saveGState()
            context.clip(to: localFrame)
            context.interpolationQuality = .high
            context.draw(backgroundImage, in: bounds)
            context.restoreGState()
        } else {
            context.saveGState()
            context.setBlendMode(.clear)
            context.fill(localFrame)
            context.restoreGState()
        }

        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        context.setLineWidth(3)
        context.stroke(localFrame.insetBy(dx: 1.5, dy: 1.5))
        drawWindowLabel(highlightedWindow, localFrame: localFrame)
    }

    private func drawInstruction() {
        let text = "移动鼠标选择窗口，点击截图  ·  Esc 取消"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        let padding = CGSize(width: 16, height: 10)
        let rect = CGRect(
            x: bounds.midX - (textSize.width + padding.width * 2) / 2,
            y: bounds.midY - (textSize.height + padding.height * 2) / 2,
            width: textSize.width + padding.width * 2,
            height: textSize.height + padding.height * 2
        )

        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
        text.draw(
            at: CGPoint(x: rect.minX + padding.width, y: rect.minY + padding.height),
            withAttributes: attributes
        )
    }

    private func drawWindowLabel(
        _ window: HighlightedWindow,
        localFrame: CGRect
    ) {
        let text = window.title.isEmpty
            ? window.applicationName
            : "\(window.applicationName) · \(window.title)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let rawSize = text.size(withAttributes: attributes)
        let padding = CGSize(width: 9, height: 6)
        let width = min(rawSize.width + padding.width * 2, max(80, bounds.width - 20))
        var labelRect = CGRect(
            x: localFrame.minX,
            y: localFrame.maxY + 8,
            width: width,
            height: rawSize.height + padding.height * 2
        )
        if labelRect.maxY > bounds.maxY - 8 {
            labelRect.origin.y = localFrame.minY - labelRect.height - 8
        }
        labelRect.origin.x = min(
            max(labelRect.minX, bounds.minX + 8),
            bounds.maxX - labelRect.width - 8
        )

        NSColor.black.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 7, yRadius: 7).fill()
        text.draw(
            in: labelRect.insetBy(dx: padding.width, dy: padding.height),
            withAttributes: attributes
        )
    }
}
