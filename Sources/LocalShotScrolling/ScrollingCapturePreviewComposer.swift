import CoreGraphics
import Foundation
import ImageIO

public final class ScrollingCapturePreviewComposer {
    private let previewWidth: Int
    private var previewImage: CGImage?

    public init(previewWidth: Int = 236) {
        self.previewWidth = max(80, previewWidth)
    }

    public func append(
        segmentURL: URL,
        transition: ScrollTransitionAnalysis?
    ) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(segmentURL as CFURL, nil),
              let segment = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw VerticalImageStitcherError.imageReadFailed(segmentURL)
        }

        let removedTop = max(0, transition.map { $0.topInset + ($0.overlap ?? 0) } ?? 0)
        let appendedHeight = segment.height - removedTop
        guard appendedHeight > 0,
              let appended = segment.cropping(to: CGRect(
                x: 0,
                y: removedTop,
                width: segment.width,
                height: appendedHeight
              )) else {
            throw VerticalImageStitcherError.outputTooLarge
        }
        let scaled = try scaledImage(appended)

        guard var current = previewImage else {
            previewImage = scaled
            return scaled
        }
        if let transition, transition.bottomInset > 0 {
            let scaledBottomInset = max(
                1,
                Int((Double(transition.bottomInset) * Double(previewWidth) / Double(segment.width)).rounded())
            )
            let retainedHeight = current.height - scaledBottomInset
            if retainedHeight > 0,
               let retained = current.cropping(to: CGRect(
                x: 0,
                y: 0,
                width: current.width,
                height: retainedHeight
               )) {
                current = retained
            }
        }
        let outputHeight = current.height + scaled.height
        guard outputHeight <= 50_000,
              let context = makeContext(width: previewWidth, height: outputHeight) else {
            throw VerticalImageStitcherError.outputTooLarge
        }
        context.interpolationQuality = .high
        context.draw(current, in: CGRect(
            x: 0,
            y: scaled.height,
            width: previewWidth,
            height: current.height
        ))
        context.draw(scaled, in: CGRect(
            x: 0,
            y: 0,
            width: previewWidth,
            height: scaled.height
        ))
        guard let output = context.makeImage() else {
            throw VerticalImageStitcherError.bitmapCreationFailed
        }
        previewImage = output
        return output
    }

    private func scaledImage(_ image: CGImage) throws -> CGImage {
        let height = max(1, Int((Double(image.height) * Double(previewWidth) / Double(image.width)).rounded()))
        guard let context = makeContext(width: previewWidth, height: height) else {
            throw VerticalImageStitcherError.bitmapCreationFailed
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: previewWidth, height: height))
        guard let output = context.makeImage() else {
            throw VerticalImageStitcherError.bitmapCreationFailed
        }
        return output
    }

    private func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}
