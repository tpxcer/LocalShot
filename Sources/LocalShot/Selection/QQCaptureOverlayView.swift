import AppKit
import CoreImage
import LocalShotCore
import LocalShotEditing

@MainActor
final class QQCaptureOverlayView: NSView, NSTextFieldDelegate {
    var onComplete: ((CGRect, [AnnotationItem], QQCaptureOverlayAction) -> Void)?
    var onCancel: (() -> Void)?

    private enum Phase {
        case selecting
        case editing
        case selectingText
    }

    private enum Tool: String, Hashable {
        case rectangle
        case ellipse
        case arrow
        case pen
        case text
        case step
        case pixelate

        var symbolName: String {
            switch self {
            case .rectangle: "rectangle"
            case .ellipse: "circle"
            case .arrow: "arrow.up.right"
            case .pen: "pencil.tip"
            case .text: "character"
            case .step: "1.circle"
            case .pixelate: "square.grid.3x3.fill"
            }
        }

        var label: String {
            switch self {
            case .rectangle: "矩形"
            case .ellipse: "椭圆"
            case .arrow: "箭头"
            case .pen: "画笔"
            case .text: "文字"
            case .step: "步骤编号"
            case .pixelate: "马赛克"
            }
        }
    }

    private enum ToolbarItemID: Hashable {
        case tool(Tool)
        case undo
        case scrolling
        case recording
        case recognizeText
        case translate
        case pin
        case save
        case cancel
        case finish
    }

    private enum SelectionHandle: CaseIterable, Equatable {
        case left
        case right
        case top
        case bottom
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    private enum DragMode {
        case create(start: CGPoint, suggested: CGRect?)
        case selectText(start: CGPoint)
        case move(start: CGPoint, original: CGRect)
        case resize(
            handle: SelectionHandle,
            start: CGPoint,
            original: CGRect,
            annotations: [AnnotationItem]
        )
        case draw(start: AnnotationPoint, points: [AnnotationPoint])
        case moveAnnotation(
            id: UUID,
            start: AnnotationPoint,
            original: AnnotationItem
        )
        case resizeAnnotation(
            id: UUID,
            handle: AnnotationHandle,
            original: AnnotationItem
        )
    }

    private enum AnnotationHandle: Hashable {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
        case arrowStart
        case arrowEnd
    }

    private enum TextEditorContext {
        case annotationText(origin: CGPoint, color: AnnotationColor)
        case stepNote(id: UUID)
        case arrowNote(id: UUID)
    }

    private struct ToolbarButton {
        let id: ToolbarItemID
        let rect: CGRect
        let symbolName: String
        let label: String
    }

    private struct GlassBackdrop {
        let panelRect: CGRect
        let drawRect: CGRect
        let image: CGImage
    }

    private let frozenImage: CGImage?
    private let scaleFactor: CGFloat
    private let snappingCandidates: [QQCaptureSnappingCandidate]
    private let emphasizesScrollingAction: Bool
    private let colors: [(name: String, value: AnnotationColor)] = [
        ("红色", .red),
        ("橙色", AnnotationColor(red: 1, green: 0.48, blue: 0.12)),
        ("黄色", AnnotationColor(red: 1, green: 0.78, blue: 0.08)),
        ("绿色", AnnotationColor(red: 0.18, green: 0.78, blue: 0.42)),
        ("蓝色", AnnotationColor(red: 0.16, green: 0.55, blue: 0.98)),
        ("紫色", AnnotationColor(red: 0.64, green: 0.38, blue: 0.94)),
        ("黑色", .black),
        ("白色", .white)
    ]
    private let lineWidths: [CGFloat] = [3, 6, 9]
    private let previewCIContext = CIContext()
    private var toolbarGlassBackdrop: GlassBackdrop?
    private var propertyGlassBackdrop: GlassBackdrop?

    private var phase: Phase = .selecting
    private var selectionRect: CGRect = .zero
    private var textSelectionRect: CGRect = .zero
    private var suggestedCandidate: QQCaptureSnappingCandidate?
    private var selectedTool: Tool?
    private var selectedColorIndex = 0
    private var selectedLineWidthIndex = 0
    private var selectedPixelateEffect: PixelateEffect = .mosaic
    private var propertiesVisibleForAcceptance = false
    private var annotations: [AnnotationItem] = []
    private var selectedAnnotationID: UUID?
    private var dragMode: DragMode?
    private var draftCurrent: AnnotationPoint?
    private var hoveredToolbarItem: ToolbarItemID?
    private var cursorPoint: CGPoint?
    private var trackingArea: NSTrackingArea?
    private weak var textEditor: NSTextField?
    private var textEditorContext: TextEditorContext?

    init(
        frame: CGRect,
        frozenImage: CGImage?,
        scaleFactor: CGFloat,
        snappingCandidates: [QQCaptureSnappingCandidate],
        initialSelectionRect: CGRect = .zero,
        initialAnnotations: [AnnotationItem] = [],
        initialCursorPoint: CGPoint? = nil,
        showsPropertiesInitially: Bool = false,
        showsPixelatePropertiesInitially: Bool = false,
        emphasizesScrollingAction: Bool = false
    ) {
        self.frozenImage = frozenImage
        self.scaleFactor = max(1, scaleFactor)
        self.snappingCandidates = snappingCandidates
        self.emphasizesScrollingAction = emphasizesScrollingAction
        super.init(frame: frame)
        cursorPoint = initialCursorPoint
        selectionRect = initialSelectionRect.intersection(frame)
        annotations = initialAnnotations
        if selectionRect.width >= 4, selectionRect.height >= 4 {
            phase = .editing
            if showsPixelatePropertiesInitially {
                selectedTool = .pixelate
            } else if showsPropertiesInitially {
                propertiesVisibleForAcceptance = true
                if let firstEditable = annotations.first(where: { isEditableAnnotation($0) }) {
                    selectEditableAnnotation(firstEditable)
                }
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

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
        if phase == .selectingText, !selectionRect.isEmpty {
            addCursorRect(selectionRect, cursor: .crosshair)
            return
        }
        guard phase == .editing, !selectionRect.isEmpty else {
            return
        }
        addCursorRect(selectionRect, cursor: selectedTool == nil ? .openHand : .crosshair)
        for (handle, rect) in selectionHandleRects() {
            let cursor: NSCursor
            switch handle {
            case .left, .right:
                cursor = .resizeLeftRight
            case .top, .bottom:
                cursor = .resizeUpDown
            case .topLeft:
                cursor = QQCaptureCursors.resizeTopLeft
            case .topRight:
                cursor = QQCaptureCursors.resizeTopRight
            case .bottomLeft:
                cursor = QQCaptureCursors.resizeBottomLeft
            case .bottomRight:
                cursor = QQCaptureCursors.resizeBottomRight
            }
            addCursorRect(rect.insetBy(dx: -3, dy: -3), cursor: cursor)
        }
        for (handle, rect) in selectedAnnotationHandleRects() {
            let cursor: NSCursor
            switch handle {
            case .topLeft:
                cursor = QQCaptureCursors.resizeTopLeft
            case .topRight:
                cursor = QQCaptureCursors.resizeTopRight
            case .bottomLeft:
                cursor = QQCaptureCursors.resizeBottomLeft
            case .bottomRight:
                cursor = QQCaptureCursors.resizeBottomRight
            case .arrowStart, .arrowEnd:
                cursor = .crosshair
            }
            addCursorRect(rect.insetBy(dx: -4, dy: -4), cursor: cursor)
        }
        addCursorRect(toolbarRect(), cursor: .arrow)
        if selectedTool != nil {
            addCursorRect(propertyPanelRect(), cursor: .arrow)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        _ = updateCursor(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = updateCursor(with: event)
        if phase == .selecting {
            suggestedCandidate = snappingCandidates.first(where: { $0.frame.contains(point) })
        } else if phase == .editing {
            hoveredToolbarItem = toolbarButtons().first(where: { $0.rect.contains(point) })?.id
        } else {
            hoveredToolbarItem = nil
        }
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        cursorPoint = nil
        hoveredToolbarItem = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = updateCursor(with: event)

        if phase == .selectingText {
            guard selectionRect.contains(point) else {
                return
            }
            textSelectionRect = CGRect(origin: point, size: .zero)
            dragMode = .selectText(start: point)
            needsDisplay = true
            return
        }

        if phase == .editing,
           event.clickCount >= 2,
           let annotation = editableAnnotation(at: point) {
            selectEditableAnnotation(annotation)
            switch annotation {
            case let .step(step):
                beginStepNoteEditing(for: step)
            case let .arrow(arrow):
                beginArrowNoteEditing(for: arrow)
            default:
                break
            }
            needsDisplay = true
            return
        }

        if phase == .editing,
           event.clickCount >= 2,
           selectionRect.contains(point),
           toolbarButtons().allSatisfy({ !$0.rect.contains(point) }) {
            complete(with: .finish)
            return
        }

        if phase == .editing {
            if let button = toolbarButtons().first(where: { $0.rect.contains(point) }) {
                handleToolbarItem(button.id)
                return
            }
            if handlePropertyPanelClick(at: point) {
                return
            }
            if let handle = selectedAnnotationHandle(at: point),
               let annotation = selectedAnnotation {
                dragMode = .resizeAnnotation(
                    id: annotation.id,
                    handle: handle,
                    original: annotation
                )
                return
            }
            if let annotation = editableAnnotation(at: point) {
                selectEditableAnnotation(annotation)
                dragMode = .moveAnnotation(
                    id: annotation.id,
                    start: annotationPoint(from: point),
                    original: annotation
                )
                NSCursor.closedHand.set()
                return
            }
            if let handle = selectionHandle(at: point), selectedTool == nil {
                dragMode = .resize(
                    handle: handle,
                    start: point,
                    original: selectionRect,
                    annotations: annotations
                )
                return
            }
            if let selectedTool, selectionRect.contains(point) {
                selectedAnnotationID = nil
                if selectedTool == .text {
                    beginTextEditing(at: point)
                    return
                }
                let projectPoint = annotationPoint(from: point)
                dragMode = .draw(start: projectPoint, points: [projectPoint])
                draftCurrent = projectPoint
                return
            }
            if selectionRect.contains(point) {
                dragMode = .move(start: point, original: selectionRect)
                NSCursor.closedHand.set()
                return
            }

            annotations.removeAll()
            selectedAnnotationID = nil
            selectedTool = nil
            phase = .selecting
        }

        let suggested = snappingCandidates.first(where: { $0.frame.contains(point) })?.frame
        selectionRect = CGRect(origin: point, size: .zero)
        dragMode = .create(start: point, suggested: suggested)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = updateCursor(with: event)
        guard let dragMode else {
            return
        }
        switch dragMode {
        case let .create(start, suggested):
            let rect = normalizedRect(from: start, to: point).intersection(bounds)
            selectionRect = rect.width >= 4 && rect.height >= 4 ? rect : (suggested ?? rect)
        case let .selectText(start):
            textSelectionRect = normalizedRect(from: start, to: point)
                .intersection(selectionRect)
        case let .move(start, original):
            selectionRect = movedSelection(
                original,
                dx: point.x - start.x,
                dy: point.y - start.y
            )
        case let .resize(handle, start, original, originalAnnotations):
            let resized = resizedSelection(
                original,
                handle: handle,
                dx: point.x - start.x,
                dy: point.y - start.y
            )
            let translation = ScreenCoordinateConverter.annotationTranslationKeepingScreenPosition(
                from: original,
                to: resized,
                scaleFactor: scaleFactor
            )
            selectionRect = resized
            annotations = originalAnnotations.map {
                $0.translated(dx: translation.width, dy: translation.height)
            }
        case let .draw(start, points):
            let projectPoint = annotationPoint(from: clampedToSelection(point))
            var updatedPoints = points
            if selectedTool == .pen {
                updatedPoints.append(projectPoint)
            }
            self.dragMode = .draw(start: start, points: updatedPoints)
            draftCurrent = projectPoint
        case let .moveAnnotation(id, start, original):
            let projectPoint = annotationPoint(from: clampedToSelection(point))
            replaceAnnotation(
                id: id,
                with: original.translated(
                    dx: projectPoint.x - start.x,
                    dy: projectPoint.y - start.y
                )
            )
        case let .resizeAnnotation(id, handle, original):
            let projectPoint = annotationPoint(from: clampedToSelection(point))
            replaceAnnotation(
                id: id,
                with: resizedAnnotation(original, handle: handle, to: projectPoint)
            )
        }
        resetCursorRects()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = updateCursor(with: event)
        defer {
            dragMode = nil
            draftCurrent = nil
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        }
        guard let dragMode else {
            return
        }
        switch dragMode {
        case let .create(start, suggested):
            let dragged = normalizedRect(from: start, to: point).intersection(bounds)
            if dragged.width >= 4, dragged.height >= 4 {
                selectionRect = dragged
            } else if let suggested {
                selectionRect = suggested.intersection(bounds)
            }
            guard selectionRect.width >= 4, selectionRect.height >= 4 else {
                selectionRect = .zero
                phase = .selecting
                return
            }
            phase = .editing
            suggestedCandidate = nil
            resetCursorRects()
        case let .selectText(start):
            let rect = normalizedRect(from: start, to: point).intersection(selectionRect)
            guard rect.width >= 4, rect.height >= 4 else {
                textSelectionRect = .zero
                return
            }
            onComplete?(rect, [], .recognizeText)
        case .move, .resize, .moveAnnotation, .resizeAnnotation:
            break
        case let .draw(start, points):
            let current = draftCurrent ?? start
            commitAnnotation(start: start, current: current, points: points)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        let command = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)
        let character = event.charactersIgnoringModifiers?.lowercased()
        if event.keyCode == 53 {
            if selectedAnnotationID != nil {
                selectedAnnotationID = nil
                needsDisplay = true
            } else {
                onCancel?()
            }
        } else if event.keyCode == 51 || event.keyCode == 117 {
            if deleteSelectedAnnotation() {
                needsDisplay = true
            }
        } else if event.keyCode == 36 || event.keyCode == 76 {
            complete(with: .finish)
        } else if command, character == "z", !shift {
            if !annotations.isEmpty {
                let removed = annotations.removeLast()
                if removed.id == selectedAnnotationID {
                    selectedAnnotationID = nil
                }
                needsDisplay = true
            }
        } else if command, character == "c" {
            complete(with: .finish)
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        if let frozenImage {
            context.saveGState()
            context.interpolationQuality = .high
            context.draw(frozenImage, in: bounds)
            context.restoreGState()
        }

        let visibleSelection = phase == .selecting && selectionRect.isEmpty
            ? suggestedCandidate?.frame
            : selectionRect

        context.setFillColor(NSColor.black.withAlphaComponent(0.42).cgColor)
        context.fill(bounds)

        if let visibleSelection, !visibleSelection.isEmpty {
            redrawFrozenImage(in: visibleSelection, context: context)
            if phase == .editing {
                drawAnnotations(context: context)
                drawDraft(context: context)
                drawSelectedAnnotation(context: context)
            }
            if phase == .selectingText {
                drawTextRecognitionSelection(context: context)
                drawSelectionBorder(visibleSelection, context: context)
            } else {
                drawSelectionBorder(visibleSelection, context: context)
                drawSizeLabel(for: visibleSelection)
            }
        } else {
            drawInstruction()
        }

        if phase == .selecting, let suggestedCandidate {
            drawCandidateLabel(suggestedCandidate)
        }

        if phase == .editing, !selectionRect.isEmpty {
            drawToolbar(context: context)
            if selectedTool != nil || propertiesVisibleForAcceptance {
                drawPropertyPanel(context: context)
            }
        } else if let cursorPoint {
            drawMagnifier(at: cursorPoint, context: context)
        }
    }

    private func updateCursor(with event: NSEvent) -> CGPoint {
        let rawPoint = convert(event.locationInWindow, from: nil)
        let point = CGPoint(
            x: min(max(rawPoint.x, bounds.minX), bounds.maxX),
            y: min(max(rawPoint.y, bounds.minY), bounds.maxY)
        )
        cursorPoint = point
        return point
    }

    private func redrawFrozenImage(in rect: CGRect, context: CGContext) {
        if let frozenImage {
            context.saveGState()
            context.clip(to: rect)
            context.interpolationQuality = .high
            context.draw(frozenImage, in: bounds)
            context.restoreGState()
        } else {
            context.saveGState()
            context.setBlendMode(.clear)
            context.fill(rect)
            context.restoreGState()
        }
    }

    private func drawInstruction() {
        let text = "拖动选择区域，或单击自动选择窗口  ·  Esc 取消"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let rect = CGRect(
            x: bounds.midX - size.width / 2 - 18,
            y: bounds.midY - size.height / 2 - 11,
            width: size.width + 36,
            height: size.height + 22
        )
        NSColor(calibratedWhite: 0.08, alpha: 0.92).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        text.draw(at: CGPoint(x: rect.minX + 18, y: rect.minY + 11), withAttributes: attributes)
    }

    private func drawTextRecognitionSelection(context: CGContext) {
        context.setFillColor(NSColor.black.withAlphaComponent(0.24).cgColor)
        context.fill(selectionRect)

        if textSelectionRect.width >= 1, textSelectionRect.height >= 1 {
            redrawFrozenImage(in: textSelectionRect, context: context)
            drawSelectionBorder(textSelectionRect, context: context)
            drawSizeLabel(for: textSelectionRect)
        }

        let text = "拖动选择要识别的文字区域  ·  右键或 Esc 取消"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        var instructionRect = CGRect(
            x: selectionRect.midX - size.width / 2 - 14,
            y: selectionRect.maxY - size.height - 28,
            width: size.width + 28,
            height: size.height + 14
        )
        instructionRect.origin.x = min(
            max(instructionRect.minX, selectionRect.minX + 8),
            selectionRect.maxX - instructionRect.width - 8
        )
        instructionRect.origin.y = max(instructionRect.minY, selectionRect.minY + 8)
        NSColor(calibratedWhite: 0.05, alpha: 0.86).setFill()
        NSBezierPath(roundedRect: instructionRect, xRadius: 9, yRadius: 9).fill()
        text.draw(
            at: CGPoint(x: instructionRect.minX + 14, y: instructionRect.minY + 7),
            withAttributes: attributes
        )
    }

    private func drawSelectionBorder(_ rect: CGRect, context: CGContext) {
        let accent = NSColor(srgbRed: 0.18, green: 0.58, blue: 1, alpha: 1)
        context.setStrokeColor(accent.cgColor)
        context.setLineWidth(2)
        context.stroke(rect.insetBy(dx: 1, dy: 1))
        guard phase == .editing else {
            return
        }
        for handleRect in selectionHandleRects().values {
            context.setFillColor(NSColor.white.cgColor)
            context.fill(handleRect)
            context.setStrokeColor(accent.cgColor)
            context.setLineWidth(1.5)
            context.stroke(handleRect)
        }
    }

    private func drawSizeLabel(for rect: CGRect) {
        let text = "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded()))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        var labelRect = CGRect(
            x: rect.minX,
            y: rect.maxY + 7,
            width: size.width + 16,
            height: size.height + 10
        )
        if labelRect.maxY > bounds.maxY - 6 {
            labelRect.origin.y = rect.maxY - labelRect.height - 7
        }
        labelRect.origin.x = min(max(labelRect.minX, 6), bounds.maxX - labelRect.width - 6)
        NSColor(calibratedWhite: 0.08, alpha: 0.92).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 5, yRadius: 5).fill()
        text.draw(
            at: CGPoint(x: labelRect.minX + 8, y: labelRect.minY + 5),
            withAttributes: attributes
        )
    }

    private func drawCandidateLabel(_ candidate: QQCaptureSnappingCandidate) {
        let title = candidate.title.isEmpty
            ? candidate.applicationName
            : "\(candidate.applicationName) · \(candidate.title)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = title.size(withAttributes: attributes)
        let width = min(size.width + 18, max(120, candidate.frame.width))
        var rect = CGRect(
            x: candidate.frame.minX,
            y: candidate.frame.minY + 8,
            width: width,
            height: size.height + 10
        )
        rect.origin.x = min(max(rect.minX, 6), bounds.maxX - rect.width - 6)
        NSColor(calibratedWhite: 0.08, alpha: 0.88).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        title.draw(
            in: rect.insetBy(dx: 9, dy: 5),
            withAttributes: attributes
        )
    }

    private func toolbarButtons() -> [ToolbarButton] {
        let items: [(ToolbarItemID, String, String)] = [
            (.tool(.arrow), Tool.arrow.symbolName, Tool.arrow.label),
            (.tool(.pen), Tool.pen.symbolName, Tool.pen.label),
            (.tool(.pixelate), Tool.pixelate.symbolName, Tool.pixelate.label),
            (.tool(.ellipse), Tool.ellipse.symbolName, Tool.ellipse.label),
            (.tool(.rectangle), Tool.rectangle.symbolName, Tool.rectangle.label),
            (.tool(.step), Tool.step.symbolName, Tool.step.label),
            (.tool(.text), Tool.text.symbolName, Tool.text.label),
            (.undo, "arrow.uturn.backward", "撤销"),
            (.scrolling, CaptureMode.scrolling.symbolName, "长截图"),
            (.recording, "record.circle", "区域录屏"),
            (.recognizeText, "text.viewfinder", "识别文字"),
            (.translate, "translate", "翻译"),
            (.pin, "pin", "置顶"),
            (.save, "square.and.arrow.down", "另存为"),
            (.cancel, "xmark", "取消"),
            (.finish, "checkmark", "完成并复制")
        ]
        let toolbar = toolbarRect()
        let buttonSize: CGFloat = 32
        let gap: CGFloat = 2
        return items.enumerated().map { index, item in
            ToolbarButton(
                id: item.0,
                rect: CGRect(
                    x: toolbar.minX + 8 + CGFloat(index) * (buttonSize + gap),
                    y: toolbar.minY + 7,
                    width: buttonSize,
                    height: buttonSize
                ),
                symbolName: item.1,
                label: item.2
            )
        }
    }

    private func toolbarRect() -> CGRect {
        let buttonCount: CGFloat = 16
        let width = 16 + buttonCount * 32 + (buttonCount - 1) * 2
        let height: CGFloat = 46
        var rect = CGRect(
            x: selectionRect.maxX - width,
            y: selectionRect.minY - height - 10,
            width: width,
            height: height
        )
        if rect.minY < bounds.minY + 6 {
            rect.origin.y = selectionRect.maxY + 10
        }
        rect.origin.x = min(max(rect.minX, bounds.minX + 6), bounds.maxX - width - 6)
        rect.origin.y = min(max(rect.minY, bounds.minY + 6), bounds.maxY - height - 6)
        return rect
    }

    private func propertyPanelRect() -> CGRect {
        let toolbar = toolbarRect()
        let width: CGFloat = 272
        let height: CGFloat = 38
        var rect = CGRect(x: toolbar.minX, y: toolbar.minY - height - 6, width: width, height: height)
        if rect.minY < bounds.minY + 6 {
            rect.origin.y = toolbar.maxY + 6
        }
        rect.origin.x = min(max(rect.minX, bounds.minX + 6), bounds.maxX - width - 6)
        return rect
    }

    private func drawToolbar(context: CGContext) {
        let toolbar = toolbarRect()
        drawFloatingPanel(toolbar, context: context)

        let accent = NSColor(srgbRed: 0.18, green: 0.58, blue: 1, alpha: 1)
        for button in toolbarButtons() {
            let isSelected: Bool
            if case let .tool(tool) = button.id {
                isSelected = selectedTool == tool
                    || (propertiesVisibleForAcceptance && tool == .rectangle)
            } else {
                isSelected = button.id == .scrolling
                    && emphasizesScrollingAction
                    && annotations.isEmpty
            }
            let isHovered = hoveredToolbarItem == button.id
            let isDisabled = (button.id == .undo && annotations.isEmpty)
                || (button.id == .scrolling && !annotations.isEmpty)
                || (button.id == .recording && !annotations.isEmpty)
            if isSelected || isHovered || button.id == .finish {
                let fill: NSColor
                let border: NSColor
                if button.id == .finish {
                    fill = accent.withAlphaComponent(0.78)
                    border = NSColor.white.withAlphaComponent(0.34)
                } else if button.id == .cancel, isHovered {
                    fill = NSColor.systemRed.withAlphaComponent(0.66)
                    border = NSColor.white.withAlphaComponent(0.24)
                } else {
                    fill = isSelected
                        ? accent.withAlphaComponent(0.58)
                        : NSColor.white.withAlphaComponent(0.11)
                    border = NSColor.white.withAlphaComponent(isSelected ? 0.28 : 0.12)
                }
                let buttonPath = NSBezierPath(
                    roundedRect: button.rect,
                    xRadius: 10,
                    yRadius: 10
                )
                context.saveGState()
                if button.id == .finish {
                    context.setShadow(
                        offset: CGSize(width: 0, height: -2),
                        blur: 8,
                        color: accent.withAlphaComponent(0.28).cgColor
                    )
                }
                fill.setFill()
                buttonPath.fill()
                context.restoreGState()
                border.setStroke()
                buttonPath.lineWidth = 0.8
                buttonPath.stroke()
            }
            let color = NSColor.white.withAlphaComponent(isDisabled ? 0.28 : 0.94)
            drawSymbol(button.symbolName, color: color, in: button.rect.insetBy(dx: 7, dy: 7))
        }

        if let hoveredToolbarItem,
           let hovered = toolbarButtons().first(where: { $0.id == hoveredToolbarItem }) {
            drawTooltip(hovered.label, above: hovered.rect)
        } else if emphasizesScrollingAction,
                  annotations.isEmpty,
                  let scrolling = toolbarButtons().first(where: { $0.id == .scrolling }) {
            drawTooltip("点击这里开始区域长截图", above: scrolling.rect)
        }
    }

    private func drawPropertyPanel(context: CGContext) {
        let panel = propertyPanelRect()
        drawFloatingPanel(panel, context: context)
        if selectedTool == .pixelate {
            drawPixelatePropertyPanel(panel, context: context)
            return
        }
        let circleSize: CGFloat = 16
        for (index, color) in colors.enumerated() {
            let rect = CGRect(
                x: panel.minX + 10 + CGFloat(index) * 24,
                y: panel.midY - circleSize / 2,
                width: circleSize,
                height: circleSize
            )
            context.setFillColor(cgColor(color.value))
            context.fillEllipse(in: rect)
            context.setStrokeColor(
                (index == selectedColorIndex ? NSColor.white : NSColor.white.withAlphaComponent(0.24)).cgColor
            )
            context.setLineWidth(index == selectedColorIndex ? 2.5 : 1)
            context.strokeEllipse(in: rect.insetBy(dx: -2, dy: -2))
        }

        context.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: panel.minX + 205, y: panel.minY + 8))
        context.addLine(to: CGPoint(x: panel.minX + 205, y: panel.maxY - 8))
        context.strokePath()

        for (index, width) in lineWidths.enumerated() {
            let center = CGPoint(x: panel.minX + 224 + CGFloat(index) * 20, y: panel.midY)
            context.setFillColor(NSColor.white.withAlphaComponent(index == selectedLineWidthIndex ? 0.98 : 0.5).cgColor)
            context.fillEllipse(in: CGRect(
                x: center.x - width / 2,
                y: center.y - width / 2,
                width: width,
                height: width
            ))
            if index == selectedLineWidthIndex {
                context.setStrokeColor(NSColor(srgbRed: 0.18, green: 0.58, blue: 1, alpha: 1).cgColor)
                context.setLineWidth(2)
                context.strokeEllipse(in: CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16))
            }
        }
    }

    private func drawPixelatePropertyPanel(_ panel: CGRect, context: CGContext) {
        let accent = NSColor(srgbRed: 0.18, green: 0.58, blue: 1, alpha: 1)
        let options: [(PixelateEffect, String, CGRect)] = [
            (.mosaic, "马赛克", CGRect(x: panel.minX + 8, y: panel.minY + 6, width: 72, height: 26)),
            (.blur, "模糊", CGRect(x: panel.minX + 84, y: panel.minY + 6, width: 58, height: 26))
        ]
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        for (effect, label, rect) in options {
            let isSelected = effect == selectedPixelateEffect
            let fill = isSelected
                ? accent.withAlphaComponent(0.58)
                : NSColor.white.withAlphaComponent(0.08)
            fill.setFill()
            let path = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
            path.fill()
            NSColor.white.withAlphaComponent(isSelected ? 0.26 : 0.08).setStroke()
            path.lineWidth = 0.8
            path.stroke()
            let size = label.size(withAttributes: attributes)
            label.draw(
                at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                withAttributes: attributes
            )
        }

        context.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: panel.minX + 160, y: panel.minY + 8))
        context.addLine(to: CGPoint(x: panel.minX + 160, y: panel.maxY - 8))
        context.strokePath()

        for (index, width) in lineWidths.enumerated() {
            let center = CGPoint(x: panel.minX + 184 + CGFloat(index) * 32, y: panel.midY)
            context.setFillColor(NSColor.white.withAlphaComponent(index == selectedLineWidthIndex ? 0.98 : 0.5).cgColor)
            context.fillEllipse(in: CGRect(
                x: center.x - width / 2,
                y: center.y - width / 2,
                width: width,
                height: width
            ))
            if index == selectedLineWidthIndex {
                context.setStrokeColor(accent.cgColor)
                context.setLineWidth(2)
                context.strokeEllipse(in: CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16))
            }
        }
    }

    private func drawFloatingPanel(_ rect: CGRect, context: CGContext) {
        let radius = min(18, rect.height / 2)
        let path = CGPath(
            roundedRect: rect,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )

        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -6),
            blur: 20,
            color: NSColor.black.withAlphaComponent(0.42).cgColor
        )
        context.setFillColor(NSColor.black.withAlphaComponent(0.44).cgColor)
        context.addPath(path)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(path)
        context.clip()
        if let backdrop = preparedGlassBackdrop(for: rect) {
            context.interpolationQuality = .high
            context.draw(backdrop.image, in: backdrop.drawRect)
        }
        if let tint = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [
                NSColor(srgbRed: 0.14, green: 0.16, blue: 0.19, alpha: 0.58).cgColor,
                NSColor(srgbRed: 0.06, green: 0.07, blue: 0.09, alpha: 0.68).cgColor,
                NSColor(srgbRed: 0.02, green: 0.03, blue: 0.04, alpha: 0.76).cgColor
            ] as CFArray,
            locations: [0, 0.46, 1]
        ) {
            context.drawLinearGradient(
                tint,
                start: CGPoint(x: rect.midX, y: rect.maxY),
                end: CGPoint(x: rect.midX, y: rect.minY),
                options: []
            )
        }
        context.restoreGState()

        context.setStrokeColor(NSColor.white.withAlphaComponent(0.28).cgColor)
        context.setLineWidth(0.8)
        context.addPath(path)
        context.strokePath()

        let innerRect = rect.insetBy(dx: 1.25, dy: 1.25)
        let innerPath = CGPath(
            roundedRect: innerRect,
            cornerWidth: max(0, radius - 1.25),
            cornerHeight: max(0, radius - 1.25),
            transform: nil
        )
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.28).cgColor)
        context.setLineWidth(0.75)
        context.addPath(innerPath)
        context.strokePath()

        context.saveGState()
        context.addPath(path)
        context.clip()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.34).cgColor)
        context.setLineWidth(0.9)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: rect.minX + radius, y: rect.maxY - 0.75))
        context.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY - 0.75))
        context.strokePath()
        context.restoreGState()
    }

    private func preparedGlassBackdrop(for panelRect: CGRect) -> GlassBackdrop? {
        let usesToolbarCache = panelRect.height >= 42
        let cached = usesToolbarCache ? toolbarGlassBackdrop : propertyGlassBackdrop
        if let cached, cached.panelRect.equalTo(panelRect) {
            return cached
        }
        guard let frozenImage else {
            return nil
        }

        let drawRect = panelRect
            .insetBy(dx: -18, dy: -18)
            .intersection(bounds)
        let pixelScaleX = CGFloat(frozenImage.width) / bounds.width
        let pixelScaleY = CGFloat(frozenImage.height) / bounds.height
        let sourceRect = CGRect(
            x: drawRect.minX * pixelScaleX,
            y: (bounds.height - drawRect.maxY) * pixelScaleY,
            width: drawRect.width * pixelScaleX,
            height: drawRect.height * pixelScaleY
        ).integral.intersection(CGRect(
            x: 0,
            y: 0,
            width: frozenImage.width,
            height: frozenImage.height
        ))
        guard sourceRect.width >= 2,
              sourceRect.height >= 2,
              let croppedImage = frozenImage.cropping(to: sourceRect) else {
            return nil
        }

        let source = CIImage(cgImage: croppedImage)
        let blurred = source
            .clampedToExtent()
            .applyingFilter(
                "CIGaussianBlur",
                parameters: [kCIInputRadiusKey: 12 * scaleFactor]
            )
            .cropped(to: source.extent)
        guard let image = previewCIContext.createCGImage(blurred, from: source.extent) else {
            return nil
        }
        let backdrop = GlassBackdrop(panelRect: panelRect, drawRect: drawRect, image: image)
        if usesToolbarCache {
            toolbarGlassBackdrop = backdrop
        } else {
            propertyGlassBackdrop = backdrop
        }
        return backdrop
    }

    private func drawSymbol(_ name: String, color: NSColor, in rect: CGRect) {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return
        }
        let pointConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        let colorConfiguration = NSImage.SymbolConfiguration(paletteColors: [color])
        let configured = image.withSymbolConfiguration(pointConfiguration.applying(colorConfiguration)) ?? image
        configured.draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    private func drawTooltip(_ text: String, above rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        var tooltip = CGRect(
            x: rect.midX - size.width / 2 - 7,
            y: rect.maxY + 8,
            width: size.width + 14,
            height: size.height + 8
        )
        tooltip.origin.x = min(max(tooltip.minX, 4), bounds.maxX - tooltip.width - 4)
        NSColor(calibratedWhite: 0.04, alpha: 0.94).setFill()
        NSBezierPath(roundedRect: tooltip, xRadius: 5, yRadius: 5).fill()
        text.draw(at: CGPoint(x: tooltip.minX + 7, y: tooltip.minY + 4), withAttributes: attributes)
    }

    private func handleToolbarItem(_ item: ToolbarItemID) {
        switch item {
        case let .tool(tool):
            propertiesVisibleForAcceptance = false
            selectedAnnotationID = nil
            selectedTool = selectedTool == tool ? nil : tool
            resetCursorRects()
            needsDisplay = true
        case .undo:
            if !annotations.isEmpty {
                let removed = annotations.removeLast()
                if removed.id == selectedAnnotationID {
                    selectedAnnotationID = nil
                }
                needsDisplay = true
            }
        case .scrolling:
            if annotations.isEmpty {
                complete(with: .scrolling)
            }
        case .recording:
            if annotations.isEmpty {
                complete(with: .recording)
            }
        case .recognizeText:
            beginTextRecognitionSelection()
        case .translate:
            complete(with: .translate)
        case .pin:
            complete(with: .pin)
        case .save:
            complete(with: .save)
        case .cancel:
            onCancel?()
        case .finish:
            complete(with: .finish)
        }
    }

    private func beginTextRecognitionSelection() {
        commitTextEditorIfNeeded()
        selectedTool = nil
        selectedAnnotationID = nil
        propertiesVisibleForAcceptance = false
        hoveredToolbarItem = nil
        textSelectionRect = .zero
        dragMode = nil
        phase = .selectingText
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    private func handlePropertyPanelClick(at point: CGPoint) -> Bool {
        guard (selectedTool != nil || propertiesVisibleForAcceptance),
              propertyPanelRect().contains(point) else {
            return false
        }
        if selectedTool == nil {
            propertiesVisibleForAcceptance = false
            selectedTool = .rectangle
        }
        let panel = propertyPanelRect()
        if selectedTool == .pixelate {
            let mosaicRect = CGRect(x: panel.minX + 8, y: panel.minY + 6, width: 72, height: 26)
            let blurRect = CGRect(x: panel.minX + 84, y: panel.minY + 6, width: 58, height: 26)
            if mosaicRect.contains(point) {
                selectedPixelateEffect = .mosaic
                needsDisplay = true
                return true
            }
            if blurRect.contains(point) {
                selectedPixelateEffect = .blur
                needsDisplay = true
                return true
            }
            for index in lineWidths.indices {
                let center = CGPoint(x: panel.minX + 184 + CGFloat(index) * 32, y: panel.midY)
                if hypot(point.x - center.x, point.y - center.y) <= 10 {
                    selectedLineWidthIndex = index
                    needsDisplay = true
                    return true
                }
            }
            return true
        }
        for index in colors.indices {
            let center = CGPoint(x: panel.minX + 18 + CGFloat(index) * 24, y: panel.midY)
            if hypot(point.x - center.x, point.y - center.y) <= 11 {
                selectedColorIndex = index
                applyColorToSelectedAnnotation(colors[index].value)
                needsDisplay = true
                return true
            }
        }
        for index in lineWidths.indices {
            let center = CGPoint(x: panel.minX + 224 + CGFloat(index) * 20, y: panel.midY)
            if hypot(point.x - center.x, point.y - center.y) <= 10 {
                selectedLineWidthIndex = index
                applyLineWidthToSelectedAnnotation(index: index)
                needsDisplay = true
                return true
            }
        }
        return true
    }

    private func complete(with action: QQCaptureOverlayAction) {
        commitTextEditorIfNeeded()
        guard selectionRect.width >= 4, selectionRect.height >= 4 else {
            return
        }
        onComplete?(selectionRect, annotations, action)
    }

    private func beginTextEditing(at point: CGPoint) {
        commitTextEditorIfNeeded()
        let field = NSTextField(frame: CGRect(x: point.x, y: point.y - 2, width: 180, height: 30))
        field.stringValue = ""
        field.placeholderString = "输入文字"
        field.font = .systemFont(ofSize: 18, weight: .medium)
        field.textColor = nsColor(colors[selectedColorIndex].value)
        field.backgroundColor = NSColor.black.withAlphaComponent(0.68)
        field.isBezeled = false
        field.focusRingType = .none
        field.delegate = self
        field.target = self
        field.action = #selector(commitTextField(_:))
        addSubview(field)
        textEditor = field
        textEditorContext = .annotationText(
            origin: point,
            color: colors[selectedColorIndex].value
        )
        window?.makeFirstResponder(field)
    }

    private func beginStepNoteEditing(for step: StepAnnotation) {
        commitTextEditorIfNeeded()
        let center = viewPoint(from: step.center)
        let diameter = CGFloat(step.diameter) / scaleFactor
        let origin = CGPoint(
            x: center.x + diameter / 2 + max(5, diameter * 0.18),
            y: center.y - 14
        )
        let availableWidth = selectionRect.maxX - origin.x - 4
        let field = NSTextField(frame: CGRect(
            x: origin.x,
            y: origin.y,
            width: min(220, max(84, availableWidth)),
            height: 28
        ))
        field.stringValue = step.note ?? ""
        field.placeholderString = "输入备注（可留空）"
        field.font = .systemFont(ofSize: max(12, diameter * 0.5), weight: .semibold)
        field.textColor = nsColor(step.fillColor)
        field.backgroundColor = NSColor.black.withAlphaComponent(0.68)
        field.isBezeled = false
        field.focusRingType = .none
        field.delegate = self
        field.target = self
        field.action = #selector(commitTextField(_:))
        addSubview(field)
        textEditor = field
        textEditorContext = .stepNote(id: step.id)
        window?.makeFirstResponder(field)
    }

    private func beginArrowNoteEditing(for arrow: ArrowAnnotation) {
        commitTextEditorIfNeeded()
        let fontSize = CGFloat(arrow.noteFontSize) / scaleFactor
        let fieldSize = CGSize(width: 180, height: 28)
        let projectOrigin = arrow.noteOrigin(
            width: Double(fieldSize.width * scaleFactor),
            height: Double(fieldSize.height * scaleFactor)
        )
        let origin = viewPoint(from: projectOrigin)
        let field = NSTextField(frame: CGRect(
            x: origin.x,
            y: origin.y,
            width: fieldSize.width,
            height: fieldSize.height
        ))
        field.stringValue = arrow.note ?? ""
        field.placeholderString = "输入备注（可留空）"
        field.font = .systemFont(ofSize: max(12, fontSize), weight: .semibold)
        field.textColor = nsColor(arrow.color)
        field.backgroundColor = NSColor.black.withAlphaComponent(0.68)
        field.isBezeled = false
        field.focusRingType = .none
        field.delegate = self
        field.target = self
        field.action = #selector(commitTextField(_:))
        addSubview(field)
        textEditor = field
        textEditorContext = .arrowNote(id: arrow.id)
        window?.makeFirstResponder(field)
    }

    @objc
    private func commitTextField(_ sender: NSTextField) {
        commitTextEditorIfNeeded()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitTextEditorIfNeeded()
    }

    private func commitTextEditorIfNeeded() {
        guard let field = textEditor else {
            return
        }
        textEditor = nil
        let editorContext = textEditorContext
        textEditorContext = nil
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.removeFromSuperview()
        switch editorContext {
        case let .annotationText(origin, color):
            if !text.isEmpty, selectionRect.contains(origin) {
                annotations.append(.text(TextAnnotation(
                    position: annotationPoint(from: origin),
                    text: text,
                    color: color,
                    fontSize: Double(18 * scaleFactor)
                )))
            }
        case let .stepNote(id):
            if let index = annotations.firstIndex(where: { $0.id == id }),
               case .step(var step) = annotations[index] {
                step.note = text.isEmpty ? nil : text
                annotations[index] = .step(step)
            }
        case let .arrowNote(id):
            if let index = annotations.firstIndex(where: { $0.id == id }),
               case .arrow(var arrow) = annotations[index] {
                arrow.note = text.isEmpty ? nil : text
                annotations[index] = .arrow(arrow)
            }
        case nil:
            break
        }
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    private func commitAnnotation(
        start: AnnotationPoint,
        current: AnnotationPoint,
        points: [AnnotationPoint]
    ) {
        guard let selectedTool else {
            return
        }
        let color = colors[selectedColorIndex].value
        let lineWidth = Double(lineWidths[selectedLineWidthIndex] * scaleFactor)
        let rect = AnnotationRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        let item: AnnotationItem?
        switch selectedTool {
        case .rectangle:
            item = rect.width >= 2 && rect.height >= 2
                ? .rectangle(RectangleAnnotation(rect: rect, color: color, lineWidth: lineWidth))
                : nil
        case .ellipse:
            item = rect.width >= 2 && rect.height >= 2
                ? .ellipse(EllipseAnnotation(rect: rect, color: color, lineWidth: lineWidth))
                : nil
        case .arrow:
            item = hypot(current.x - start.x, current.y - start.y) >= 3
                ? .arrow(ArrowAnnotation(
                    start: start,
                    end: current,
                    color: color,
                    lineWidth: lineWidth,
                    noteFontSize: Double(14 * scaleFactor)
                ))
                : nil
        case .pen:
            let allPoints = points + [current]
            item = allPoints.count >= 2
                ? .pen(PenAnnotation(points: allPoints, color: color, lineWidth: lineWidth))
                : nil
        case .text:
            item = nil
        case .step:
            let number = annotations.reduce(0) { partial, annotation in
                if case let .step(value) = annotation {
                    return max(partial, value.number)
                }
                return partial
            } + 1
            item = .step(StepAnnotation(
                center: current,
                number: number,
                diameter: Double(28 * scaleFactor),
                fillColor: color
            ))
        case .pixelate:
            item = rect.width >= 4 && rect.height >= 4
                ? .pixelate(PixelateAnnotation(
                    rect: rect,
                    scale: selectedPixelateScale,
                    effect: selectedPixelateEffect
                ))
                : nil
        }
        if let item {
            annotations.append(item)
            if isEditableAnnotation(item) {
                selectEditableAnnotation(item)
            }
            if case let .step(step) = item {
                beginStepNoteEditing(for: step)
            } else if case let .arrow(arrow) = item {
                beginArrowNoteEditing(for: arrow)
            }
        }
    }

    private func drawAnnotations(context: CGContext) {
        context.saveGState()
        context.clip(to: selectionRect)
        for annotation in annotations {
            draw(annotation, context: context)
        }
        context.restoreGState()
    }

    private func drawDraft(context: CGContext) {
        guard case let .draw(start, points) = dragMode,
              let current = draftCurrent,
              let tool = selectedTool else {
            return
        }
        let color = colors[selectedColorIndex].value
        let width = Double(lineWidths[selectedLineWidthIndex] * scaleFactor)
        let rect = AnnotationRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        let annotation: AnnotationItem?
        switch tool {
        case .rectangle:
            annotation = .rectangle(RectangleAnnotation(rect: rect, color: color, lineWidth: width))
        case .ellipse:
            annotation = .ellipse(EllipseAnnotation(rect: rect, color: color, lineWidth: width))
        case .arrow:
            annotation = .arrow(ArrowAnnotation(start: start, end: current, color: color, lineWidth: width))
        case .pen:
            annotation = .pen(PenAnnotation(points: points + [current], color: color, lineWidth: width))
        case .step:
            annotation = .step(StepAnnotation(center: current, number: annotations.count + 1, diameter: Double(28 * scaleFactor), fillColor: color))
        case .pixelate:
            annotation = .pixelate(PixelateAnnotation(
                rect: rect,
                scale: selectedPixelateScale,
                effect: selectedPixelateEffect
            ))
        case .text:
            annotation = nil
        }
        if let annotation {
            context.saveGState()
            context.clip(to: selectionRect)
            draw(annotation, context: context)
            context.restoreGState()
        }
    }

    private func draw(_ annotation: AnnotationItem, context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setLineCap(.round)
        context.setLineJoin(.round)
        switch annotation {
        case let .arrow(value):
            let points = ArrowShapeGeometry(value).points.map(viewPoint(from:))
            if let first = points.first {
                context.beginPath()
                context.move(to: first)
                points.dropFirst().forEach(context.addLine(to:))
                context.closePath()
                context.setFillColor(cgColor(value.color))
                context.fillPath()
            }
            if let note = value.note {
                let noteAttributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(
                        ofSize: CGFloat(value.noteFontSize) / scaleFactor,
                        weight: .semibold
                    ),
                    .foregroundColor: nsColor(value.color)
                ]
                let noteSize = note.size(withAttributes: noteAttributes)
                let noteOrigin = value.noteOrigin(
                    width: Double(noteSize.width * scaleFactor),
                    height: Double(noteSize.height * scaleFactor)
                )
                note.draw(
                    at: viewPoint(from: noteOrigin),
                    withAttributes: noteAttributes
                )
            }
        case let .rectangle(value):
            let rect = viewRect(from: value.rect)
            let width = CGFloat(value.lineWidth) / scaleFactor
            if let fillColor = value.fillColor {
                context.setFillColor(cgColor(fillColor))
                context.fill(rect)
            }
            context.setStrokeColor(cgColor(value.color))
            context.setLineWidth(width)
            context.stroke(rect)
        case let .ellipse(value):
            context.setStrokeColor(cgColor(value.color))
            context.setLineWidth(CGFloat(value.lineWidth) / scaleFactor)
            context.strokeEllipse(in: viewRect(from: value.rect))
        case let .pen(value):
            guard let first = value.points.first else { return }
            context.setStrokeColor(cgColor(value.color))
            context.setLineWidth(CGFloat(value.lineWidth) / scaleFactor)
            context.move(to: viewPoint(from: first))
            for point in value.points.dropFirst() {
                context.addLine(to: viewPoint(from: point))
            }
            context.strokePath()
        case let .text(value):
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: CGFloat(value.fontSize) / scaleFactor, weight: .medium),
                .foregroundColor: nsColor(value.color)
            ]
            value.text.draw(at: viewPoint(from: value.position), withAttributes: attributes)
        case let .step(value):
            let center = viewPoint(from: value.center)
            let diameter = CGFloat(value.diameter) / scaleFactor
            let rect = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
            context.setFillColor(cgColor(value.fillColor))
            context.fillEllipse(in: rect)
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
            context.setLineWidth(1.5)
            context.strokeEllipse(in: rect.insetBy(dx: 1, dy: 1))
            let text = String(value.number)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: max(11, diameter * 0.52), weight: .bold),
                .foregroundColor: nsColor(value.textColor)
            ]
            let size = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), withAttributes: attributes)
            if let note = value.note {
                let noteAttributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: max(11, diameter * 0.5), weight: .semibold),
                    .foregroundColor: nsColor(value.fillColor)
                ]
                let noteSize = note.size(withAttributes: noteAttributes)
                note.draw(at: CGPoint(
                    x: rect.maxX + max(5, diameter * 0.18),
                    y: center.y - noteSize.height / 2
                ), withAttributes: noteAttributes)
            }
        case let .pixelate(value):
            drawPixelatedPreview(value, context: context)
        case let .line(value):
            context.setStrokeColor(cgColor(value.color))
            context.setLineWidth(CGFloat(value.lineWidth) / scaleFactor)
            context.move(to: viewPoint(from: value.start))
            context.addLine(to: viewPoint(from: value.end))
            context.strokePath()
        case let .highlight(value):
            guard let first = value.points.first else { return }
            context.setStrokeColor(cgColor(value.color).copy(alpha: CGFloat(value.opacity)) ?? cgColor(value.color))
            context.setLineWidth(CGFloat(value.lineWidth) / scaleFactor)
            context.move(to: viewPoint(from: first))
            for point in value.points.dropFirst() {
                context.addLine(to: viewPoint(from: point))
            }
            context.strokePath()
        case let .redaction(value):
            context.setFillColor(cgColor(value.color))
            context.fill(viewRect(from: value.rect))
        case let .spotlight(value):
            let path = CGMutablePath()
            path.addRect(selectionRect)
            path.addEllipse(in: viewRect(from: value.focusRect))
            context.addPath(path)
            context.setFillColor(NSColor.black.withAlphaComponent(value.dimOpacity).cgColor)
            context.drawPath(using: .eoFill)
        }
    }

    private func drawPixelatedPreview(
        _ pixelate: PixelateAnnotation,
        context: CGContext
    ) {
        let rect = viewRect(from: pixelate.rect).intersection(selectionRect)
        guard rect.width >= 2, rect.height >= 2 else {
            return
        }

        if let frozenImage {
            let pixelScaleX = CGFloat(frozenImage.width) / bounds.width
            let pixelScaleY = CGFloat(frozenImage.height) / bounds.height
            let sourceRect = CGRect(
                x: rect.minX * pixelScaleX,
                y: (bounds.height - rect.maxY) * pixelScaleY,
                width: rect.width * pixelScaleX,
                height: rect.height * pixelScaleY
            ).integral.intersection(CGRect(
                x: 0,
                y: 0,
                width: frozenImage.width,
                height: frozenImage.height
            ))
            if pixelate.effect == .blur,
               sourceRect.width >= 2,
               sourceRect.height >= 2,
                let source = frozenImage.cropping(to: sourceRect) {
                let image = CIImage(cgImage: source)
                let blurred = AnnotationObscurationFilter.apply(
                    to: image,
                    effect: .blur,
                    scale: pixelate.scale
                )
                if let output = previewCIContext.createCGImage(blurred, from: image.extent) {
                    context.saveGState()
                    context.clip(to: rect)
                    context.interpolationQuality = .high
                    context.draw(output, in: rect)
                    context.restoreGState()
                    context.setStrokeColor(NSColor.white.withAlphaComponent(0.28).cgColor)
                    context.setLineWidth(1)
                    context.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
                    return
                }
            }

            let blockSize = max(4, CGFloat(pixelate.scale) / scaleFactor)
            let reducedWidth = max(1, Int(ceil(rect.width / blockSize)))
            let reducedHeight = max(1, Int(ceil(rect.height / blockSize)))
            if sourceRect.width >= 2,
               sourceRect.height >= 2,
               let source = frozenImage.cropping(to: sourceRect),
               let reducedContext = CGContext(
                   data: nil,
                   width: reducedWidth,
                   height: reducedHeight,
                   bitsPerComponent: 8,
                   bytesPerRow: 0,
                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
               ) {
                reducedContext.interpolationQuality = .low
                reducedContext.draw(source, in: CGRect(
                    x: 0,
                    y: 0,
                    width: reducedWidth,
                    height: reducedHeight
                ))
                if let reducedImage = reducedContext.makeImage() {
                    context.saveGState()
                    context.clip(to: rect)
                    context.interpolationQuality = .none
                    context.draw(reducedImage, in: rect)
                    context.restoreGState()
                    context.setStrokeColor(NSColor.white.withAlphaComponent(0.28).cgColor)
                    context.setLineWidth(1)
                    context.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
                    return
                }
            }
        }

        context.setFillColor(NSColor.black.withAlphaComponent(0.28).cgColor)
        context.fill(rect)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.24).cgColor)
        context.setLineWidth(1)
        context.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
    }

    private var selectedPixelateScale: Double {
        let sizes: [CGFloat] = selectedPixelateEffect == .mosaic
            ? [8, 12, 18]
            : [10, 16, 24]
        return Double(sizes[selectedLineWidthIndex] * scaleFactor)
    }

    private var selectedAnnotation: AnnotationItem? {
        guard let selectedAnnotationID else {
            return nil
        }
        return annotations.first(where: { $0.id == selectedAnnotationID })
    }

    private func isEditableAnnotation(_ annotation: AnnotationItem) -> Bool {
        switch annotation {
        case .step, .arrow, .ellipse, .rectangle:
            true
        default:
            false
        }
    }

    private func tool(for annotation: AnnotationItem) -> Tool? {
        switch annotation {
        case .step:
            .step
        case .arrow:
            .arrow
        case .ellipse:
            .ellipse
        case .rectangle:
            .rectangle
        default:
            nil
        }
    }

    private func editableAnnotation(at point: CGPoint) -> AnnotationItem? {
        guard selectionRect.contains(point) else {
            return nil
        }
        let projectPoint = annotationPoint(from: point)
        return annotations.reversed().first(where: {
            isEditableAnnotation($0)
                && $0.hitTest(projectPoint, tolerance: Double(7 * scaleFactor))
        })
    }

    private func selectEditableAnnotation(_ annotation: AnnotationItem) {
        guard let tool = tool(for: annotation) else {
            return
        }
        selectedAnnotationID = annotation.id
        selectedTool = tool
        if let color = editableColor(of: annotation),
           let index = colors.indices.min(by: {
               colorDistance(colors[$0].value, color) < colorDistance(colors[$1].value, color)
           }) {
            selectedColorIndex = index
        }
        switch annotation {
        case let .arrow(value):
            selectedLineWidthIndex = nearestLineWidthIndex(to: CGFloat(value.lineWidth) / scaleFactor)
        case let .rectangle(value):
            selectedLineWidthIndex = nearestLineWidthIndex(to: CGFloat(value.lineWidth) / scaleFactor)
        case let .ellipse(value):
            selectedLineWidthIndex = nearestLineWidthIndex(to: CGFloat(value.lineWidth) / scaleFactor)
        case let .step(value):
            let diameters: [CGFloat] = [24, 28, 34]
            let diameter = CGFloat(value.diameter) / scaleFactor
            selectedLineWidthIndex = diameters.indices.min(by: {
                abs(diameters[$0] - diameter) < abs(diameters[$1] - diameter)
            }) ?? 1
        default:
            break
        }
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    private func editableColor(of annotation: AnnotationItem) -> AnnotationColor? {
        switch annotation {
        case let .step(value):
            value.fillColor
        case let .arrow(value):
            value.color
        case let .ellipse(value):
            value.color
        case let .rectangle(value):
            value.color
        default:
            nil
        }
    }

    private func colorDistance(_ lhs: AnnotationColor, _ rhs: AnnotationColor) -> Double {
        let red = lhs.red - rhs.red
        let green = lhs.green - rhs.green
        let blue = lhs.blue - rhs.blue
        let alpha = lhs.alpha - rhs.alpha
        return red * red + green * green + blue * blue + alpha * alpha
    }

    private func nearestLineWidthIndex(to width: CGFloat) -> Int {
        lineWidths.indices.min(by: {
            abs(lineWidths[$0] - width) < abs(lineWidths[$1] - width)
        }) ?? 0
    }

    private func applyColorToSelectedAnnotation(_ color: AnnotationColor) {
        guard let annotation = selectedAnnotation else {
            return
        }
        let updated: AnnotationItem
        switch annotation {
        case .step(var value):
            value.fillColor = color
            updated = .step(value)
        case .arrow(var value):
            value.color = color
            updated = .arrow(value)
        case .ellipse(var value):
            value.color = color
            updated = .ellipse(value)
        case .rectangle(var value):
            value.color = color
            updated = .rectangle(value)
        default:
            return
        }
        replaceAnnotation(id: annotation.id, with: updated)
    }

    private func applyLineWidthToSelectedAnnotation(index: Int) {
        guard let annotation = selectedAnnotation else {
            return
        }
        let width = Double(lineWidths[index] * scaleFactor)
        let updated: AnnotationItem
        switch annotation {
        case .step(var value):
            let diameters: [CGFloat] = [24, 28, 34]
            value.diameter = Double(diameters[index] * scaleFactor)
            updated = .step(value)
        case .arrow(var value):
            value.lineWidth = width
            updated = .arrow(value)
        case .ellipse(var value):
            value.lineWidth = width
            updated = .ellipse(value)
        case .rectangle(var value):
            value.lineWidth = width
            updated = .rectangle(value)
        default:
            return
        }
        replaceAnnotation(id: annotation.id, with: updated)
    }

    private func replaceAnnotation(id: UUID, with annotation: AnnotationItem) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else {
            return
        }
        annotations[index] = annotation
    }

    @discardableResult
    private func deleteSelectedAnnotation() -> Bool {
        guard let selectedAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == selectedAnnotationID }) else {
            return false
        }
        annotations.remove(at: index)
        self.selectedAnnotationID = nil
        window?.invalidateCursorRects(for: self)
        return true
    }

    private func selectedAnnotationHandleRects() -> [AnnotationHandle: CGRect] {
        guard let annotation = selectedAnnotation else {
            return [:]
        }
        let handleSize: CGFloat = 8
        let centers: [AnnotationHandle: CGPoint]
        switch annotation {
        case let .arrow(value):
            centers = [
                .arrowStart: viewPoint(from: value.start),
                .arrowEnd: viewPoint(from: value.end)
            ]
        case .rectangle, .ellipse:
            let rect = viewRect(from: annotation.bounds)
            centers = [
                .topLeft: CGPoint(x: rect.minX, y: rect.maxY),
                .topRight: CGPoint(x: rect.maxX, y: rect.maxY),
                .bottomLeft: CGPoint(x: rect.minX, y: rect.minY),
                .bottomRight: CGPoint(x: rect.maxX, y: rect.minY)
            ]
        default:
            return [:]
        }
        return centers.mapValues {
            CGRect(
                x: $0.x - handleSize / 2,
                y: $0.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
        }
    }

    private func selectedAnnotationHandle(at point: CGPoint) -> AnnotationHandle? {
        selectedAnnotationHandleRects().first(where: {
            $0.value.insetBy(dx: -6, dy: -6).contains(point)
        })?.key
    }

    private func resizedAnnotation(
        _ annotation: AnnotationItem,
        handle: AnnotationHandle,
        to point: AnnotationPoint
    ) -> AnnotationItem {
        switch annotation {
        case .arrow(var value):
            if handle == .arrowStart {
                value.start = point
            } else if handle == .arrowEnd {
                value.end = point
            }
            return .arrow(value)
        case .rectangle(var value):
            value.rect = resizedAnnotationRect(value.rect, handle: handle, to: point)
            return .rectangle(value)
        case .ellipse(var value):
            value.rect = resizedAnnotationRect(value.rect, handle: handle, to: point)
            return .ellipse(value)
        default:
            return annotation
        }
    }

    private func resizedAnnotationRect(
        _ original: AnnotationRect,
        handle: AnnotationHandle,
        to point: AnnotationPoint
    ) -> AnnotationRect {
        let rect = original.normalized
        let minimum = Double(8 * scaleFactor)
        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY
        switch handle {
        case .topLeft:
            minX = min(point.x, maxX - minimum)
            maxY = max(point.y, minY + minimum)
        case .topRight:
            maxX = max(point.x, minX + minimum)
            maxY = max(point.y, minY + minimum)
        case .bottomLeft:
            minX = min(point.x, maxX - minimum)
            minY = min(point.y, maxY - minimum)
        case .bottomRight:
            maxX = max(point.x, minX + minimum)
            minY = min(point.y, maxY - minimum)
        case .arrowStart, .arrowEnd:
            return rect
        }
        return AnnotationRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    private func drawSelectedAnnotation(context: CGContext) {
        guard let annotation = selectedAnnotation else {
            return
        }
        let accent = NSColor(srgbRed: 0.18, green: 0.58, blue: 1, alpha: 1)
        let outline = viewRect(from: annotation.bounds).insetBy(dx: -4, dy: -4)
        context.saveGState()
        context.clip(to: selectionRect)
        context.setStrokeColor(accent.cgColor)
        context.setLineWidth(1.25)
        context.setLineDash(phase: 0, lengths: [4, 3])
        context.stroke(outline)
        context.setLineDash(phase: 0, lengths: [])
        for (handle, rect) in selectedAnnotationHandleRects() {
            context.setFillColor(NSColor.white.cgColor)
            context.setStrokeColor(accent.cgColor)
            context.setLineWidth(1.5)
            if handle == .arrowStart || handle == .arrowEnd {
                context.fillEllipse(in: rect)
                context.strokeEllipse(in: rect)
            } else {
                context.fill(rect)
                context.stroke(rect)
            }
        }
        context.restoreGState()
    }

    private func selectionHandleRects() -> [SelectionHandle: CGRect] {
        guard !selectionRect.isEmpty else { return [:] }
        let size: CGFloat = 7
        let centers: [SelectionHandle: CGPoint] = [
            .left: CGPoint(x: selectionRect.minX, y: selectionRect.midY),
            .right: CGPoint(x: selectionRect.maxX, y: selectionRect.midY),
            .top: CGPoint(x: selectionRect.midX, y: selectionRect.maxY),
            .bottom: CGPoint(x: selectionRect.midX, y: selectionRect.minY),
            .topLeft: CGPoint(x: selectionRect.minX, y: selectionRect.maxY),
            .topRight: CGPoint(x: selectionRect.maxX, y: selectionRect.maxY),
            .bottomLeft: CGPoint(x: selectionRect.minX, y: selectionRect.minY),
            .bottomRight: CGPoint(x: selectionRect.maxX, y: selectionRect.minY)
        ]
        return centers.mapValues {
            CGRect(x: $0.x - size / 2, y: $0.y - size / 2, width: size, height: size)
        }
    }

    private func selectionHandle(at point: CGPoint) -> SelectionHandle? {
        selectionHandleRects().first(where: { $0.value.insetBy(dx: -6, dy: -6).contains(point) })?.key
    }

    private func movedSelection(_ rect: CGRect, dx: CGFloat, dy: CGFloat) -> CGRect {
        var moved = rect.offsetBy(dx: dx, dy: dy)
        if moved.minX < bounds.minX { moved.origin.x = bounds.minX }
        if moved.maxX > bounds.maxX { moved.origin.x = bounds.maxX - moved.width }
        if moved.minY < bounds.minY { moved.origin.y = bounds.minY }
        if moved.maxY > bounds.maxY { moved.origin.y = bounds.maxY - moved.height }
        return moved
    }

    private func resizedSelection(
        _ rect: CGRect,
        handle: SelectionHandle,
        dx: CGFloat,
        dy: CGFloat
    ) -> CGRect {
        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY
        switch handle {
        case .left: minX += dx
        case .right: maxX += dx
        case .top: maxY += dy
        case .bottom: minY += dy
        case .topLeft:
            minX += dx
            maxY += dy
        case .topRight:
            maxX += dx
            maxY += dy
        case .bottomLeft:
            minX += dx
            minY += dy
        case .bottomRight:
            maxX += dx
            minY += dy
        }
        let minimum: CGFloat = 24
        if maxX - minX < minimum {
            if handle == .left || handle == .topLeft || handle == .bottomLeft {
                minX = maxX - minimum
            } else {
                maxX = minX + minimum
            }
        }
        if maxY - minY < minimum {
            if handle == .bottom || handle == .bottomLeft || handle == .bottomRight {
                minY = maxY - minimum
            } else {
                maxY = minY + minimum
            }
        }
        minX = max(bounds.minX, minX)
        maxX = min(bounds.maxX, maxX)
        minY = max(bounds.minY, minY)
        maxY = min(bounds.maxY, maxY)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func clampedToSelection(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, selectionRect.minX), selectionRect.maxX),
            y: min(max(point.y, selectionRect.minY), selectionRect.maxY)
        )
    }

    private func annotationPoint(from point: CGPoint) -> AnnotationPoint {
        AnnotationPoint(
            x: Double((point.x - selectionRect.minX) * scaleFactor),
            y: Double((point.y - selectionRect.minY) * scaleFactor)
        )
    }

    private func viewPoint(from point: AnnotationPoint) -> CGPoint {
        CGPoint(
            x: selectionRect.minX + CGFloat(point.x) / scaleFactor,
            y: selectionRect.minY + CGFloat(point.y) / scaleFactor
        )
    }

    private func viewRect(from rect: AnnotationRect) -> CGRect {
        let normalized = rect.normalized
        return CGRect(
            x: selectionRect.minX + CGFloat(normalized.minX) / scaleFactor,
            y: selectionRect.minY + CGFloat(normalized.minY) / scaleFactor,
            width: CGFloat(normalized.width) / scaleFactor,
            height: CGFloat(normalized.height) / scaleFactor
        )
    }

    private func cgColor(_ color: AnnotationColor) -> CGColor {
        CGColor(
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            components: [
                CGFloat(color.red),
                CGFloat(color.green),
                CGFloat(color.blue),
                CGFloat(color.alpha)
            ]
        )!
    }

    private func nsColor(_ color: AnnotationColor) -> NSColor {
        NSColor(
            srgbRed: CGFloat(color.red),
            green: CGFloat(color.green),
            blue: CGFloat(color.blue),
            alpha: CGFloat(color.alpha)
        )
    }

    private func drawMagnifier(at point: CGPoint, context: CGContext) {
        guard let frozenImage else { return }
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
              let sample = frozenImage.cropping(to: sourceRect) else { return }

        let size = CGSize(width: 168, height: 168)
        var origin = CGPoint(x: point.x + 24, y: point.y + 24)
        if origin.x + size.width > bounds.maxX - 8 { origin.x = point.x - size.width - 24 }
        if origin.y + size.height > bounds.maxY - 8 { origin.y = point.y - size.height - 24 }
        origin.x = min(max(origin.x, bounds.minX + 8), bounds.maxX - size.width - 8)
        origin.y = min(max(origin.y, bounds.minY + 8), bounds.maxY - size.height - 8)
        let outerRect = CGRect(origin: origin, size: size)
        let imageRect = outerRect.insetBy(dx: 2.5, dy: 2.5)
        let path = CGPath(rect: outerRect, transform: nil)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -3), blur: 10, color: NSColor.black.withAlphaComponent(0.45).cgColor)
        context.setFillColor(NSColor(srgbRed: 0.08, green: 0.09, blue: 0.11, alpha: 0.96).cgColor)
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

@MainActor
private enum QQCaptureCursors {
    private enum Corner {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    static let resizeTopLeft = cornerCursor(.topLeft, risesRight: false)
    static let resizeTopRight = cornerCursor(.topRight, risesRight: true)
    static let resizeBottomLeft = cornerCursor(.bottomLeft, risesRight: true)
    static let resizeBottomRight = cornerCursor(.bottomRight, risesRight: false)

    private static func cornerCursor(
        _ corner: Corner,
        risesRight: Bool
    ) -> NSCursor {
        if #available(macOS 15, *) {
            let position: NSCursor.FrameResizePosition = switch corner {
            case .topLeft: .topLeft
            case .topRight: .topRight
            case .bottomLeft: .bottomLeft
            case .bottomRight: .bottomRight
            }
            return NSCursor.frameResize(position: position, directions: .all)
        }
        return diagonalCursor(risesRight: risesRight)
    }

    private static func diagonalCursor(risesRight: Bool) -> NSCursor {
        let size = NSSize(width: 24, height: 24)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let start = risesRight ? NSPoint(x: 5, y: 5) : NSPoint(x: 5, y: 19)
        let end = risesRight ? NSPoint(x: 19, y: 19) : NSPoint(x: 19, y: 5)
        let direction = atan2(end.y - start.y, end.x - start.x)
        let path = NSBezierPath()
        path.lineWidth = 2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: start)
        path.line(to: end)
        let headLength: CGFloat = 5
        let spread: CGFloat = .pi / 5
        for (tip, angle) in [(end, direction), (start, direction + .pi)] {
            path.move(to: tip)
            path.line(to: NSPoint(
                x: tip.x - headLength * cos(angle - spread),
                y: tip.y - headLength * sin(angle - spread)
            ))
            path.move(to: tip)
            path.line(to: NSPoint(
                x: tip.x - headLength * cos(angle + spread),
                y: tip.y - headLength * sin(angle + spread)
            ))
        }
        NSColor.white.setStroke()
        path.lineWidth = 4.5
        path.stroke()
        NSColor.black.setStroke()
        path.lineWidth = 2
        path.stroke()
        return NSCursor(image: image, hotSpot: NSPoint(x: 12, y: 12))
    }
}
