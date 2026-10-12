import Foundation

public struct OCRBoundingBox: Codable, Hashable, Sendable {
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
}

public struct OCRTextBlock: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var text: String
    public var confidence: Float
    public var boundingBox: OCRBoundingBox

    public init(
        id: UUID = UUID(),
        text: String,
        confidence: Float,
        boundingBox: OCRBoundingBox
    ) {
        self.id = id
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}
