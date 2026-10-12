import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum AnnotationRendererError: LocalizedError {
    case imageReadFailed
    case contextCreationFailed
    case imageWriteFailed

    public var errorDescription: String? {
        switch self {
        case .imageReadFailed:
            "无法读取原始图片。"
        case .contextCreationFailed:
            "无法创建图片渲染环境。"
        case .imageWriteFailed:
            "无法写入渲染后的图片。"
        }
    }
}

public enum AnnotationRenderer {
    public static func render(
        baseImageURL: URL,
        project: AnnotationProject,
        outputURL: URL
    ) throws {
        guard let source = CGImageSourceCreateWithURL(baseImageURL as CFURL, nil),
              let baseImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw AnnotationRendererError.imageReadFailed
        }

        let fullCanvas = CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height)
        let cropRect = project.visibleRect.cgRect
            .standardized
            .integral
            .intersection(fullCanvas)
        let width = max(1, Int(cropRect.width))
        let height = max(1, Int(cropRect.height))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw AnnotationRendererError.contextCreationFailed
        }

        context.translateBy(x: -cropRect.minX, y: -cropRect.minY)
        context.draw(baseImage, in: fullCanvas)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let ciContext = CIContext(cgContext: context, options: nil)
        for annotation in project.annotations {
            draw(
                annotation,
                rotation: project.rotation(for: annotation.id),
                baseImage: baseImage,
                canvasRect: cropRect,
                context: context,
                ciContext: ciContext
            )
        }

        guard let rendered = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                outputURL as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
              ) else {
            throw AnnotationRendererError.imageWriteFailed
        }
        CGImageDestinationAddImage(destination, rendered, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw AnnotationRendererError.imageWriteFailed
        }
    }

    private static func draw(
        _ annotation: AnnotationItem,
        rotation: Double,
        baseImage: CGImage,
        canvasRect: CGRect,
        context: CGContext,
        ciContext: CIContext
    ) {
        if case let .spotlight(value) = annotation {
            drawSpotlight(
                value,
                rotation: rotation,
                canvasRect: canvasRect,
                context: context
            )
            return
        }

        context.saveGState()
        defer { context.restoreGState() }
        if rotation != 0 {
            let center = annotation.bounds.center.cgPoint
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: rotation)
            context.translateBy(x: -center.x, y: -center.y)
        }

        switch annotation {
        case let .arrow(value):
            drawArrow(value, context: context)
        case let .rectangle(value):
            drawRectangle(value, context: context)
        case let .ellipse(value):
            drawEllipse(value, context: context)
        case let .line(value):
            drawLine(value, context: context)
        case let .pen(value):
            drawPen(value, context: context)
        case let .highlight(value):
            drawHighlight(value, context: context)
        case let .text(value):
            drawText(value, context: context)
        case let .pixelate(value):
            drawPixelate(value, baseImage: baseImage, context: context, ciContext: ciContext)
        case let .redaction(value):
            context.setFillColor(value.color.cgColor)
            context.fill(value.rect.cgRect)
        case let .step(value):
            drawStep(value, context: context)
        case .spotlight:
            break
        }
    }

    private static func drawArrow(_ arrow: ArrowAnnotation, context: CGContext) {
        let points = ArrowShapeGeometry(arrow).points.map(\.cgPoint)
        if let first = points.first {
            context.beginPath()
            context.move(to: first)
            points.dropFirst().forEach(context.addLine(to:))
            context.closePath()
            context.setFillColor(arrow.color.cgColor)
            context.fillPath()
        }

        guard let note = arrow.note else {
            return
        }
        let font = CTFontCreateWithName(
            "SFProText-Semibold" as CFString,
            CGFloat(arrow.noteFontSize),
            nil
        )
        let attributedNote = NSAttributedString(
            string: note,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): arrow.color.cgColor
            ]
        )
        let noteLine = CTLineCreateWithAttributedString(attributedNote)
        let noteBounds = CTLineGetBoundsWithOptions(noteLine, [.useGlyphPathBounds])
        let noteOrigin = arrow.noteOrigin(
            width: noteBounds.width,
            height: noteBounds.height
        )
        context.textPosition = CGPoint(
            x: noteOrigin.x - noteBounds.minX,
            y: noteOrigin.y - noteBounds.minY
        )
        CTLineDraw(noteLine, context)
    }

    private static func drawRectangle(_ rectangle: RectangleAnnotation, context: CGContext) {
        let rect = rectangle.rect.cgRect.standardized
        if let fillColor = rectangle.fillColor {
            context.setFillColor(fillColor.cgColor)
            context.fill(rect)
        }
        context.setStrokeColor(rectangle.color.cgColor)
        context.setLineWidth(CGFloat(rectangle.lineWidth))
        context.stroke(rect)
    }

    private static func drawEllipse(_ ellipse: EllipseAnnotation, context: CGContext) {
        let rect = ellipse.rect.cgRect.standardized
        if let fillColor = ellipse.fillColor {
            context.setFillColor(fillColor.cgColor)
            context.fillEllipse(in: rect)
        }
        context.setStrokeColor(ellipse.color.cgColor)
        context.setLineWidth(CGFloat(ellipse.lineWidth))
        context.strokeEllipse(in: rect)
    }

    private static func drawLine(_ line: LineAnnotation, context: CGContext) {
        context.saveGState()
        context.setStrokeColor(line.color.cgColor)
        context.setLineWidth(CGFloat(line.lineWidth))
        if line.isDashed {
            let dash = max(4, CGFloat(line.lineWidth) * 2.5)
            context.setLineDash(phase: 0, lengths: [dash, dash * 0.75])
        }
        context.beginPath()
        context.move(to: line.start.cgPoint)
        context.addLine(to: line.end.cgPoint)
        context.strokePath()
        context.restoreGState()
    }

    private static func drawPen(_ pen: PenAnnotation, context: CGContext) {
        guard let first = pen.points.first else {
            return
        }
        context.setStrokeColor(pen.color.cgColor)
        context.setLineWidth(CGFloat(pen.lineWidth))
        context.beginPath()
        context.move(to: first.cgPoint)
        for point in pen.points.dropFirst() {
            context.addLine(to: point.cgPoint)
        }
        context.strokePath()
    }

    private static func drawHighlight(_ highlight: HighlightAnnotation, context: CGContext) {
        guard let first = highlight.points.first else {
            return
        }
        context.saveGState()
        context.setBlendMode(.normal)
        context.setStrokeColor(
            highlight.color.cgColor.copy(
                alpha: min(max(highlight.opacity * highlight.color.alpha, 0.05), 0.9)
            ) ?? highlight.color.cgColor
        )
        context.setLineWidth(CGFloat(highlight.lineWidth))
        context.setLineCap(.square)
        context.beginPath()
        context.move(to: first.cgPoint)
        for point in highlight.points.dropFirst() {
            context.addLine(to: point.cgPoint)
        }
        context.strokePath()
        context.restoreGState()
    }

    private static func drawText(_ text: TextAnnotation, context: CGContext) {
        let font = CTFontCreateWithName(
            "SFProText-Regular" as CFString,
            CGFloat(text.fontSize),
            nil
        )
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): text.color.cgColor
        ]
        let attributedText = NSAttributedString(string: text.text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributedText)
        context.saveGState()
        context.textPosition = text.position.cgPoint
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static func drawStep(_ step: StepAnnotation, context: CGContext) {
        let diameter = CGFloat(step.diameter)
        let rect = CGRect(
            x: step.center.x - step.diameter / 2,
            y: step.center.y - step.diameter / 2,
            width: step.diameter,
            height: step.diameter
        )
        context.setFillColor(step.fillColor.cgColor)
        context.fillEllipse(in: rect)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.85))
        context.setLineWidth(max(1.5, diameter * 0.05))
        context.strokeEllipse(in: rect.insetBy(dx: 1, dy: 1))

        let font = CTFontCreateWithName(
            "SFProRounded-Bold" as CFString,
            max(11, diameter * 0.52),
            nil
        )
        let attributed = NSAttributedString(
            string: String(step.number),
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): step.textColor.cgColor
            ]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        context.textPosition = CGPoint(
            x: step.center.x - bounds.midX,
            y: step.center.y - bounds.midY
        )
        CTLineDraw(line, context)

        guard let note = step.note else {
            return
        }
        let noteFont = CTFontCreateWithName(
            "SFProText-Semibold" as CFString,
            max(11, diameter * 0.5),
            nil
        )
        let attributedNote = NSAttributedString(
            string: note,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): noteFont,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): step.fillColor.cgColor
            ]
        )
        let noteLine = CTLineCreateWithAttributedString(attributedNote)
        let noteBounds = CTLineGetBoundsWithOptions(noteLine, [.useGlyphPathBounds])
        context.textPosition = CGPoint(
            x: step.center.x + diameter / 2 + max(5, diameter * 0.18),
            y: step.center.y - noteBounds.midY
        )
        CTLineDraw(noteLine, context)
    }

    private static func drawSpotlight(
        _ spotlight: SpotlightAnnotation,
        rotation: Double,
        canvasRect: CGRect,
        context: CGContext
    ) {
        context.saveGState()
        context.setFillColor(CGColor(gray: 0, alpha: spotlight.dimOpacity))
        let path = CGMutablePath()
        path.addRect(canvasRect)
        let rect = spotlight.focusRect.cgRect.standardized
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let transform = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: rotation)
            .translatedBy(x: -center.x, y: -center.y)
        path.addEllipse(in: rect, transform: transform)
        context.addPath(path)
        context.drawPath(using: .eoFill)
        context.restoreGState()
    }

    private static func drawPixelate(
        _ pixelate: PixelateAnnotation,
        baseImage: CGImage,
        context: CGContext,
        ciContext: CIContext
    ) {
        let rect = pixelate.rect.cgRect.integral
        guard !rect.isEmpty else {
            return
        }
        let image = CIImage(cgImage: baseImage)
        let outputImage = AnnotationObscurationFilter.apply(
            to: image.cropped(to: rect),
            effect: pixelate.effect,
            scale: pixelate.scale
        )
        guard let output = ciContext.createCGImage(outputImage, from: rect) else {
            return
        }
        context.draw(output, in: rect)
    }
}
