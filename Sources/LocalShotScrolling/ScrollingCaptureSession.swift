import Foundation

public enum ScrollingCaptureSessionError: LocalizedError, Equatable {
    case contentDidNotScroll
    case unsupportedTransition
    case segmentLimitReached(Int)

    public var errorDescription: String? {
        switch self {
        case .contentDidNotScroll:
            "目标窗口内容没有发生滚动，可能已到底部或不支持滚动截图。"
        case .unsupportedTransition:
            "相邻画面无法可靠匹配。该页面可能包含粘性区域、动画或横向移动。"
        case let .segmentLimitReached(limit):
            "页面超过当前安全上限（\(limit) 段），已停止且不会保存不完整长图。"
        }
    }
}

public struct ScrollingCaptureSessionResult: Hashable, Sendable {
    public let capturedSegmentCount: Int
    public let stitchResult: VerticalStitchResult

    public init(capturedSegmentCount: Int, stitchResult: VerticalStitchResult) {
        self.capturedSegmentCount = capturedSegmentCount
        self.stitchResult = stitchResult
    }
}

public enum ScrollingCaptureSession {
    @MainActor
    public static func run(
        requestedSegmentLimit: Int,
        outputURL: URL,
        captureSegment: (Int) async throws -> URL,
        advance: (Int) async throws -> Void,
        analyzeTransition: (URL, URL) throws -> ScrollTransitionAnalysis = {
            try VerticalImageStitcher.analyzeTransition(previousURL: $0, nextURL: $1)
        },
        removeSegment: (URL) -> Void = { try? FileManager.default.removeItem(at: $0) },
        stitch: ([URL], URL) throws -> VerticalStitchResult = {
            try VerticalImageStitcher.stitch(imageURLs: $0, outputURL: $1)
        },
        onAcceptedSegment: (URL, ScrollTransitionAnalysis?) -> Void = { _, _ in },
        onProgress: (Int, ScrollTransitionAnalysis?) -> Void = { _, _ in },
        shouldFinishWhenUnchanged: () -> Bool = { true }
    ) async throws -> ScrollingCaptureSessionResult {
        try Task.checkCancellation()

        let segmentLimit = ScrollingCapturePolicy.effectiveSegmentLimit(requestedSegmentLimit)
        var segmentURLs = [try await captureSegment(0)]
        var reachedEnd = false
        onAcceptedSegment(segmentURLs[0], nil)
        onProgress(1, nil)

        var index = 1
        while index < segmentLimit {
            try Task.checkCancellation()
            try await advance(index)
            try Task.checkCancellation()

            let nextURL = try await captureSegment(index)
            let transition = try analyzeTransition(segmentURLs[segmentURLs.count - 1], nextURL)
            switch ScrollingCapturePolicy.transitionDecision(for: transition) {
            case .reachedEnd:
                removeSegment(nextURL)
                if shouldFinishWhenUnchanged() {
                    reachedEnd = true
                } else {
                    continue
                }
            case .waitForMoreMovement:
                if shouldFinishWhenUnchanged() {
                    segmentURLs.append(nextURL)
                    onAcceptedSegment(nextURL, transition)
                    onProgress(segmentURLs.count, transition)
                    index += 1
                } else {
                    removeSegment(nextURL)
                    continue
                }
            case .unsupportedTransition:
                removeSegment(nextURL)
                throw ScrollingCaptureSessionError.unsupportedTransition
            case .appendSegment:
                segmentURLs.append(nextURL)
                onAcceptedSegment(nextURL, transition)
                onProgress(segmentURLs.count, transition)
                index += 1
            }
            if reachedEnd {
                break
            }
        }

        try Task.checkCancellation()
        switch ScrollingCapturePolicy.finalizationDecision(
            capturedSegmentCount: segmentURLs.count,
            reachedEnd: reachedEnd,
            requestedSegmentLimit: requestedSegmentLimit
        ) {
        case .contentDidNotScroll:
            throw ScrollingCaptureSessionError.contentDidNotScroll
        case let .segmentLimitReached(limit):
            throw ScrollingCaptureSessionError.segmentLimitReached(limit)
        case .stitch:
            let stitchResult = try stitch(segmentURLs, outputURL)
            return ScrollingCaptureSessionResult(
                capturedSegmentCount: segmentURLs.count,
                stitchResult: stitchResult
            )
        }
    }
}
