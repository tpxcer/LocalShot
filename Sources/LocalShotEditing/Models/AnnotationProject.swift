import Foundation

public struct AnnotationProject: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var imageFilename: String
    public var canvasWidth: Int
    public var canvasHeight: Int
    public var cropRect: AnnotationRect?
    public var annotations: [AnnotationItem]
    public var annotationRotations: [UUID: Double]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        imageFilename: String,
        canvasWidth: Int,
        canvasHeight: Int,
        cropRect: AnnotationRect? = nil,
        annotations: [AnnotationItem] = [],
        annotationRotations: [UUID: Double] = [:],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.imageFilename = imageFilename
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.cropRect = cropRect
        self.annotations = annotations
        self.annotationRotations = annotationRotations
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case imageFilename
        case canvasWidth
        case canvasHeight
        case cropRect
        case annotations
        case annotationRotations
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        imageFilename = try container.decode(String.self, forKey: .imageFilename)
        canvasWidth = try container.decode(Int.self, forKey: .canvasWidth)
        canvasHeight = try container.decode(Int.self, forKey: .canvasHeight)
        cropRect = try container.decodeIfPresent(AnnotationRect.self, forKey: .cropRect)
        annotations = try container.decode([AnnotationItem].self, forKey: .annotations)
        annotationRotations = try container.decodeIfPresent(
            [UUID: Double].self,
            forKey: .annotationRotations
        ) ?? [:]
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(imageFilename, forKey: .imageFilename)
        try container.encode(canvasWidth, forKey: .canvasWidth)
        try container.encode(canvasHeight, forKey: .canvasHeight)
        try container.encodeIfPresent(cropRect, forKey: .cropRect)
        try container.encode(annotations, forKey: .annotations)
        try container.encode(annotationRotations, forKey: .annotationRotations)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    public func rotation(for annotationID: UUID) -> Double {
        annotationRotations[annotationID] ?? 0
    }

    public mutating func setRotation(_ radians: Double, for annotationID: UUID) {
        let normalized = atan2(sin(radians), cos(radians))
        if abs(normalized) < 0.000_001 {
            annotationRotations.removeValue(forKey: annotationID)
        } else {
            annotationRotations[annotationID] = normalized
        }
    }

    public mutating func removeRotation(for annotationID: UUID) {
        annotationRotations.removeValue(forKey: annotationID)
    }

    public var fullCanvasRect: AnnotationRect {
        AnnotationRect(
            x: 0,
            y: 0,
            width: Double(max(1, canvasWidth)),
            height: Double(max(1, canvasHeight))
        )
    }

    public var visibleRect: AnnotationRect {
        guard let cropRect else {
            return fullCanvasRect
        }
        let intersection = cropRect.normalized.intersection(fullCanvasRect)
        guard intersection.width >= 1, intersection.height >= 1 else {
            return fullCanvasRect
        }
        return intersection
    }
}
