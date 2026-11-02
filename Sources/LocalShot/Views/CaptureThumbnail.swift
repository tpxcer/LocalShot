import AppKit
import ImageIO

@MainActor
enum CaptureThumbnail {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(for url: URL, maxPixelSize: Int) -> NSImage {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0
        let key = "\(url.path)|\(modified)|\(maxPixelSize)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return NSImage()
        }
        let image = NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
        cache.setObject(image, forKey: key)
        return image
    }
}
