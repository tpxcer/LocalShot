import CoreGraphics
import Foundation
import ImageIO
import LocalShotTranslation
import LocalShotVision
import UniformTypeIdentifiers

enum TranslationCheckError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message): message
        }
    }
}

@main
struct LocalShotTranslationCheck {
    static func main() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalShotTranslationCheck-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let baseURL = directory.appendingPathComponent("base.png")
            let outputURL = directory.appendingPathComponent("translated.png")
            try writeBaseImage(to: baseURL)

            let blocks = [
                TranslationTextBlock(
                    sourceText: "Settings",
                    targetText: "设置",
                    boundingBox: OCRBoundingBox(x: 0.08, y: 0.66, width: 0.28, height: 0.16)
                ),
                TranslationTextBlock(
                    sourceText: "Privacy and Security",
                    targetText: "隐私与安全性",
                    boundingBox: OCRBoundingBox(x: 0.08, y: 0.36, width: 0.48, height: 0.16)
                )
            ]
            try TranslationOverlayRenderer.render(
                baseImageURL: baseURL,
                blocks: blocks,
                outputURL: outputURL
            )

            guard let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw TranslationCheckError.failed("无法读取翻译图片")
            }
            guard image.width == 640, image.height == 360 else {
                throw TranslationCheckError.failed("翻译图片尺寸错误")
            }
            print("LocalShotTranslationCheck: PASS")
        } catch {
            fputs("LocalShotTranslationCheck: FAIL - \(error)\n", stderr)
            exit(1)
        }
    }

    private static func writeBaseImage(to url: URL) throws {
        guard let context = CGContext(
            data: nil,
            width: 640,
            height: 360,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TranslationCheckError.failed("无法创建基础图片")
        }
        context.setFillColor(CGColor(red: 0.10, green: 0.13, blue: 0.18, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 640, height: 360))
        context.setFillColor(CGColor(red: 0.17, green: 0.21, blue: 0.29, alpha: 1))
        context.fill(CGRect(x: 35, y: 80, width: 570, height: 230))

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
              ) else {
            throw TranslationCheckError.failed("无法创建基础文件")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TranslationCheckError.failed("无法写入基础文件")
        }
    }
}
