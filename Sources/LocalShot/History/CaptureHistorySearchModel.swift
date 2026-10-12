import Foundation
import LocalShotCore
import LocalShotHistoryIndex

@MainActor
final class CaptureHistorySearchModel: ObservableObject {
    @Published private(set) var textByPath: [String: String] = [:]
    @Published private(set) var isIndexing = false
    @Published private(set) var statusMessage = "文字索引尚未建立"
    @Published var errorMessage: String?

    private let store: CaptureSearchIndexStore
    private var indexingTask: Task<Void, Never>?
    private var indexingGeneration = 0

    init() {
        let applicationSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = (applicationSupport ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("LocalShot", isDirectory: true)
        store = CaptureSearchIndexStore(
            indexURL: directory.appendingPathComponent("capture-search-index.json")
        )
        loadCachedIndex()
    }

    func recognizedText(for asset: CaptureAsset) -> String {
        textByPath[asset.url.standardizedFileURL.path] ?? ""
    }

    func synchronize(assets: [CaptureAsset]) {
        indexingTask?.cancel()
        indexingGeneration += 1
        let generation = indexingGeneration
        let urls = assets.map(\.url)
        isIndexing = true
        errorMessage = nil
        statusMessage = "正在本地识别 \(urls.count) 张截图…"

        indexingTask = Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let result = try await store.synchronize(imageURLs: urls)
                try Task.checkCancellation()
                guard generation == indexingGeneration else {
                    return
                }
                textByPath = result.textByPath
                statusMessage = "文字索引：新增 \(result.indexedCount)，复用 \(result.reusedCount)，清理 \(result.removedCount)，失败 \(result.failedCount)"
                isIndexing = false
                indexingTask = nil
            } catch is CancellationError {
                guard generation == indexingGeneration else {
                    return
                }
                isIndexing = false
                indexingTask = nil
            } catch {
                guard generation == indexingGeneration else {
                    return
                }
                isIndexing = false
                indexingTask = nil
                errorMessage = "建立文字索引失败：\(error.localizedDescription)"
                statusMessage = "文字索引暂不可用"
            }
        }
    }

    func removeRecord(for asset: CaptureAsset) {
        textByPath[asset.url.standardizedFileURL.path] = nil
        Task {
            try? await store.removeRecord(for: asset.url)
        }
    }

    func cancelIndexing() {
        indexingGeneration += 1
        indexingTask?.cancel()
        indexingTask = nil
        isIndexing = false
        statusMessage = "已停止文字索引"
    }

    private func loadCachedIndex() {
        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let cachedTextByPath = try await store.currentTextByPath()
                guard !isIndexing, textByPath.isEmpty else {
                    return
                }
                textByPath = cachedTextByPath
                if !cachedTextByPath.isEmpty {
                    statusMessage = "已载入 \(cachedTextByPath.count) 条本地文字索引"
                }
            } catch {
                errorMessage = "读取文字索引失败：\(error.localizedDescription)"
            }
        }
    }
}
