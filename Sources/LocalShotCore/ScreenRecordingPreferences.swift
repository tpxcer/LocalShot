import Foundation

public enum ScreenRecordingQuality: String, CaseIterable, Identifiable, Sendable {
    case standard
    case high
    case original

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .standard: "标准（最长边 1280）"
        case .high: "高清（最长边 1920）"
        case .original: "原画"
        }
    }

    public var shortDisplayName: String {
        switch self {
        case .standard: "标准"
        case .high: "高清"
        case .original: "原画"
        }
    }

    public func outputSize(for sourceSize: CGSize) -> CGSize {
        let limit: CGFloat?
        switch self {
        case .standard: limit = 1_280
        case .high: limit = 1_920
        case .original: limit = nil
        }
        guard let limit,
              max(sourceSize.width, sourceSize.height) > limit else {
            return sourceSize
        }
        let scale = limit / max(sourceSize.width, sourceSize.height)
        return CGSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )
    }
}

public enum ScreenRecordingFrameRate: Int, CaseIterable, Identifiable, Sendable {
    case fps30 = 30
    case fps60 = 60

    public var id: Int { rawValue }
    public var displayName: String { "\(rawValue) FPS" }
}

public struct ScreenRecordingSizeEstimate: Equatable, Sendable {
    public let lowerBytesPerMinute: Int64
    public let upperBytesPerMinute: Int64

    public init(lowerBytesPerMinute: Int64, upperBytesPerMinute: Int64) {
        self.lowerBytesPerMinute = lowerBytesPerMinute
        self.upperBytesPerMinute = upperBytesPerMinute
    }
}

public enum ScreenRecordingSizeEstimator {
    public static func estimatePerMinute(
        pixelSize: CGSize,
        frameRate: ScreenRecordingFrameRate,
        capturesAudio: Bool
    ) -> ScreenRecordingSizeEstimate {
        let pixelRate = max(1, pixelSize.width)
            * max(1, pixelSize.height)
            * CGFloat(frameRate.rawValue)
        let audioBitsPerSecond: CGFloat = capturesAudio ? 192_000 : 0
        let lowerBitsPerSecond = pixelRate * 0.035 + audioBitsPerSecond
        let upperBitsPerSecond = pixelRate * 0.12 + audioBitsPerSecond
        return ScreenRecordingSizeEstimate(
            lowerBytesPerMinute: Int64((lowerBitsPerSecond * 60 / 8).rounded(.up)),
            upperBytesPerMinute: Int64((upperBitsPerSecond * 60 / 8).rounded(.up))
        )
    }
}
