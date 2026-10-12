import CoreGraphics

public enum WindowCaptureOrdering {
    public static func frontToBack(
        _ candidates: [WindowCaptureCandidate],
        zOrderByWindowID: [CGWindowID: Int]
    ) -> [WindowCaptureCandidate] {
        candidates.enumerated().sorted { lhs, rhs in
            let lhsOrder = zOrderByWindowID[lhs.element.id] ?? Int.max
            let rhsOrder = zOrderByWindowID[rhs.element.id] ?? Int.max
            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}
