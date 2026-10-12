import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import LocalShotVision
import UniformTypeIdentifiers

public enum TranslationOverlayRendererError: LocalizedError {
    case imageReadFailed
    case contextCreationFailed
    case imageWriteFailed

    public var errorDescription: String? {
        switch self {
        case .imageReadFailed: "无法读取原始图片。"
        case .contextCreationFailed: "无法创建翻译图片。"
        case .imageWriteFailed: "无法写入翻译图片。"
        }
    }
}

public enum TranslationOverlayRenderer {
    public static func render(
        baseImageURL: URL,
        blocks: [TranslationTextBlock],
        outputURL: URL
    ) throws {
        guard let source = CGImageSourceCreateWithURL(baseImageURL as CFURL, nil),
              let baseImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw TranslationOverlayRendererError.imageReadFailed
        }
        guard let context = CGContext(
            data: nil,
            width: baseImage.width,
            height: baseImage.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TranslationOverlayRendererError.contextCreationFailed
        }

        let canvas = CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height)
        context.draw(baseImage, in: canvas)

        for block in blocks where !block.targetText.isEmpty {
            let rect = pixelRect(for: block.boundingBox, imageSize: canvas.size)
                .insetBy(dx: -5, dy: -3)
                .intersection(canvas)
            guard rect.width >= 8, rect.height >= 8 else {
                continue
            }
            drawCard(text: block.targetText, rect: rect, context: context)
        }

        guard let output = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                outputURL as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
              ) else {
            throw TranslationOverlayRendererError.imageWriteFailed
        }
        CGImageDestinationAddImage(destination, output, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TranslationOverlayRendererError.imageWriteFailed
        }
    }

    private static func pixelRect(for box: OCRBoundingBox, imageSize: CGSize) -> CGRect {
        CGRect(
            x: box.x * imageSize.width,
            y: box.y * imageSize.height,
            width: box.width * imageSize.width,
            height: box.height * imageSize.height
        )
    }

    private static func drawCard(text: String, rect: CGRect, context: CGContext) {
        let path = CGPath(
            roundedRect: rect,
            cornerWidth: min(6, rect.height / 4),
            cornerHeight: min(6, rect.height / 4),
            transform: nil
        )
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.addPath(path)
        context.fillPath()
        context.setStrokeColor(CGColor(gray: 0, alpha: 0.18))
        context.setLineWidth(1)
        context.addPath(path)
        context.strokePath()

        let textRect = rect.insetBy(dx: 5, dy: 3)
        let fontSize = fittedFontSize(text: text, rect: textRect)
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.05, alpha: 1),
            .paragraphStyle: paragraph
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let textPath = CGPath(rect: textRect, transform: nil)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributed.length),
            textPath,
            nil
        )
        CTFrameDraw(frame, context)
    }

    private static func fittedFontSize(text: String, rect: CGRect) -> CGFloat {
        var size = min(36, max(8, rect.height * 0.72))
        while size > 8 {
            let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
            let attributed = NSAttributedString(
                string: text,
                attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
            )
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter,
                CFRange(location: 0, length: attributed.length),
                nil,
                CGSize(width: rect.width, height: .greatestFiniteMagnitude),
                nil
            )
            if suggested.height <= rect.height && suggested.width <= rect.width + 1 {
                return size
            }
            size -= 1
        }
        return 8
    }
}
