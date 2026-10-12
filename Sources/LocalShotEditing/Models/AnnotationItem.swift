import Foundation

public struct ArrowAnnotation: Codable, Hashable, Sendable {
    public let id: UUID
    public var start: AnnotationPoint
    public var end: AnnotationPoint
    public var color: AnnotationColor
    public var lineWidth: Double
    public var note: String?
    public var noteFontSize: Double

    public init(
        id: UUID = UUID(),
        start: AnnotationPoint,
        end: AnnotationPoint,
        color: AnnotationColor = .red,
        lineWidth: Double = 4,
        note: String? = nil,
        noteFontSize: Double = 18
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.color = color
        self.lineWidth = lineWidth
        self.note = Self.normalizedNote(note)
        self.noteFontSize = max(11, noteFontSize)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case start
        case end
        case color
        case lineWidth
        case note
        case noteFontSize
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        start = try container.decode(AnnotationPoint.self, forKey: .start)
        end = try container.decode(AnnotationPoint.self, forKey: .end)
        color = try container.decode(AnnotationColor.self, forKey: .color)
        lineWidth = try container.decode(Double.self, forKey: .lineWidth)
        note = Self.normalizedNote(try container.decodeIfPresent(String.self, forKey: .note))
        noteFontSize = max(
            11,
            try container.decodeIfPresent(Double.self, forKey: .noteFontSize) ?? 18
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encode(color, forKey: .color)
        try container.encode(lineWidth, forKey: .lineWidth)
        try container.encodeIfPresent(Self.normalizedNote(note), forKey: .note)
        try container.encode(noteFontSize, forKey: .noteFontSize)
    }

    public func noteOrigin(width: Double, height: Double) -> AnnotationPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(0.000_001, hypot(dx, dy))
        let unitX = dx / length
        let unitY = dy / length
        let gap = max(6, lineWidth * 1.5)
        let anchorX = start.x - unitX * gap
        let anchorY = start.y - unitY * gap
        let originX: Double
        if abs(unitX) < 0.25 {
            originX = anchorX - width / 2
        } else if unitX > 0 {
            originX = anchorX - width
        } else {
            originX = anchorX
        }
        return AnnotationPoint(
            x: originX,
            y: anchorY - height / 2
        )
    }

    private static func normalizedNote(_ note: String?) -> String? {
        guard let normalized = note?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty else {
            return nil
        }
        return normalized
    }
}

public struct RectangleAnnotation: Codable, Hashable, Sendable {
    public let id: UUID
    public var rect: AnnotationRect
    public var color: AnnotationColor
    public var lineWidth: Double
    public var fillColor: AnnotationColor?

    public init(
        id: UUID = UUID(),
        rect: AnnotationRect,
        color: AnnotationColor = .red,
        lineWidth: Double = 4,
        fillColor: AnnotationColor? = nil
    ) {
        self.id = id
        self.rect = rect
        self.color = color
        self.lineWidth = lineWidth
        self.fillColor = fillColor
    }
}

public struct EllipseAnnotation: Codable, Hashable, Sendable {
    public let id: UUID
    public var rect: AnnotationRect
    public var color: AnnotationColor
    public var lineWidth: Double
    public var fillColor: AnnotationColor?

    public init(
        id: UUID = UUID(),
        rect: AnnotationRect,
        color: AnnotationColor = .red,
        lineWidth: Double = 4,
        fillColor: AnnotationColor? = nil
    ) {
        self.id = id
        self.rect = rect
        self.color = color
        self.lineWidth = lineWidth
        self.fillColor = fillColor
    }
}

public struct LineAnnotation: Codable, Hashable, Sendable {
    public let id: UUID
    public var start: AnnotationPoint
    public var end: AnnotationPoint
    public var color: AnnotationColor
    public var lineWidth: Double
    public var isDashed: Bool

    public init(
        id: UUID = UUID(),
        start: AnnotationPoint,
        end: AnnotationPoint,
        color: AnnotationColor = .red,
        lineWidth: Double = 4,
        isDashed: Bool = false
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.color = color
        self.lineWidth = lineWidth
        self.isDashed = isDashed
    }
}

public struct PenAnnotation: Codable, Hashable, Sendable {
    public let id: UUID
    public var points: [AnnotationPoint]
    public var color: AnnotationColor
    public var lineWidth: Double

    public init(
        id: UUID = UUID(),
        points: [AnnotationPoint],
        color: AnnotationColor = .red,
        lineWidth: Double = 4
    ) {
        self.id = id
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
    }
}

public struct HighlightAnnotation: Codable, Hashable, Sendable {
    public let id: UUID
    public var points: [AnnotationPoint]
    public var color: AnnotationColor
    public var lineWidth: Double
    public var opacity: Double

    public init(
        id: UUID = UUID(),
        points: [AnnotationPoint],
        color: AnnotationColor = AnnotationColor(red: 1, green: 0.78, blue: 0.05),
        lineWidth: Double = 18,
        opacity: Double = 0.36
    ) {
        self.id = id
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
        self.opacity = min(max(opacity, 0.05), 0.9)
    }
}

public struct TextAnnotation: Codable, Hashable, Sendable {
    public let id: UUID
    public var position: AnnotationPoint
    public var text: String
    public var color: AnnotationColor
    public var fontSize: Double

    public init(
        id: UUID = UUID(),
        position: AnnotationPoint,
        text: String,
        color: AnnotationColor = .red,
        fontSize: Double = 24
    ) {
        self.id = id
        self.position = position
        self.text = text
        self.color = color
        self.fontSize = fontSize
    }
}

public enum PixelateEffect: String, Codable, Hashable, Sendable {
    case mosaic
    case blur
}

public struct PixelateAnnotation: Codable, Hashable, Sendable {
    public let id: UUID
    public var rect: AnnotationRect
    public var scale: Double
    public var effect: PixelateEffect

    public init(
        id: UUID = UUID(),
        rect: AnnotationRect,
        scale: Double = 10,
        effect: PixelateEffect = .mosaic
    ) {
        self.id = id
        self.rect = rect
        self.scale = scale
        self.effect = effect
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case rect
        case scale
        case effect
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        rect = try container.decode(AnnotationRect.self, forKey: .rect)
        scale = try container.decode(Double.self, forKey: .scale)
        effect = try container.decodeIfPresent(PixelateEffect.self, forKey: .effect) ?? .mosaic
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(rect, forKey: .rect)
        try container.encode(scale, forKey: .scale)
        try container.encode(effect, forKey: .effect)
    }
}

public struct RedactionAnnotation: Codable, Hashable, Sendable {
    public let id: UUID
    public var rect: AnnotationRect
    public var color: AnnotationColor

    public init(
        id: UUID = UUID(),
        rect: AnnotationRect,
        color: AnnotationColor = .black
    ) {
        self.id = id
        self.rect = rect
        self.color = color
    }
}

public struct StepAnnotation: Codable, Hashable, Sendable {
    public let id: UUID
    public var center: AnnotationPoint
    public var number: Int
    public var diameter: Double
    public var fillColor: AnnotationColor
    public var textColor: AnnotationColor
    public var note: String?

    public init(
        id: UUID = UUID(),
        center: AnnotationPoint,
        number: Int,
        diameter: Double = 34,
        fillColor: AnnotationColor = .red,
        textColor: AnnotationColor = .white,
        note: String? = nil
    ) {
        self.id = id
        self.center = center
        self.number = max(1, number)
        self.diameter = max(16, diameter)
        self.fillColor = fillColor
        self.textColor = textColor
        self.note = Self.normalizedNote(note)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case center
        case number
        case diameter
        case fillColor
        case textColor
        case note
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        center = try container.decode(AnnotationPoint.self, forKey: .center)
        number = max(1, try container.decode(Int.self, forKey: .number))
        diameter = max(16, try container.decode(Double.self, forKey: .diameter))
        fillColor = try container.decode(AnnotationColor.self, forKey: .fillColor)
        textColor = try container.decode(AnnotationColor.self, forKey: .textColor)
        note = Self.normalizedNote(try container.decodeIfPresent(String.self, forKey: .note))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(center, forKey: .center)
        try container.encode(number, forKey: .number)
        try container.encode(diameter, forKey: .diameter)
        try container.encode(fillColor, forKey: .fillColor)
        try container.encode(textColor, forKey: .textColor)
        try container.encodeIfPresent(Self.normalizedNote(note), forKey: .note)
    }

    private static func normalizedNote(_ note: String?) -> String? {
        guard let normalized = note?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty else {
            return nil
        }
        return normalized
    }
}

public struct SpotlightAnnotation: Codable, Hashable, Sendable {
    public let id: UUID
    public var focusRect: AnnotationRect
    public var dimOpacity: Double

    public init(
        id: UUID = UUID(),
        focusRect: AnnotationRect,
        dimOpacity: Double = 0.58
    ) {
        self.id = id
        self.focusRect = focusRect
        self.dimOpacity = min(max(dimOpacity, 0.1), 0.9)
    }
}

public enum AnnotationItem: Codable, Hashable, Sendable, Identifiable {
    case arrow(ArrowAnnotation)
    case rectangle(RectangleAnnotation)
    case ellipse(EllipseAnnotation)
    case line(LineAnnotation)
    case pen(PenAnnotation)
    case highlight(HighlightAnnotation)
    case text(TextAnnotation)
    case pixelate(PixelateAnnotation)
    case redaction(RedactionAnnotation)
    case step(StepAnnotation)
    case spotlight(SpotlightAnnotation)

    public var id: UUID {
        switch self {
        case let .arrow(value): value.id
        case let .rectangle(value): value.id
        case let .ellipse(value): value.id
        case let .line(value): value.id
        case let .pen(value): value.id
        case let .highlight(value): value.id
        case let .text(value): value.id
        case let .pixelate(value): value.id
        case let .redaction(value): value.id
        case let .step(value): value.id
        case let .spotlight(value): value.id
        }
    }
}
