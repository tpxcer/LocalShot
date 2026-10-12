import CoreGraphics
import Foundation
import ImageIO
import LocalShotBeautification
import UniformTypeIdentifiers

enum BeautificationCheckError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message): message
        }
    }
}

@main
struct LocalShotBeautificationCheck {
    static func main() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalShotBeautificationCheck-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let baseURL = directory.appendingPathComponent("base.png")
            let outputURL = directory.appendingPathComponent("styled.png")
            try writeBaseImage(to: baseURL)

            let options = ImageBeautificationOptions(
                background: .solid(BeautificationColor(red: 0.9, green: 0.1, blue: 0.15)),
                padding: 40,
                cornerRadius: 24,
                shadowRadius: 12,
                shadowOpacity: 0.25,
                aspectRatio: .square
            )
            try ImageBeautificationRenderer.render(
                baseImageURL: baseURL,
                options: options,
                outputURL: outputURL
            )

            guard let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw BeautificationCheckError.failed("无法读取美化图片")
            }
            guard image.width == 400, image.height == 400 else {
                throw BeautificationCheckError.failed("美化图片尺寸错误：\(image.width)×\(image.height)")
            }

            let cornerPixel = try samplePixel(image, x: 4, y: 4)
            guard cornerPixel.red > 0.75, cornerPixel.green < 0.25, cornerPixel.blue < 0.3 else {
                throw BeautificationCheckError.failed("背景颜色未正确渲染")
            }

            let centerPixel = try samplePixel(image, x: 200, y: 200)
            guard centerPixel.blue > 0.7, centerPixel.red < 0.3 else {
                throw BeautificationCheckError.failed("原图未正确居中渲染")
            }

            print("LocalShotBeautificationCheck: PASS")
        } catch {
            fputs("LocalShotBeautificationCheck: FAIL - \(error)\n", stderr)
            exit(1)
        }
    }

    private static func writeBaseImage(to url: URL) throws {
        guard let context = CGContext(
            data: nil,
            width: 320,
            height: 180,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw BeautificationCheckError.failed("无法创建基础图片")
        }
        context.setFillColor(CGColor(red: 0.08, green: 0.35, blue: 0.92, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
              ) else {
            throw BeautificationCheckError.failed("无法创建基础图片文件")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw BeautificationCheckError.failed("无法写入基础图片")
        }
    }

    private static func samplePixel(
        _ image: CGImage,
        x: Int,
        y: Int
    ) throws -> (red: Double, green: Double, blue: Double, alpha: Double) {
        var bytes = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &bytes,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw BeautificationCheckError.failed("无法读取输出像素")
        }
        context.interpolationQuality = .none
        context.translateBy(x: -CGFloat(x), y: -CGFloat(y))
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )
        return (
            Double(bytes[0]) / 255,
            Double(bytes[1]) / 255,
            Double(bytes[2]) / 255,
            Double(bytes[3]) / 255
        )
    }
}
