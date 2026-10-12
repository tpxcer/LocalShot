import AppKit
import ImageIO
import LocalShotBeautification
import LocalShotCore
import UniformTypeIdentifiers

enum ImageBeautifierModelError: LocalizedError {
    case imageReadFailed

    var errorDescription: String? {
        "无法读取需要美化的截图。"
    }
}

@MainActor
final class ImageBeautifierModel: ObservableObject {
    @Published var backgroundPreset: BeautificationBackgroundPreset = .system
    @Published var padding = 56.0
    @Published var cornerRadius = 18.0
    @Published var shadowRadius = 20.0
    @Published var shadowOpacity = 0.28
    @Published var aspectRatio: BeautificationAspectRatio = .automatic
    @Published var errorMessage: String?

    let asset: CaptureAsset
    let image: NSImage
    let sourcePixelSize: CGSize

    init(asset: CaptureAsset) throws {
        guard let image = NSImage(contentsOf: asset.url),
              let source = CGImageSourceCreateWithURL(asset.url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImageBeautifierModelError.imageReadFailed
        }
        self.asset = asset
        self.image = image
        sourcePixelSize = CGSize(width: cgImage.width, height: cgImage.height)
    }

    var options: ImageBeautificationOptions {
        ImageBeautificationOptions(
            background: backgroundPreset.background,
            padding: padding,
            cornerRadius: cornerRadius,
            shadowRadius: shadowRadius,
            shadowOpacity: shadowOpacity,
            aspectRatio: aspectRatio
        )
    }

    func reset() {
        backgroundPreset = .system
        padding = 56
        cornerRadius = 18
        shadowRadius = 20
        shadowOpacity = 0.28
        aspectRatio = .automatic
        errorMessage = nil
    }

    func exportAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = asset.url
            .deletingPathExtension()
            .lastPathComponent + "-styled.png"
        panel.canCreateDirectories = true

        panel.begin { [weak self] response in
            guard let self, response == .OK, let outputURL = panel.url else {
                return
            }
            do {
                try LocalFileExporter.exportGeneratedFile(to: outputURL) { temporaryURL in
                    try ImageBeautificationRenderer.render(
                        baseImageURL: self.asset.url,
                        options: self.options,
                        outputURL: temporaryURL
                    )
                }
                self.errorMessage = nil
            } catch {
                self.errorMessage = "导出美化图片失败：\(error.localizedDescription)"
            }
        }
    }
}
