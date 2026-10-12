import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageBeautificationRendererError: LocalizedError {
    case imageReadFailed
    case contextCreationFailed
    case imageWriteFailed

    public var errorDescription: String? {
        switch self {
        case .imageReadFailed: "无法读取原始图片。"
        case .contextCreationFailed: "无法创建美化图片。"
        case .imageWriteFailed: "无法写入美化图片。"
        }
    }
}

public enum ImageBeautificationRenderer {
    public static func outputSize(
        imageSize: CGSize,
        options: ImageBeautificationOptions
    ) -> CGSize {
        let padding = max(0, options.padding)
        var width = max(1, imageSize.width + padding * 2)
        var height = max(1, imageSize.height + padding * 2)

        if let ratio = options.aspectRatio.widthToHeight {
            if width / height > ratio {
                height = width / ratio
            } else {
                width = height * ratio
            }
        }

        return CGSize(width: ceil(width), height: ceil(height))
    }

    public static func render(
        baseImageURL: URL,
        options: ImageBeautificationOptions,
        outputURL: URL
    ) throws {
        guard let source = CGImageSourceCreateWithURL(baseImageURL as CFURL, nil),
              let baseImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImageBeautificationRendererError.imageReadFailed
        }

        let imageSize = CGSize(width: baseImage.width, height: baseImage.height)
        let canvasSize = outputSize(imageSize: imageSize, options: options)
        guard let context = CGContext(
            data: nil,
            width: Int(canvasSize.width),
            height: Int(canvasSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ImageBeautificationRendererError.contextCreationFailed
        }

        let canvas = CGRect(origin: .zero, size: canvasSize)
        drawBackground(options.background, in: canvas, context: context)

        let imageRect = CGRect(
            x: (canvas.width - imageSize.width) / 2,
            y: (canvas.height - imageSize.height) / 2,
            width: imageSize.width,
            height: imageSize.height
        )
        let cornerRadius = min(
            max(0, options.cornerRadius),
            min(imageRect.width, imageRect.height) / 2
        )
        let imagePath = CGPath(
            roundedRect: imageRect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )

        let shadowRadius = min(max(0, options.shadowRadius), max(0, options.padding))
        if shadowRadius > 0, options.shadowOpacity > 0 {
            context.saveGState()
            context.setShadow(
                offset: CGSize(width: 0, height: -max(1, shadowRadius * 0.18)),
                blur: shadowRadius,
                color: CGColor(gray: 0, alpha: min(max(options.shadowOpacity, 0), 1))
            )
            context.setFillColor(CGColor(gray: 0, alpha: 0.84))
            context.addPath(imagePath)
            context.fillPath()
            context.restoreGState()
        }

        context.saveGState()
        context.addPath(imagePath)
        context.clip()
        context.interpolationQuality = .high
        context.draw(baseImage, in: imageRect)
        context.restoreGState()

        guard let renderedImage = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                outputURL as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
              ) else {
            throw ImageBeautificationRendererError.imageWriteFailed
        }
        CGImageDestinationAddImage(destination, renderedImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageBeautificationRendererError.imageWriteFailed
        }
    }

    private static func drawBackground(
        _ background: BeautificationBackground,
        in rect: CGRect,
        context: CGContext
    ) {
        switch background {
        case let .solid(color):
            context.setFillColor(cgColor(color))
            context.fill(rect)
        case let .linearGradient(start, end):
            let colors = [cgColor(start), cgColor(end)] as CFArray
            let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: colors,
                locations: [0, 1]
            )
            guard let gradient else {
                context.setFillColor(cgColor(start))
                context.fill(rect)
                return
            }
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: rect.minX, y: rect.maxY),
                end: CGPoint(x: rect.maxX, y: rect.minY),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
    }

    private static func cgColor(_ color: BeautificationColor) -> CGColor {
        CGColor(
            red: color.red,
            green: color.green,
            blue: color.blue,
            alpha: color.alpha
        )
    }
}
