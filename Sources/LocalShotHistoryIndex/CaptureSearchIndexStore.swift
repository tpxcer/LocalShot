import Foundation
import LocalShotVision

public struct CaptureTextRecognizer: Sendable {
    private let operation: @Sendable (URL) async throws -> String

    public init(operation: @escaping @Sendable (URL) async throws -> String) {
        self.operation = operation
    }

    public func recognize(_ url: URL) async throws -> String {
        try await operation(url)
    }

    public static let vision = CaptureTextRecognizer { url in
        do {
            return try await VisionOCRService()
                .recognizeText(in: url)
                .map(\.text)
                .joined(separator: "\n")
        } catch VisionOCRServiceError.noRecognizedText {
            return ""
        }
    }
}

public struct CaptureSearchRecord: Codable, Hashable, Sendable {
    public let path: String
    public let modifiedAt: TimeInterval
    public let fileSize: Int64
    public let recognizedText: String
    public let indexedAt: Date

    public init(
        path: String,
        modifiedAt: TimeInterval,
        fileSize: Int64,
        recognizedText: String,
        indexedAt: Date = .now
    ) {
        self.path = path
        self.modifiedAt = modifiedAt
        self.fileSize = fileSize
        self.recognizedText = recognizedText
        self.indexedAt = indexedAt
    }
}

public struct CaptureSearchSynchronizationResult: Hashable, Sendable {
    public let indexedCount: Int
    public let reusedCount: Int
    public let removedCount: Int
    public let failedCount: Int
    public let textByPath: [String: String]

    public init(
        indexedCount: Int,
        reusedCount: Int,
        removedCount: Int,
        failedCount: Int,
        textByPath: [String: String]
    ) {
        self.indexedCount = indexedCount
        self.reusedCount = reusedCount
        self.removedCount = removedCount
        self.failedCount = failedCount
        self.textByPath = textByPath
    }
}

public actor CaptureSearchIndexStore {
    private struct StoredIndex: Codable {
        var version: Int
        var records: [CaptureSearchRecord]
    }

    private let indexURL: URL
    private let recognizer: CaptureTextRecognizer
    private var recordsByPath: [String: CaptureSearchRecord] = [:]
    private var hasLoaded = false

    public init(
        indexURL: URL,
        recognizer: CaptureTextRecognizer = .vision
    ) {
        self.indexURL = indexURL
        self.recognizer = recognizer
    }

    public func synchronize(imageURLs: [URL]) async throws -> CaptureSearchSynchronizationResult {
        try loadIfNeeded()
        let standardizedURLs = imageURLs.map(\.standardizedFileURL)
        let validPaths = Set(standardizedURLs.map(\.path))
        let countBeforePruning = recordsByPath.count
        recordsByPath = recordsByPath.filter { validPaths.contains($0.key) }
        let removedCount = countBeforePruning - recordsByPath.count
        var indexedCount = 0
        var reusedCount = 0
        var failedCount = 0

        for url in standardizedURLs {
            try Task.checkCancellation()
            guard let fingerprint = try fileFingerprint(for: url) else {
                continue
            }
            if let record = recordsByPath[url.path],
               record.modifiedAt == fingerprint.modifiedAt,
               record.fileSize == fingerprint.fileSize {
                reusedCount += 1
                continue
            }

            recordsByPath[url.path] = nil
            do {
                let text = try await recognizer.recognize(url)
                recordsByPath[url.path] = CaptureSearchRecord(
                    path: url.path,
                    modifiedAt: fingerprint.modifiedAt,
                    fileSize: fingerprint.fileSize,
                    recognizedText: text
                )
                indexedCount += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failedCount += 1
            }
        }

        try persist()
        return CaptureSearchSynchronizationResult(
            indexedCount: indexedCount,
            reusedCount: reusedCount,
            removedCount: removedCount,
            failedCount: failedCount,
            textByPath: textByPath()
        )
    }

    public func currentTextByPath() throws -> [String: String] {
        try loadIfNeeded()
        return textByPath()
    }

    public func removeRecord(for imageURL: URL) throws {
        try loadIfNeeded()
        recordsByPath[imageURL.standardizedFileURL.path] = nil
        try persist()
    }

    private func loadIfNeeded() throws {
        guard !hasLoaded else {
            return
        }
        hasLoaded = true
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            return
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let stored = try decoder.decode(
                StoredIndex.self,
                from: Data(contentsOf: indexURL)
            )
            guard stored.version == 1 else {
                return
            }
            recordsByPath = Dictionary(
                uniqueKeysWithValues: stored.records.map { ($0.path, $0) }
            )
        } catch {
            recordsByPath = [:]
        }
    }

    private func persist() throws {
        try FileManager.default.createDirectory(
            at: indexURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let stored = StoredIndex(
            version: 1,
            records: recordsByPath.values.sorted { $0.path < $1.path }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(stored).write(to: indexURL, options: .atomic)
    }

    private func textByPath() -> [String: String] {
        Dictionary(uniqueKeysWithValues: recordsByPath.values.map {
            ($0.path, $0.recognizedText)
        })
    }

    private func fileFingerprint(
        for url: URL
    ) throws -> (modifiedAt: TimeInterval, fileSize: Int64)? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let values = try url.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileSizeKey
        ])
        return (
            (values.contentModificationDate ?? .distantPast).timeIntervalSince1970,
            Int64(values.fileSize ?? 0)
        )
    }
}
