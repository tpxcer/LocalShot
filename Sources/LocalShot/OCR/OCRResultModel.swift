import AppKit
import LocalShotCore
import LocalShotVision

@MainActor
final class OCRResultModel: ObservableObject {
    @Published private(set) var blocks: [OCRTextBlock] = []
    @Published private(set) var isLoading = true
    @Published var errorMessage: String?

    let asset: CaptureAsset
    private var recognitionTask: Task<Void, Never>?

    init(asset: CaptureAsset) {
        self.asset = asset
        recognize()
    }

    var combinedText: String {
        blocks.map(\.text).joined(separator: "\n")
    }

    func recognize() {
        recognitionTask?.cancel()
        isLoading = true
        errorMessage = nil

        let imageURL = asset.url
        recognitionTask = Task { [weak self] in
            do {
                let recognizedBlocks = try await VisionOCRService().recognizeText(in: imageURL)
                try Task.checkCancellation()
                guard let self else {
                    return
                }
                blocks = recognizedBlocks
                isLoading = false
                recognitionTask = nil
            } catch is CancellationError {
                guard let self else {
                    return
                }
                isLoading = false
                recognitionTask = nil
            } catch {
                guard let self else {
                    return
                }
                blocks = []
                isLoading = false
                errorMessage = error.localizedDescription
                recognitionTask = nil
            }
        }
    }

    deinit {
        recognitionTask?.cancel()
    }

    func copyAll() {
        copy(combinedText)
    }

    func copy(_ text: String) {
        guard !text.isEmpty else {
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
