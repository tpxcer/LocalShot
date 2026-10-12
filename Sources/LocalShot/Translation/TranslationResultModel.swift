import AppKit
import LocalShotCore
import LocalShotTranslation
import LocalShotVision
@preconcurrency import Translation
import UniformTypeIdentifiers

@available(macOS 15.0, *)
@MainActor
final class TranslationResultModel: ObservableObject {
    @Published private(set) var ocrBlocks: [OCRTextBlock] = []
    @Published private(set) var translatedBlocks: [TranslationTextBlock] = []
    @Published private(set) var isRecognizing = true
    @Published private(set) var isTranslating = false
    @Published var errorMessage: String?
    @Published var showsTranslation = true
    @Published var targetLanguageIdentifier = "zh-Hans" {
        didSet {
            requestTranslation()
        }
    }
    @Published var configuration: TranslationSession.Configuration?

    let asset: CaptureAsset
    private var recognitionTask: Task<Void, Never>?

    init(asset: CaptureAsset) {
        self.asset = asset
        recognize()
    }

    var combinedSourceText: String {
        ocrBlocks.map(\.text).joined(separator: "\n")
    }

    var combinedTargetText: String {
        translatedBlocks.map(\.targetText).joined(separator: "\n")
    }

    func recognize() {
        recognitionTask?.cancel()
        isRecognizing = true
        errorMessage = nil
        translatedBlocks = []
        configuration = nil

        let imageURL = asset.url
        recognitionTask = Task { [weak self] in
            do {
                let recognizedBlocks = try await VisionOCRService().recognizeText(in: imageURL)
                try Task.checkCancellation()
                guard let self else {
                    return
                }
                ocrBlocks = recognizedBlocks
                isRecognizing = false
                recognitionTask = nil
                requestTranslation()
            } catch is CancellationError {
                guard let self else {
                    return
                }
                isRecognizing = false
                recognitionTask = nil
            } catch {
                guard let self else {
                    return
                }
                ocrBlocks = []
                isRecognizing = false
                errorMessage = error.localizedDescription
                recognitionTask = nil
            }
        }
    }

    deinit {
        recognitionTask?.cancel()
    }

    func beginTranslation() {
        isTranslating = true
        errorMessage = nil
    }

    func completeTranslation(_ blocks: [TranslationTextBlock]) {
        translatedBlocks = blocks
        isTranslating = false
    }

    func failTranslation(_ message: String) {
        translatedBlocks = []
        isTranslating = false
        errorMessage = message
    }

    func copyTargetText() {
        copy(combinedTargetText)
    }

    func copySourceText() {
        copy(combinedSourceText)
    }

    func copy(_ text: String) {
        guard !text.isEmpty else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func exportAs() {
        guard !translatedBlocks.isEmpty else {
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = asset.url
            .deletingPathExtension()
            .lastPathComponent + "-translated.png"
        panel.canCreateDirectories = true

        panel.begin { [weak self] response in
            guard let self, response == .OK, let outputURL = panel.url else {
                return
            }
            do {
                try LocalFileExporter.exportGeneratedFile(to: outputURL) { temporaryURL in
                    try TranslationOverlayRenderer.render(
                        baseImageURL: self.asset.url,
                        blocks: self.translatedBlocks,
                        outputURL: temporaryURL
                    )
                }
            } catch {
                Task { @MainActor in
                    self.errorMessage = "导出翻译图片失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func requestTranslation() {
        guard !ocrBlocks.isEmpty else {
            return
        }
        translatedBlocks = []
        configuration = TranslationSession.Configuration(
            source: nil,
            target: Locale.Language(identifier: targetLanguageIdentifier)
        )
    }
}
