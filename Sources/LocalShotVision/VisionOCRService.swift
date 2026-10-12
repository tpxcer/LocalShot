import Foundation
import Vision

public enum VisionOCRServiceError: LocalizedError {
    case noRecognizedText

    public var errorDescription: String? {
        switch self {
        case .noRecognizedText:
            "没有识别到文字。"
        }
    }
}

public struct VisionOCRService: Sendable {
    public init() {}

    public func recognizeText(
        in imageURL: URL,
        recognitionLanguages: [String] = []
    ) async throws -> [OCRTextBlock] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = recognitionLanguages.isEmpty
            if !recognitionLanguages.isEmpty {
                request.recognitionLanguages = recognitionLanguages
            }

            let handler = VNImageRequestHandler(url: imageURL, options: [:])
            try handler.perform([request])

            let blocks = (request.results ?? []).compactMap { observation -> OCRTextBlock? in
                guard let candidate = observation.topCandidates(1).first else {
                    return nil
                }
                let box = observation.boundingBox
                return OCRTextBlock(
                    text: candidate.string,
                    confidence: candidate.confidence,
                    boundingBox: OCRBoundingBox(
                        x: box.minX,
                        y: box.minY,
                        width: box.width,
                        height: box.height
                    )
                )
            }
            .sorted { first, second in
                if abs(first.boundingBox.y - second.boundingBox.y) > 0.02 {
                    return first.boundingBox.y > second.boundingBox.y
                }
                return first.boundingBox.x < second.boundingBox.x
            }

            guard !blocks.isEmpty else {
                throw VisionOCRServiceError.noRecognizedText
            }
            return blocks
        }.value
    }
}
