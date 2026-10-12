import Foundation
import LocalShotHistoryIndex

enum HistoryIndexCheckError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message): message
        }
    }
}

actor RecognitionCounter {
    private(set) var count = 0

    func recognize(_ url: URL) throws -> String {
        count += 1
        if try Data(contentsOf: url).first == 0xFF {
            throw HistoryIndexCheckError.failed("模拟 OCR 失败")
        }
        return "识别内容 \(url.deletingPathExtension().lastPathComponent) \(count)"
    }
}

@main
struct LocalShotHistoryIndexCheck {
    static func main() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalShotHistoryIndexCheck-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let firstURL = directory.appendingPathComponent("first.png")
            let secondURL = directory.appendingPathComponent("second.png")
            try Data([1, 2, 3]).write(to: firstURL)
            try Data([4, 5, 6]).write(to: secondURL)
            let indexURL = directory.appendingPathComponent("search-index.json")
            let counter = RecognitionCounter()
            let recognizer = CaptureTextRecognizer { url in
                try await counter.recognize(url)
            }
            let store = CaptureSearchIndexStore(
                indexURL: indexURL,
                recognizer: recognizer
            )

            let first = try await store.synchronize(imageURLs: [firstURL, secondURL])
            try require(first.indexedCount == 2, "首次索引数量错误")
            try require(first.textByPath[firstURL.path]?.contains("first") == true, "首次索引内容缺失")

            let reused = try await store.synchronize(imageURLs: [firstURL, secondURL])
            try require(reused.indexedCount == 0 && reused.reusedCount == 2, "未复用有效缓存")

            try Data([1, 2, 3, 4, 5]).write(to: firstURL, options: .atomic)
            let updated = try await store.synchronize(imageURLs: [firstURL, secondURL])
            try require(updated.indexedCount == 1 && updated.reusedCount == 1, "文件修改后没有重新索引")

            try Data([0xFF]).write(to: firstURL, options: .atomic)
            let failedUpdate = try await store.synchronize(imageURLs: [firstURL, secondURL])
            try require(failedUpdate.failedCount == 1, "文件变化后的 OCR 失败没有被记录")
            try require(
                failedUpdate.textByPath[firstURL.path] == nil,
                "文件变化且 OCR 失败后仍保留陈旧文字"
            )

            try Data([7, 8, 9]).write(to: firstURL, options: .atomic)
            let recovered = try await store.synchronize(imageURLs: [firstURL, secondURL])
            try require(recovered.indexedCount == 1, "OCR 恢复后没有重新建立索引")

            let pruned = try await store.synchronize(imageURLs: [firstURL])
            try require(pruned.removedCount == 1, "失效记录没有清理")
            try require(pruned.textByPath[secondURL.path] == nil, "已删除记录仍存在")

            let reloadedStore = CaptureSearchIndexStore(
                indexURL: indexURL,
                recognizer: recognizer
            )
            let reloaded = try await reloadedStore.currentTextByPath()
            try require(reloaded[firstURL.path] == pruned.textByPath[firstURL.path], "索引持久化往返失败")

            print("LocalShotHistoryIndexCheck: PASS")
        } catch {
            fputs("LocalShotHistoryIndexCheck: FAIL - \(error)\n", stderr)
            exit(1)
        }
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else {
            throw HistoryIndexCheckError.failed(message)
        }
    }
}
