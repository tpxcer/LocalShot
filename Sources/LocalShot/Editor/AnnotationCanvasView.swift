import AppKit
import LocalShotEditing
import SwiftUI

struct AnnotationCanvasView: View {
    @ObservedObject var model: AnnotationEditorModel

    private var image: NSImage {
        NSImage(contentsOf: model.imageURL) ?? NSImage()
    }

    var body: some View {
        GeometryReader { proxy in
            let frame = imageFrame(in: proxy.size)

            ZStack {
                Color(nsColor: .windowBackgroundColor)

                croppedImage(frame: frame)
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 4)

                Canvas { context, _ in
                    var clippedContext = context
                    clippedContext.clip(to: Path(frame))

                    for annotation in model.project.annotations {
                        var annotationContext = clippedContext
                        draw(
                            annotation,
                            rotation: model.project.rotation(for: annotation.id),
                            in: &annotationContext,
                            imageFrame: frame
                        )
                    }
                    if let preview = previewAnnotation(frame: frame) {
                        var previewContext = clippedContext
                        draw(preview, rotation: 0, in: &previewContext, imageFrame: frame)
                    }
                    if model.selectedTool == .crop, let draft = model.gestureDraft {
                        drawCropPreview(draft, in: &clippedContext, imageFrame: frame)
                    }
                    if model.selectedTool == .select, let selected = model.selectedAnnotation {
                        var selectionContext = context
                        drawSelection(selected, in: &selectionContext, imageFrame: frame)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(canvasGesture(frame: frame))
            .onDeleteCommand {
                model.deleteSelected()
            }
        }
    }

    private func croppedImage(frame: CGRect) -> some View {
        let visible = model.project.visibleRect
        let scale = frame.width / max(1, CGFloat(visible.width))
        let fullWidth = CGFloat(model.project.canvasWidth) * scale
        let fullHeight = CGFloat(model.project.canvasHeight) * scale
        let originX = -CGFloat(visible.minX) * scale
        let originY = -(CGFloat(model.project.canvasHeight) - CGFloat(visible.maxY)) * scale

        return Canvas { context, _ in
            context.draw(
                Image(nsImage: image),
                in: CGRect(x: originX, y: originY, width: fullWidth, height: fullHeight)
            )
        }
        .frame(width: frame.width, height: frame.height)
        .clipShape(Rectangle())
        .overlay {
            Rectangle().stroke(.black.opacity(0.12), lineWidth: 1)
        }
        .position(x: frame.midX, y: frame.midY)
    }

    private func canvasGesture(frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                switch model.selectedTool {
                case .select:
                    updateSelectionGesture(at: value.location, frame: frame)
                default:
                    let point = clamped(value.location, to: frame)
                    if model.gestureDraft == nil {
                        model.gestureDraft = AnnotationGestureDraft(
                            start: point,
                            current: point,
                            points: [point]
                        )
                    } else {
                        model.gestureDraft?.current = point
                        if model.selectedTool == .pen || model.selectedTool == .highlight {
                            model.gestureDraft?.points.append(point)
                        }
                    }
                }
            }
            .onEnded { _ in
                switch model.selectedTool {
                case .select:
                    model.finishTransform()
                case .crop:
                    if let draft = model.gestureDraft {
                        model.setCrop(projectRect(start: draft.start, end: draft.current, frame: frame))
                    }
                    model.gestureDraft = nil
                default:
                    guard let annotation = previewAnnotation(frame: frame) else {
                        model.gestureDraft = nil
                        return
                    }
                    model.add(annotation)
                    model.gestureDraft = nil
                }
            }
    }

    private func updateSelectionGesture(at viewPoint: CGPoint, frame: CGRect) {
        let clampedPoint = clamped(viewPoint, to: frame)
        let point = projectPoint(from: clampedPoint, frame: frame)

        if !model.isTransforming {
            if rotationHandleContains(viewPoint, frame: frame),
               let annotationID = model.selectedAnnotationID {
                model.beginTransform(
                    annotationID: annotationID,
                    startPoint: point,
                    resizeHandle: nil,
                    rotates: true
                )
            } else if let handle = resizeHandle(at: viewPoint, frame: frame),
               let annotationID = model.selectedAnnotationID {
                model.beginTransform(
                    annotationID: annotationID,
                    startPoint: point,
                    resizeHandle: handle
                )
            } else {
                let scale = frame.width / max(1, CGFloat(model.project.visibleRect.width))
                let tolerance = Double(8 / max(scale, 0.01))
                guard let hit = model.annotation(at: point, tolerance: tolerance) else {
                    model.select(nil)
                    return
                }
                model.select(hit.id)
                model.beginTransform(
                    annotationID: hit.id,
                    startPoint: point,
                    resizeHandle: nil
                )
            }
        }

        model.updateTransform(to: point)
    }

    private func imageFrame(in size: CGSize) -> CGRect {
        let visible = model.project.visibleRect
        let canvasWidth = max(1, CGFloat(visible.width))
        let canvasHeight = max(1, CGFloat(visible.height))
        let inset: CGFloat = 28
        let available = CGSize(
            width: max(1, size.width - inset * 2),
            height: max(1, size.height - inset * 2)
        )
        let scale = min(available.width / canvasWidth, available.height / canvasHeight)
        let imageSize = CGSize(width: canvasWidth * scale, height: canvasHeight * scale)
        return CGRect(
            x: (size.width - imageSize.width) / 2,
            y: (size.height - imageSize.height) / 2,
            width: imageSize.width,
            height: imageSize.height
        )
    }

    private func clamped(_ point: CGPoint, to frame: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, frame.minX), frame.maxX),
            y: min(max(point.y, frame.minY), frame.maxY)
        )
    }

    private func projectPoint(from viewPoint: CGPoint, frame: CGRect) -> AnnotationPoint {
        let visible = model.project.visibleRect
        let x = visible.minX
            + Double((viewPoint.x - frame.minX) / frame.width) * visible.width
        let y = visible.maxY
            - Double((viewPoint.y - frame.minY) / frame.height) * visible.height
        return AnnotationPoint(x: x, y: y)
    }

    private func viewPoint(from point: AnnotationPoint, frame: CGRect) -> CGPoint {
        let visible = model.project.visibleRect
        return CGPoint(
            x: frame.minX + CGFloat((point.x - visible.minX) / visible.width) * frame.width,
            y: frame.minY + CGFloat((visible.maxY - point.y) / visible.height) * frame.height
        )
    }

    private func projectRect(start: CGPoint, end: CGPoint, frame: CGRect) -> AnnotationRect {
        let first = projectPoint(from: start, frame: frame)
        let second = projectPoint(from: end, frame: frame)
        return AnnotationRect(
            x: min(first.x, second.x),
            y: min(first.y, second.y),
            width: abs(first.x - second.x),
            height: abs(first.y - second.y)
        )
    }

    private func viewRect(from rect: AnnotationRect, frame: CGRect) -> CGRect {
        let visible = model.project.visibleRect
        let normalized = rect.normalized
        let scaleX = frame.width / CGFloat(visible.width)
        let scaleY = frame.height / CGFloat(visible.height)
        return CGRect(
            x: frame.minX + CGFloat(normalized.minX - visible.minX) * scaleX,
            y: frame.minY + CGFloat(visible.maxY - normalized.maxY) * scaleY,
            width: CGFloat(normalized.width) * scaleX,
            height: CGFloat(normalized.height) * scaleY
        )
    }

    private func selectionProjectRect(for annotation: AnnotationItem, frame: CGRect) -> AnnotationRect {
        var rect = annotation.bounds.normalized
        let scale = frame.width / max(1, CGFloat(model.project.visibleRect.width))
        let minimum = Double(14 / max(scale, 0.01))
        if rect.width < minimum {
            rect.x -= (minimum - rect.width) / 2
            rect.width = minimum
        }
        if rect.height < minimum {
            rect.y -= (minimum - rect.height) / 2
            rect.height = minimum
        }
        return rect
    }

    private func selectionHandlePoints(
        for annotation: AnnotationItem,
        frame: CGRect
    ) -> [AnnotationResizeHandle: CGPoint] {
        let rect = selectionProjectRect(for: annotation, frame: frame)
        let center = rect.center
        let rotation = model.project.rotation(for: annotation.id)
        let projectPoints: [AnnotationResizeHandle: AnnotationPoint] = [
            .topLeft: AnnotationPoint(x: rect.minX, y: rect.maxY),
            .topRight: AnnotationPoint(x: rect.maxX, y: rect.maxY),
            .bottomLeft: AnnotationPoint(x: rect.minX, y: rect.minY),
            .bottomRight: AnnotationPoint(x: rect.maxX, y: rect.minY)
        ]
        return projectPoints.mapValues {
            viewPoint(from: $0.rotated(around: center, by: rotation), frame: frame)
        }
    }

    private func rotationHandleGeometry(
        for annotation: AnnotationItem,
        frame: CGRect
    ) -> (topMidpoint: CGPoint, handle: CGPoint) {
        let rect = selectionProjectRect(for: annotation, frame: frame)
        let center = rect.center
        let rotation = model.project.rotation(for: annotation.id)
        let topMidpoint = AnnotationPoint(x: center.x, y: rect.maxY)
            .rotated(around: center, by: rotation)
        let centerView = viewPoint(from: center, frame: frame)
        let topView = viewPoint(from: topMidpoint, frame: frame)
        let dx = topView.x - centerView.x
        let dy = topView.y - centerView.y
        let length = max(0.001, hypot(dx, dy))
        let distance: CGFloat = 26
        return (
            topView,
            CGPoint(
                x: topView.x + dx / length * distance,
                y: topView.y + dy / length * distance
            )
        )
    }

    private func resizeHandle(at point: CGPoint, frame: CGRect) -> AnnotationResizeHandle? {
        guard let selected = model.selectedAnnotation else {
            return nil
        }
        return selectionHandlePoints(for: selected, frame: frame).first(where: {
            hypot(point.x - $0.value.x, point.y - $0.value.y) <= 9
        })?.key
    }

    private func rotationHandleContains(_ point: CGPoint, frame: CGRect) -> Bool {
        guard let selected = model.selectedAnnotation else {
            return false
        }
        let handle = rotationHandleGeometry(for: selected, frame: frame).handle
        return hypot(point.x - handle.x, point.y - handle.y) <= 11
    }

    private func previewAnnotation(frame: CGRect) -> AnnotationItem? {
        guard let draft = model.gestureDraft else {
            return nil
        }
        guard frame.width > 0, frame.height > 0 else {
            return nil
        }
        let color = model.selectedColor.annotationColor
        switch model.selectedTool {
        case .select, .crop:
            return nil
        case .arrow:
            return .arrow(ArrowAnnotation(
                start: projectPoint(from: draft.start, frame: frame),
                end: projectPoint(from: draft.current, frame: frame),
                color: color,
                lineWidth: model.lineWidth
            ))
        case .line:
            return .line(LineAnnotation(
                start: projectPoint(from: draft.start, frame: frame),
                end: projectPoint(from: draft.current, frame: frame),
                color: color,
                lineWidth: model.lineWidth,
                isDashed: model.lineIsDashed
            ))
        case .rectangle:
            return .rectangle(RectangleAnnotation(
                rect: projectRect(start: draft.start, end: draft.current, frame: frame),
                color: color,
                lineWidth: model.lineWidth
            ))
        case .ellipse:
            return .ellipse(EllipseAnnotation(
                rect: projectRect(start: draft.start, end: draft.current, frame: frame),
                color: color,
                lineWidth: model.lineWidth
            ))
        case .pen:
            return .pen(PenAnnotation(
                points: draft.points.map { projectPoint(from: $0, frame: frame) },
                color: color,
                lineWidth: model.lineWidth
            ))
        case .highlight:
            return .highlight(HighlightAnnotation(
                points: draft.points.map { projectPoint(from: $0, frame: frame) },
                color: color,
                lineWidth: max(12, model.lineWidth * 4.5)
            ))
        case .text:
            let text = model.textDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return nil
            }
            return .text(TextAnnotation(
                position: projectPoint(from: draft.current, frame: frame),
                text: text,
                color: color,
                fontSize: max(12, model.lineWidth * 5)
            ))
        case .step:
            return .step(StepAnnotation(
                center: projectPoint(from: draft.current, frame: frame),
                number: model.nextStepNumber,
                diameter: max(28, model.lineWidth * 7),
                fillColor: color
            ))
        case .spotlight:
            return .spotlight(SpotlightAnnotation(
                focusRect: projectRect(start: draft.start, end: draft.current, frame: frame)
            ))
        case .pixelate:
            return .pixelate(PixelateAnnotation(
                rect: projectRect(start: draft.start, end: draft.current, frame: frame),
                effect: model.pixelateEffect
            ))
        case .redaction:
            return .redaction(RedactionAnnotation(
                rect: projectRect(start: draft.start, end: draft.current, frame: frame),
                color: color
            ))
        }
    }

    private func drawCropPreview(
        _ draft: AnnotationGestureDraft,
        in context: inout GraphicsContext,
        imageFrame: CGRect
    ) {
        let cropRect = CGRect(
            x: min(draft.start.x, draft.current.x),
            y: min(draft.start.y, draft.current.y),
            width: abs(draft.start.x - draft.current.x),
            height: abs(draft.start.y - draft.current.y)
        ).intersection(imageFrame)
        guard cropRect.width >= 1, cropRect.height >= 1 else {
            return
        }

        let maskColor = Color.black.opacity(0.48)
        context.fill(
            Path(CGRect(x: imageFrame.minX, y: imageFrame.minY, width: imageFrame.width, height: cropRect.minY - imageFrame.minY)),
            with: .color(maskColor)
        )
        context.fill(
            Path(CGRect(x: imageFrame.minX, y: cropRect.maxY, width: imageFrame.width, height: imageFrame.maxY - cropRect.maxY)),
            with: .color(maskColor)
        )
        context.fill(
            Path(CGRect(x: imageFrame.minX, y: cropRect.minY, width: cropRect.minX - imageFrame.minX, height: cropRect.height)),
            with: .color(maskColor)
        )
        context.fill(
            Path(CGRect(x: cropRect.maxX, y: cropRect.minY, width: imageFrame.maxX - cropRect.maxX, height: cropRect.height)),
            with: .color(maskColor)
        )
        context.stroke(
            Path(cropRect),
            with: .color(.white),
            style: StrokeStyle(lineWidth: 2, dash: [6, 4])
        )
    }

    private func drawSelection(
        _ annotation: AnnotationItem,
        in context: inout GraphicsContext,
        imageFrame: CGRect
    ) {
        let handles = selectionHandlePoints(for: annotation, frame: imageFrame)
        guard let topLeft = handles[.topLeft],
              let topRight = handles[.topRight],
              let bottomRight = handles[.bottomRight],
              let bottomLeft = handles[.bottomLeft] else {
            return
        }
        var outline = Path()
        outline.move(to: topLeft)
        outline.addLine(to: topRight)
        outline.addLine(to: bottomRight)
        outline.addLine(to: bottomLeft)
        outline.closeSubpath()
        context.stroke(
            outline,
            with: .color(.accentColor),
            style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])
        )
        let rotationGeometry = rotationHandleGeometry(for: annotation, frame: imageFrame)
        var connector = Path()
        connector.move(to: rotationGeometry.topMidpoint)
        connector.addLine(to: rotationGeometry.handle)
        context.stroke(connector, with: .color(.accentColor), lineWidth: 1.5)

        let handleSize: CGFloat = 9
        for point in handles.values {
            let handleRect = CGRect(
                x: point.x - handleSize / 2,
                y: point.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            context.fill(Path(ellipseIn: handleRect), with: .color(.white))
            context.stroke(Path(ellipseIn: handleRect), with: .color(.accentColor), lineWidth: 1.5)
        }
        let rotationHandleSize: CGFloat = 11
        let rotationRect = CGRect(
            x: rotationGeometry.handle.x - rotationHandleSize / 2,
            y: rotationGeometry.handle.y - rotationHandleSize / 2,
            width: rotationHandleSize,
            height: rotationHandleSize
        )
        context.fill(Path(ellipseIn: rotationRect), with: .color(.accentColor))
        context.stroke(Path(ellipseIn: rotationRect), with: .color(.white), lineWidth: 1.5)
    }

    private func draw(
        _ annotation: AnnotationItem,
        rotation: Double,
        in context: inout GraphicsContext,
        imageFrame: CGRect
    ) {
        if case let .spotlight(value) = annotation {
            var path = Path()
            path.addRect(imageFrame)
            let rect = viewRect(from: value.focusRect, frame: imageFrame)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let transform = CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: -rotation)
                .translatedBy(x: -center.x, y: -center.y)
            path.addPath(Path(ellipseIn: rect).applying(transform))
            context.fill(
                path,
                with: .color(.black.opacity(value.dimOpacity)),
                style: FillStyle(eoFill: true)
            )
            return
        }

        if rotation != 0 {
            let center = viewPoint(from: annotation.bounds.center, frame: imageFrame)
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: .radians(-rotation))
            context.translateBy(x: -center.x, y: -center.y)
        }
        let scale = imageFrame.width / max(1, CGFloat(model.project.visibleRect.width))
        switch annotation {
        case let .arrow(value):
            let points = ArrowShapeGeometry(value).points.map {
                viewPoint(from: $0, frame: imageFrame)
            }
            var path = Path()
            if let first = points.first {
                path.move(to: first)
                points.dropFirst().forEach { path.addLine(to: $0) }
                path.closeSubpath()
                context.fill(path, with: .color(swiftUIColor(value.color)))
            }
        case let .rectangle(value):
            let rect = viewRect(from: value.rect, frame: imageFrame)
            if let fillColor = value.fillColor {
                context.fill(Path(rect), with: .color(swiftUIColor(fillColor)))
            }
            context.stroke(
                Path(rect),
                with: .color(swiftUIColor(value.color)),
                lineWidth: max(1, CGFloat(value.lineWidth) * scale)
            )
        case let .ellipse(value):
            let rect = viewRect(from: value.rect, frame: imageFrame)
            if let fillColor = value.fillColor {
                context.fill(Path(ellipseIn: rect), with: .color(swiftUIColor(fillColor)))
            }
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(swiftUIColor(value.color)),
                lineWidth: max(1, CGFloat(value.lineWidth) * scale)
            )
        case let .line(value):
            var path = Path()
            path.move(to: viewPoint(from: value.start, frame: imageFrame))
            path.addLine(to: viewPoint(from: value.end, frame: imageFrame))
            let width = max(1, CGFloat(value.lineWidth) * scale)
            context.stroke(
                path,
                with: .color(swiftUIColor(value.color)),
                style: StrokeStyle(
                    lineWidth: width,
                    lineCap: .round,
                    lineJoin: .round,
                    dash: value.isDashed ? [max(4, width * 2.5), max(3, width * 1.8)] : []
                )
            )
        case let .pen(value):
            guard let first = value.points.first else { return }
            var path = Path()
            path.move(to: viewPoint(from: first, frame: imageFrame))
            for point in value.points.dropFirst() {
                path.addLine(to: viewPoint(from: point, frame: imageFrame))
            }
            context.stroke(
                path,
                with: .color(swiftUIColor(value.color)),
                style: StrokeStyle(
                    lineWidth: max(1, CGFloat(value.lineWidth) * scale),
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        case let .highlight(value):
            guard let first = value.points.first else { return }
            var path = Path()
            path.move(to: viewPoint(from: first, frame: imageFrame))
            for point in value.points.dropFirst() {
                path.addLine(to: viewPoint(from: point, frame: imageFrame))
            }
            context.stroke(
                path,
                with: .color(swiftUIColor(value.color).opacity(value.opacity)),
                style: StrokeStyle(
                    lineWidth: max(2, CGFloat(value.lineWidth) * scale),
                    lineCap: .square,
                    lineJoin: .round
                )
            )
        case let .text(value):
            context.draw(
                Text(value.text)
                    .font(.system(size: max(9, CGFloat(value.fontSize) * scale), weight: .medium))
                    .foregroundColor(swiftUIColor(value.color)),
                at: viewPoint(from: value.position, frame: imageFrame),
                anchor: .bottomLeading
            )
        case let .pixelate(value):
            let rect = viewRect(from: value.rect, frame: imageFrame)
            context.fill(Path(rect), with: .color(.gray.opacity(0.55)))
            context.stroke(Path(rect), with: .color(.white.opacity(0.8)), lineWidth: 1)
        case let .redaction(value):
            context.fill(
                Path(viewRect(from: value.rect, frame: imageFrame)),
                with: .color(swiftUIColor(value.color))
            )
        case let .step(value):
            let center = viewPoint(from: value.center, frame: imageFrame)
            let diameter = max(16, CGFloat(value.diameter) * scale)
            let rect = CGRect(
                x: center.x - diameter / 2,
                y: center.y - diameter / 2,
                width: diameter,
                height: diameter
            )
            context.fill(Path(ellipseIn: rect), with: .color(swiftUIColor(value.fillColor)))
            context.stroke(
                Path(ellipseIn: rect.insetBy(dx: 1, dy: 1)),
                with: .color(.white.opacity(0.86)),
                lineWidth: max(1.5, diameter * 0.05)
            )
            context.draw(
                Text(String(value.number))
                    .font(.system(size: max(10, diameter * 0.52), weight: .bold, design: .rounded))
                    .foregroundColor(swiftUIColor(value.textColor)),
                at: center,
                anchor: .center
            )
        case .spotlight:
            break
        }
    }

    private func swiftUIColor(_ color: AnnotationColor) -> Color {
        Color(red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }
}
