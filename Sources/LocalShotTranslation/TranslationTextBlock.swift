import Foundation
import LocalShotVision

public struct TranslationTextBlock: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var sourceText: String
    public var targetText: String
    public var boundingBox: OCRBoundingBox

    public init(
        id: UUID = UUID(),
        sourceText: String,
        targetText: String,
        boundingBox: OCRBoundingBox
    ) {
        self.id = id
        self.sourceText = sourceText
        self.targetText = targetText
        self.boundingBox = boundingBox
    }
}
