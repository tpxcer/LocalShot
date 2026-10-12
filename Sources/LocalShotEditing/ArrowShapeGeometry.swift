import Foundation

public struct ArrowShapeGeometry: Hashable, Sendable {
    public let points: [AnnotationPoint]

    public init(_ arrow: ArrowAnnotation) {
        self.init(start: arrow.start, end: arrow.end, lineWidth: arrow.lineWidth)
    }

    public init(start: AnnotationPoint, end: AnnotationPoint, lineWidth: Double) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0.000_001 else {
            points = [start]
            return
        }

        let unitX = dx / length
        let unitY = dy / length
        let normalX = -unitY
        let normalY = unitX
        let baseBodyWidth = max(7.5, lineWidth * 1.6875)
        let baseTailWidth = max(3.125, baseBodyWidth * 0.42)
        let baseHeadLength = max(27.5, lineWidth * 4)
        let baseHeadWidth = max(22.5, baseBodyWidth * 2.15)
        let compactScale = min(1, length / (baseHeadLength + 8))
        let bodyHalfWidth = baseBodyWidth * compactScale / 2
        let tailHalfWidth = baseTailWidth * compactScale / 2
        let headHalfWidth = min(length * 0.4, baseHeadWidth * compactScale / 2)
        let headLength = min(length * 0.58, baseHeadLength * compactScale)
        let neck = AnnotationPoint(
            x: end.x - unitX * headLength,
            y: end.y - unitY * headLength
        )

        func offset(_ point: AnnotationPoint, by distance: Double) -> AnnotationPoint {
            AnnotationPoint(
                x: point.x + normalX * distance,
                y: point.y + normalY * distance
            )
        }

        points = [
            offset(start, by: tailHalfWidth),
            offset(neck, by: bodyHalfWidth),
            offset(neck, by: headHalfWidth),
            end,
            offset(neck, by: -headHalfWidth),
            offset(neck, by: -bodyHalfWidth),
            offset(start, by: -tailHalfWidth)
        ]
    }

    public var bounds: AnnotationRect {
        AnnotationRect.enclosing(points)
    }

    public func contains(_ point: AnnotationPoint, tolerance: Double = 0) -> Bool {
        guard points.count >= 3 else {
            guard let first = points.first else {
                return false
            }
            return hypot(point.x - first.x, point.y - first.y) <= tolerance
        }
        if containsInsidePolygon(point) {
            return true
        }
        let edges = zip(points, points.dropFirst() + [points[0]])
        return edges.contains {
            distance(point, toSegmentFrom: $0.0, to: $0.1) <= tolerance
        }
    }

    private func containsInsidePolygon(_ point: AnnotationPoint) -> Bool {
        var isInside = false
        var previous = points[points.count - 1]
        for current in points {
            let crossesHorizontalRay = (current.y > point.y) != (previous.y > point.y)
            if crossesHorizontalRay {
                let intersectionX = (previous.x - current.x)
                    * (point.y - current.y)
                    / (previous.y - current.y)
                    + current.x
                if point.x < intersectionX {
                    isInside.toggle()
                }
            }
            previous = current
        }
        return isInside
    }

    private func distance(
        _ point: AnnotationPoint,
        toSegmentFrom start: AnnotationPoint,
        to end: AnnotationPoint
    ) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let squaredLength = dx * dx + dy * dy
        guard squaredLength > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }
        let projection = max(
            0,
            min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / squaredLength)
        )
        return hypot(
            point.x - (start.x + projection * dx),
            point.y - (start.y + projection * dy)
        )
    }
}
