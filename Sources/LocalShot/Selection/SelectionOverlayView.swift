import AppKit
import LocalShotCore

@MainActor
final class SelectionOverlayView: NSView {
    var onSelection: ((CGRect, WindowCaptureCandidate?) -> Void)?
    var onCancel: (() -> Void)?

    private var dragStart: CGPoint?
    private var pressedCandidate: SelectionSnappingCandidate?
    private var suggestedCandidate: SelectionSnappingCandidate?
    private var didDrag = false
    private var selectionRect: CGRect = .zero
    private var cursorPoint: CGPoint?
    private var trackingArea: NSTrackingArea?
    private let frozenImage: CGImage?
    private let scaleFactor: CGFloat
    private let snappingCandidates: [SelectionSnappingCandidate]
    private let showsFrozenImageAsBackground: Bool
    private let instructionText: String

    init(
        frame: CGRect,
        frozenImage: CGImage?,
        scaleFactor: CGFloat,
        snappingCandidates: [SelectionSnappingCandidate] = [],
        initialSelectionRect: CGRect = .zero,
        initialCursorPoint: CGPoint? = nil,
        showsFrozenImageAsBackground: Bool = false,
        instructionText: String = "拖动选择截图区域  ·  右键或 Esc 取消"
    ) {
        self.frozenImage = frozenImage
        self.scaleFactor = max(1, scaleFactor)
        self.snappingCandidates = snappingCandidates
        self.selectionRect = initialSelectionRect.intersection(frame)
        self.cursorPoint = initialCursorPoint
        if self.selectionRect.isEmpty, let initialCursorPoint {
            self.suggestedCandidate = snappingCandidates.first(where: {
                $0.frame.contains(initialCursorPoint)
            })
        }
        self.showsFrozenImageAsBackground = showsFrozenImageAsBackground
        self.instructionText = instructionText
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
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: CaptureCursors.rainbowArrow)
    }

    override func mouseEntered(with event: NSEvent) {
        let point = updateCursor(with: event)
        updateSuggestedCandidate(at: point)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = updateCursor(with: event)
        updateSuggestedCandidate(at: point)
    }

    override func mouseExited(with event: NSEvent) {
        cursorPoint = nil
        if dragStart == nil {
            suggestedCandidate = nil
        }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = updateCursor(with: event)
        dragStart = point
        didDrag = false
        pressedCandidate = snappingCandidates.first(where: { $0.frame.contains(point) })
        selectionRect = pressedCandidate?.frame ?? CGRect(origin: point, size: .zero)
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else {
            return
        }
        let point = updateCursor(with: event)
        if pressedCandidate != nil,
           !didDrag,
           hypot(point.x - dragStart.x, point.y - dragStart.y) < 3 {
            return
        }
        didDrag = true
        pressedCandidate = nil
        suggestedCandidate = nil
        selectionRect = CGRect(
            x: min(dragStart.x, point.x),
            y: min(dragStart.y, point.y),
            width: abs(point.x - dragStart.x),
            height: abs(point.y - dragStart.y)
        ).intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        updateCursor(with: event)
        let targetWindow = didDrag ? nil : pressedCandidate?.candidate
        defer {
            dragStart = nil
            pressedCandidate = nil
            didDrag = false
        }
        if !didDrag, let pressedCandidate {
            selectionRect = pressedCandidate.frame.intersection(bounds)
        }
        guard selectionRect.width >= 4, selectionRect.height >= 4 else {
            selectionRect = .zero
            needsDisplay = true
            return
        }
        suggestedCandidate = nil
        onSelection?(selectionRect, targetWindow)
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

        if showsFrozenImageAsBackground, let frozenImage {
            context.saveGState()
            context.interpolationQuality = .high
            context.draw(frozenImage, in: bounds)
            context.restoreGState()
        }

        context.setFillColor(NSColor.black.withAlphaComponent(0.32).cgColor)
        context.fill(bounds)

        let visibleSelection = selectionRect.isEmpty
            ? suggestedCandidate?.frame
            : selectionRect

        if let visibleSelection, !visibleSelection.isEmpty {
            if showsFrozenImageAsBackground, let frozenImage {
                context.saveGState()
                context.clip(to: visibleSelection)
                context.interpolationQuality = .high
                context.draw(frozenImage, in: bounds)
                context.restoreGState()
            } else {
                context.saveGState()
                context.setBlendMode(.clear)
                context.fill(visibleSelection)
                context.restoreGState()
            }

            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(1.5)
            context.stroke(visibleSelection.insetBy(dx: 0.75, dy: 0.75))
            drawSizeLabel(for: visibleSelection)
        } else {
            drawInstruction()
        }

        if selectionRect.isEmpty, let suggestedCandidate {
            drawCandidateLabel(suggestedCandidate)
        }

        if let cursorPoint {
            drawMagnifier(at: cursorPoint, context: context)
        }
    }

    @discardableResult
    private func updateCursor(with event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        cursorPoint = CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
        needsDisplay = true
        return cursorPoint ?? point
    }

    private func updateSuggestedCandidate(at point: CGPoint) {
        guard dragStart == nil, selectionRect.isEmpty else { return }
        suggestedCandidate = snappingCandidates.first(where: { $0.frame.contains(point) })
        needsDisplay = true
    }

    private func drawInstruction() {
        let text = snappingCandidates.isEmpty
            ? instructionText
            : "移动鼠标自动识别窗口，拖动自由选择区域  ·  右键或 Esc 取消"
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

        NSColor.black.withAlphaComponent(0.76).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
        text.draw(
            at: CGPoint(x: rect.minX + padding.width, y: rect.minY + padding.height),
            withAttributes: attributes
        )
    }

    private func drawSizeLabel(for selectionRect: CGRect) {
        let text = "\(Int(selectionRect.width.rounded())) × \(Int(selectionRect.height.rounded()))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        let padding = CGSize(width: 8, height: 5)
        var labelRect = CGRect(
            x: selectionRect.minX,
            y: selectionRect.minY - textSize.height - padding.height * 2 - 6,
            width: textSize.width + padding.width * 2,
            height: textSize.height + padding.height * 2
        )
        if labelRect.minY < bounds.minY + 6 {
            labelRect.origin.y = selectionRect.maxY + 6
        }
        labelRect = labelRect.intersection(bounds.insetBy(dx: 6, dy: 6))

        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 6, yRadius: 6).fill()
        text.draw(
            at: CGPoint(
                x: labelRect.minX + padding.width,
                y: labelRect.minY + padding.height
            ),
            withAttributes: attributes
        )
    }

    private func drawCandidateLabel(_ candidate: SelectionSnappingCandidate) {
        let text = candidate.title.isEmpty
            ? candidate.applicationName
            : "\(candidate.applicationName) · \(candidate.title)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        let padding = CGSize(width: 9, height: 6)
        let width = min(textSize.width + padding.width * 2, max(80, bounds.width - 20))
        var rect = CGRect(
            x: candidate.frame.minX,
            y: candidate.frame.maxY + 8,
            width: width,
            height: textSize.height + padding.height * 2
        )
        if rect.maxY > bounds.maxY - 8 {
            rect.origin.y = candidate.frame.minY - rect.height - 8
        }
        rect.origin.x = min(
            max(rect.minX, bounds.minX + 8),
            bounds.maxX - rect.width - 8
        )

        NSColor.black.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        text.draw(
            in: rect.insetBy(dx: padding.width, dy: padding.height),
            withAttributes: attributes
        )
    }

    private func drawMagnifier(at point: CGPoint, context: CGContext) {
        guard let frozenImage else {
            return
        }

        let samplePixels = min(CGFloat(56), CGFloat(frozenImage.width), CGFloat(frozenImage.height))
        let pixelX = point.x * scaleFactor
        let pixelY = (bounds.height - point.y) * scaleFactor
        let sourceX = min(max(pixelX - samplePixels / 2, 0), CGFloat(frozenImage.width) - samplePixels)
        let sourceY = min(max(pixelY - samplePixels / 2, 0), CGFloat(frozenImage.height) - samplePixels)
        let sourceRect = CGRect(
            x: floor(sourceX),
            y: floor(sourceY),
            width: samplePixels,
            height: samplePixels
        ).integral
        guard sourceRect.width >= 2,
              sourceRect.height >= 2,
              let sample = frozenImage.cropping(to: sourceRect) else {
            return
        }

        let size = CGSize(width: 168, height: 168)
        var origin = CGPoint(x: point.x + 24, y: point.y + 24)
        if origin.x + size.width > bounds.maxX - 8 {
            origin.x = point.x - size.width - 24
        }
        if origin.y + size.height > bounds.maxY - 8 {
            origin.y = point.y - size.height - 24
        }
        origin.x = min(max(origin.x, bounds.minX + 8), bounds.maxX - size.width - 8)
        origin.y = min(max(origin.y, bounds.minY + 8), bounds.maxY - size.height - 8)
        let outerRect = CGRect(origin: origin, size: size)
        let imageRect = outerRect.insetBy(dx: 2.5, dy: 2.5)
        let path = CGPath(rect: outerRect, transform: nil)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -3), blur: 10, color: NSColor.black.withAlphaComponent(0.45).cgColor)
        context.setFillColor(NSColor.black.withAlphaComponent(0.88).cgColor)
        context.addPath(path)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.clip(to: imageRect)
        context.interpolationQuality = .none
        context.draw(sample, in: imageRect)

        let center = CGPoint(x: imageRect.midX, y: imageRect.midY)
        context.setStrokeColor(NSColor(srgbRed: 0.10, green: 0.76, blue: 1, alpha: 1).cgColor)
        context.setLineWidth(1.5)
        context.move(to: CGPoint(x: imageRect.minX, y: center.y))
        context.addLine(to: CGPoint(x: imageRect.maxX, y: center.y))
        context.move(to: CGPoint(x: center.x, y: imageRect.minY))
        context.addLine(to: CGPoint(x: center.x, y: imageRect.maxY))
        context.strokePath()
        context.restoreGState()

        context.setStrokeColor(NSColor.white.withAlphaComponent(0.62).cgColor)
        context.setLineWidth(0.75)
        context.addPath(path)
        context.strokePath()
    }
}
