import CoreGraphics
import CoreText
import Foundation
import ImageIO
import LocalShotVision
import UniformTypeIdentifiers

enum OCRCheckError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message): message
        }
    }
}

@main
struct LocalShotOCRCheck {
    static func main() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalShotOCRCheck-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let imageURL = directory.appendingPathComponent("ocr-source.png")
            try writeTextImage(to: imageURL)

            let blocks = try await VisionOCRService().recognizeText(in: imageURL)
            let combined = blocks.map(\.text).joined(separator: " ").lowercased()
            guard combined.contains("localshot") || combined.contains("123") else {
                throw OCRCheckError.failed("识别结果不包含预期文字：\(combined)")
            }
            guard blocks.allSatisfy({
                $0.boundingBox.x >= 0 && $0.boundingBox.y >= 0 &&
                $0.boundingBox.width <= 1 && $0.boundingBox.height <= 1
            }) else {
                throw OCRCheckError.failed("文字坐标不在归一化范围内")
            }

            let fixtureURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("TestFixtures", isDirectory: true)
                .appendingPathComponent("LocalShot-UI-Acceptance.png")
            guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
                throw OCRCheckError.failed("缺少界面验收图片：\(fixtureURL.path)")
            }

            let fixtureBlocks = try await VisionOCRService().recognizeText(in: fixtureURL)
            let fixtureText = fixtureBlocks.map(\.text).joined(separator: " ").lowercased()
            for expectedText in ["localshot", "hello", "123456"] {
                guard fixtureText.contains(expectedText) else {
                    throw OCRCheckError.failed(
                        "验收图片识别结果缺少 \(expectedText)：\(fixtureText)"
                    )
                }
            }

            print("LocalShotOCRCheck: PASS - \(combined); fixture blocks: \(fixtureBlocks.count)")
        } catch {
            fputs("LocalShotOCRCheck: FAIL - \(error)\n", stderr)
            exit(1)
        }
    }

    private static func writeTextImage(to url: URL) throws {
        let width = 900
        let height = 240
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw OCRCheckError.failed("无法创建 OCR 图片")
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 72, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: "LocalShot 123", attributes: attributes)
        )
        context.textPosition = CGPoint(x: 55, y: 85)
        CTLineDraw(line, context)

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
              ) else {
            throw OCRCheckError.failed("无法创建 OCR 图片文件")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw OCRCheckError.failed("无法写入 OCR 图片")
        }
    }
}
