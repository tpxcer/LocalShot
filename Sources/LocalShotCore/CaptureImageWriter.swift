import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum CaptureImageWriterError: LocalizedError {
    case destinationUnavailable
    case writeFailed

    public var errorDescription: String? {
        switch self {
        case .destinationUnavailable:
            "无法创建截图文件。"
        case .writeFailed:
            "无法写入截图文件。"
        }
    }
}

public enum CaptureImageWriter {
    public static func write(
        _ image: CGImage,
        to url: URL,
        format: CaptureOutputFormat,
        jpegQuality: Double = 0.9
    ) throws {
        let typeIdentifier: CFString = switch format {
        case .png: UTType.png.identifier as CFString
        case .jpeg: UTType.jpeg.identifier as CFString
        }
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            typeIdentifier,
            1,
            nil
        ) else {
            throw CaptureImageWriterError.destinationUnavailable
        }

        let properties: CFDictionary? = switch format {
        case .png:
            nil
        case .jpeg:
            [
                kCGImageDestinationLossyCompressionQuality:
                    min(max(jpegQuality, 0.1), 1)
            ] as CFDictionary
        }
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else {
            throw CaptureImageWriterError.writeFailed
        }
    }
}
