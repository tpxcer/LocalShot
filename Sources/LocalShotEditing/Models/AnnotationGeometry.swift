import CoreGraphics
import Foundation

public struct AnnotationPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init(_ point: CGPoint) {
        self.init(x: point.x, y: point.y)
    }

    public var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }

    public func offsetBy(dx: Double, dy: Double) -> AnnotationPoint {
        AnnotationPoint(x: x + dx, y: y + dy)
    }

    public func rotated(around center: AnnotationPoint, by radians: Double) -> AnnotationPoint {
        guard radians != 0 else {
            return self
        }
        let dx = x - center.x
        let dy = y - center.y
        let cosine = cos(radians)
        let sine = sin(radians)
        return AnnotationPoint(
            x: center.x + dx * cosine - dy * sine,
            y: center.y + dx * sine + dy * cosine
        )
    }
}

public struct AnnotationRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ rect: CGRect) {
        self.init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    public var normalized: AnnotationRect {
        AnnotationRect(cgRect.standardized)
    }

    public var minX: Double { normalized.x }
    public var minY: Double { normalized.y }
    public var maxX: Double { normalized.x + normalized.width }
    public var maxY: Double { normalized.y + normalized.height }

    public var center: AnnotationPoint {
        let rect = normalized
        return AnnotationPoint(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2)
    }

    public func offsetBy(dx: Double, dy: Double) -> AnnotationRect {
        let rect = normalized
        return AnnotationRect(
            x: rect.x + dx,
            y: rect.y + dy,
            width: rect.width,
            height: rect.height
        )
    }

    public func insetBy(dx: Double, dy: Double) -> AnnotationRect {
        AnnotationRect(cgRect.standardized.insetBy(dx: dx, dy: dy))
    }

    public func intersection(_ other: AnnotationRect) -> AnnotationRect {
        AnnotationRect(cgRect.standardized.intersection(other.cgRect.standardized))
    }

    public func contains(_ point: AnnotationPoint) -> Bool {
        cgRect.standardized.contains(point.cgPoint)
    }

    public static func enclosing(_ points: [AnnotationPoint]) -> AnnotationRect {
        guard let first = points.first else {
            return AnnotationRect(x: 0, y: 0, width: 0, height: 0)
        }
        var minX = first.x
        var minY = first.y
        var maxX = first.x
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        return AnnotationRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }
}

public struct AnnotationColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let red = AnnotationColor(red: 0.93, green: 0.20, blue: 0.22)
    public static let black = AnnotationColor(red: 0, green: 0, blue: 0)
    public static let white = AnnotationColor(red: 1, green: 1, blue: 1)

    var cgColor: CGColor {
        CGColor(
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            components: [red, green, blue, alpha]
        )!
    }
}
