public enum ScrollingCaptureTransitionDecision: Equatable, Sendable {
    case appendSegment
    case waitForMoreMovement
    case reachedEnd
    case unsupportedTransition
}

public enum ScrollingCaptureFinalizationDecision: Equatable, Sendable {
    case stitch
    case contentDidNotScroll
    case segmentLimitReached(Int)
}

public enum ScrollingCapturePolicy {
    public static func effectiveSegmentLimit(_ requestedLimit: Int) -> Int {
        max(2, requestedLimit)
    }

    public static func transitionDecision(
        for analysis: ScrollTransitionAnalysis,
        unchangedThreshold: Double = 0.8
    ) -> ScrollingCaptureTransitionDecision {
        if analysis.frameDifference <= unchangedThreshold {
            return .reachedEnd
        }
        guard let overlap = analysis.overlap else {
            return .unsupportedTransition
        }
        if analysis.frameHeight > 0 {
            let advancedHeight = analysis.frameHeight
                - analysis.topInset
                - analysis.bottomInset
                - overlap
            let minimumAdvance = min(96, max(24, analysis.frameHeight / 10))
            if advancedHeight < minimumAdvance {
                return .waitForMoreMovement
            }
        }
        return .appendSegment
    }

    public static func finalizationDecision(
        capturedSegmentCount: Int,
        reachedEnd: Bool,
        requestedSegmentLimit: Int
    ) -> ScrollingCaptureFinalizationDecision {
        if capturedSegmentCount < 2 {
            return .contentDidNotScroll
        }
        if !reachedEnd {
            return .segmentLimitReached(effectiveSegmentLimit(requestedSegmentLimit))
        }
        return .stitch
    }
}
