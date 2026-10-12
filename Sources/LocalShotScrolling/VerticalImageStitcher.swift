import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum VerticalImageStitcherError: LocalizedError {
    case noImages
    case imageReadFailed(URL)
    case widthMismatch
    case bitmapCreationFailed
    case overlapNotFound(Int)
    case outputTooLarge
    case imageWriteFailed

    public var errorDescription: String? {
        switch self {
        case .noImages: "没有可拼接的图片。"
        case let .imageReadFailed(url): "无法读取滚动截图片段：\(url.lastPathComponent)"
        case .widthMismatch: "滚动截图片段宽度不一致。"
        case .bitmapCreationFailed: "无法分析滚动截图像素。"
        case let .overlapNotFound(index): "无法识别第 \(index + 1) 张片段的重叠区域。"
        case .outputTooLarge: "滚动截图结果过大，无法安全创建。"
        case .imageWriteFailed: "无法写入滚动截图结果。"
        }
    }
}

public struct VerticalStitchResult: Hashable, Sendable {
    public let width: Int
    public let height: Int
    public let overlaps: [Int]
    public let topInsets: [Int]
    public let bottomInsets: [Int]

    public init(
        width: Int,
        height: Int,
        overlaps: [Int],
        topInsets: [Int] = [],
        bottomInsets: [Int] = []
    ) {
        self.width = width
        self.height = height
        self.overlaps = overlaps
        self.topInsets = topInsets
        self.bottomInsets = bottomInsets
    }
}

public struct ScrollTransitionAnalysis: Hashable, Sendable {
    public let frameDifference: Double
    public let overlap: Int?
    public let topInset: Int
    public let bottomInset: Int
    public let frameHeight: Int

    public init(
        frameDifference: Double,
        overlap: Int?,
        topInset: Int = 0,
        bottomInset: Int = 0,
        frameHeight: Int = 0
    ) {
        self.frameDifference = frameDifference
        self.overlap = overlap
        self.topInset = topInset
        self.bottomInset = bottomInset
        self.frameHeight = frameHeight
    }
}

private struct OverlapMatch {
    let overlap: Int
    let difference: Double
}

private struct TransitionMatch {
    let overlap: OverlapMatch?
    let topInset: Int
    let bottomInset: Int
}

public enum VerticalImageStitcher {
    public static func analyzeTransition(
        previousURL: URL,
        nextURL: URL,
        minimumOverlap: Int = 16,
        maximumDifference: Double = 18
    ) throws -> ScrollTransitionAnalysis {
        let previousImage = try loadImage(at: previousURL)
        let nextImage = try loadImage(at: nextURL)
        guard previousImage.width == nextImage.width else {
            throw VerticalImageStitcherError.widthMismatch
        }
        let previous = try RowSignatureImage(image: previousImage)
        let next = try RowSignatureImage(image: nextImage)
        let match = matchTransition(
            previous: previous,
            next: next,
            minimumOverlap: minimumOverlap,
            maximumDifference: maximumDifference
        )
        return ScrollTransitionAnalysis(
            frameDifference: previous.meanDifference(
                to: next,
                excludingLeadingRows: match.topInset,
                excludingTrailingRows: match.bottomInset
            ),
            overlap: match.overlap?.overlap,
            topInset: match.topInset,
            bottomInset: match.bottomInset,
            frameHeight: previous.height
        )
    }

    public static func stitch(
        imageURLs: [URL],
        outputURL: URL,
        minimumOverlap: Int = 16,
        maximumDifference: Double = 18
    ) throws -> VerticalStitchResult {
        guard !imageURLs.isEmpty else {
            throw VerticalImageStitcherError.noImages
        }

        let images = try imageURLs.map(loadImage)
        guard let first = images.first else {
            throw VerticalImageStitcherError.noImages
        }
        guard images.allSatisfy({ $0.width == first.width }) else {
            throw VerticalImageStitcherError.widthMismatch
        }

        let signatures = try images.map(RowSignatureImage.init)
        var overlaps: [Int] = []
        var topInsets: [Int] = []
        var bottomInsets: [Int] = []
        for index in 1..<images.count {
            let match = matchTransition(
                previous: signatures[index - 1],
                next: signatures[index],
                minimumOverlap: minimumOverlap,
                maximumDifference: maximumDifference
            )
            guard let overlap = match.overlap?.overlap else {
                throw VerticalImageStitcherError.overlapNotFound(index)
            }
            overlaps.append(overlap)
            topInsets.append(match.topInset)
            bottomInsets.append(match.bottomInset)
        }

        var slices: [CGImage] = []
        slices.reserveCapacity(images.count)
        for index in images.indices {
            let startRow = index == 0 ? 0 : topInsets[index - 1] + overlaps[index - 1]
            let endRow = index == images.count - 1
                ? images[index].height
                : images[index].height - bottomInsets[index]
            let height = endRow - startRow
            guard height > 0,
                  let slice = images[index].cropping(to: CGRect(
                    x: 0,
                    y: startRow,
                    width: images[index].width,
                    height: height
                  )) else {
                throw VerticalImageStitcherError.outputTooLarge
            }
            slices.append(slice)
        }
        let outputHeight = slices.reduce(0) { $0 + $1.height }
        guard outputHeight > 0,
              outputHeight <= 100_000,
              first.width <= 20_000 else {
            throw VerticalImageStitcherError.outputTooLarge
        }
        guard let context = CGContext(
            data: nil,
            width: first.width,
            height: outputHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw VerticalImageStitcherError.bitmapCreationFailed
        }

        var imageY = outputHeight
        for slice in slices {
            imageY -= slice.height
            context.draw(
                slice,
                in: CGRect(x: 0, y: imageY, width: slice.width, height: slice.height)
            )
        }

        guard let output = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                outputURL as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
              ) else {
            throw VerticalImageStitcherError.imageWriteFailed
        }
        CGImageDestinationAddImage(destination, output, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw VerticalImageStitcherError.imageWriteFailed
        }

        return VerticalStitchResult(
            width: first.width,
            height: outputHeight,
            overlaps: overlaps,
            topInsets: topInsets,
            bottomInsets: bottomInsets
        )
    }

    private static func matchTransition(
        previous: RowSignatureImage,
        next: RowSignatureImage,
        minimumOverlap: Int,
        maximumDifference: Double
    ) -> TransitionMatch {
        let topInset = detectStableTopInset(
            previous: previous,
            next: next,
            minimumOverlap: minimumOverlap,
            maximumDifference: maximumDifference
        )
        let bottomInset = detectStableBottomInset(
            previous: previous,
            next: next,
            minimumOverlap: minimumOverlap,
            maximumDifference: maximumDifference
        )
        var insetOptions = [(top: 0, bottom: 0)]
        if topInset > 0 {
            insetOptions.append((topInset, 0))
        }
        if bottomInset > 0 {
            insetOptions.append((0, bottomInset))
        }
        if topInset > 0, bottomInset > 0 {
            insetOptions.append((topInset, bottomInset))
        }
        let matches = insetOptions.compactMap { option -> TransitionMatch? in
            let overlap = detectOverlap(
                previous: previous,
                next: next,
                previousEndRow: previous.height - option.bottom,
                nextStartRow: option.top,
                nextEndRow: next.height - option.bottom,
                minimumOverlap: minimumOverlap,
                maximumDifference: maximumDifference
            )
            return overlap.map {
                TransitionMatch(overlap: $0, topInset: option.top, bottomInset: option.bottom)
            }
        }
        guard let bestDifference = matches.compactMap(\.overlap?.difference).min() else {
            return TransitionMatch(overlap: nil, topInset: 0, bottomInset: 0)
        }
        return matches
            .filter { ($0.overlap?.difference ?? .greatestFiniteMagnitude) <= bestDifference + 0.5 }
            .max {
                let firstInsets = $0.topInset + $0.bottomInset
                let secondInsets = $1.topInset + $1.bottomInset
                if firstInsets != secondInsets {
                    return firstInsets < secondInsets
                }
                return ($0.overlap?.overlap ?? 0) < ($1.overlap?.overlap ?? 0)
            } ?? TransitionMatch(overlap: nil, topInset: 0, bottomInset: 0)
    }

    private static func detectStableTopInset(
        previous: RowSignatureImage,
        next: RowSignatureImage,
        minimumOverlap: Int,
        maximumDifference: Double
    ) -> Int {
        let maximumInset = min(
            512,
            min(
                min(previous.height, next.height) * 2 / 5,
                next.height - minimumOverlap
            )
        )
        guard maximumInset >= 8 else {
            return 0
        }
        let stableDifference = min(8, max(2, maximumDifference / 3))
        var inset = 0
        while inset < maximumInset,
              previous.rowDifference(at: inset, to: next) <= stableDifference {
            inset += 1
        }
        return inset >= 8 ? inset : 0
    }

    private static func detectStableBottomInset(
        previous: RowSignatureImage,
        next: RowSignatureImage,
        minimumOverlap: Int,
        maximumDifference: Double
    ) -> Int {
        let maximumInset = min(
            512,
            min(
                min(previous.height, next.height) * 2 / 5,
                next.height - minimumOverlap
            )
        )
        guard maximumInset >= 8 else {
            return 0
        }
        let stableDifference = min(8, max(2, maximumDifference / 3))
        var inset = 0
        while inset < maximumInset {
            let row = previous.height - inset - 1
            guard previous.rowDifference(at: row, to: next, keepingFraction: 0.98) <= stableDifference else {
                break
            }
            inset += 1
        }
        return inset >= 8 ? inset : 0
    }

    private static func detectOverlap(
        previous: RowSignatureImage,
        next: RowSignatureImage,
        previousEndRow: Int,
        nextStartRow: Int,
        nextEndRow: Int,
        minimumOverlap: Int,
        maximumDifference: Double
    ) -> OverlapMatch? {
        let availableNextHeight = nextEndRow - nextStartRow
        let maximumOverlap = min(previousEndRow, availableNextHeight) * 19 / 20
        guard maximumOverlap >= minimumOverlap else {
            return nil
        }

        var bestOverlap: Int?
        var bestDifference = Double.greatestFiniteMagnitude
        for overlap in minimumOverlap...maximumOverlap {
            let rowStep = max(1, overlap / 64)
            var differences = DifferenceAccumulator()
            var row = 0
            while row < overlap {
                let previousRow = previous.rows[previousEndRow - overlap + row]
                let nextRow = next.rows[nextStartRow + row]
                for column in previousRow.indices {
                    differences.add(previousRow[column], nextRow[column])
                }
                row += rowStep
            }
            let difference = differences.trimmedMean(keepingFraction: 0.95)
            if difference < bestDifference - 0.01
                || (abs(difference - bestDifference) <= 0.01 && overlap > (bestOverlap ?? 0)) {
                bestDifference = difference
                bestOverlap = overlap
            }
        }
        guard bestDifference <= maximumDifference else {
            return nil
        }
        guard let bestOverlap else {
            return nil
        }
        return OverlapMatch(overlap: bestOverlap, difference: bestDifference)
    }

    private static func loadImage(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw VerticalImageStitcherError.imageReadFailed(url)
        }
        return image
    }
}

private struct RowSignatureImage {
    let height: Int
    let rows: [[UInt8]]

    init(image: CGImage) throws {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let created = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard created else {
            throw VerticalImageStitcherError.bitmapCreationFailed
        }

        let sampleCount = min(32, max(8, width / 12))
        var rows: [[UInt8]] = []
        rows.reserveCapacity(height)
        for y in 0..<height {
            var signature: [UInt8] = []
            signature.reserveCapacity(sampleCount)
            for sample in 0..<sampleCount {
                let x = min(width - 1, (sample * width + width / 2) / sampleCount)
                let offset = y * bytesPerRow + x * 4
                let red = Double(pixels[offset])
                let green = Double(pixels[offset + 1])
                let blue = Double(pixels[offset + 2])
                signature.append(UInt8(red))
                signature.append(UInt8(green))
                signature.append(UInt8(blue))
            }
            rows.append(signature)
        }

        self.height = height
        self.rows = rows
    }

    func meanDifference(
        to other: RowSignatureImage,
        excludingLeadingRows: Int = 0,
        excludingTrailingRows: Int = 0
    ) -> Double {
        guard height == other.height,
              rows.first?.count == other.rows.first?.count else {
            return .greatestFiniteMagnitude
        }
        let firstRow = min(max(0, excludingLeadingRows), height - 1)
        let lastRow = max(firstRow + 1, height - max(0, excludingTrailingRows))
        let comparedHeight = lastRow - firstRow
        let rowStep = max(1, comparedHeight / 120)
        var differences = DifferenceAccumulator()
        var row = firstRow
        while row < lastRow {
            for column in rows[row].indices {
                differences.add(rows[row][column], other.rows[row][column])
            }
            row += rowStep
        }
        return differences.trimmedMean(keepingFraction: 0.85)
    }

    func rowDifference(
        at row: Int,
        to other: RowSignatureImage,
        keepingFraction: Double = 0.85
    ) -> Double {
        guard rows.indices.contains(row),
              other.rows.indices.contains(row),
              rows[row].count == other.rows[row].count else {
            return .greatestFiniteMagnitude
        }
        var differences = DifferenceAccumulator()
        for (first, second) in zip(rows[row], other.rows[row]) {
            differences.add(first, second)
        }
        return differences.trimmedMean(keepingFraction: keepingFraction)
    }
}

private struct DifferenceAccumulator {
    private var histogram = [Int](repeating: 0, count: 256)
    private var count = 0

    mutating func add(_ first: UInt8, _ second: UInt8) {
        histogram[abs(Int(first) - Int(second))] += 1
        count += 1
    }

    func trimmedMean(keepingFraction: Double) -> Double {
        guard count > 0 else {
            return .greatestFiniteMagnitude
        }
        let targetCount = max(1, Int(ceil(Double(count) * keepingFraction)))
        var remaining = targetCount
        var total = 0
        for difference in histogram.indices where remaining > 0 {
            let used = min(remaining, histogram[difference])
            total += difference * used
            remaining -= used
        }
        return Double(total) / Double(targetCount)
    }
}
