import Foundation

public struct ScreenRecordingAsset: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let createdAt: Date

    public init(url: URL, createdAt: Date) {
        self.url = url
        self.createdAt = createdAt
    }
}

public struct ScreenRecordingFileStore: Sendable {
    public let recordingsDirectory: URL

    public init(recordingsDirectory: URL) throws {
        self.recordingsDirectory = recordingsDirectory
        try FileManager.default.createDirectory(
            at: recordingsDirectory,
            withIntermediateDirectories: true
        )
    }

    public func nextRecordingURL(
        date: Date = .now,
        filenamePrefix: String = "LocalShot",
        timeZone: TimeZone = .current
    ) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let prefix = filenamePrefix
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return recordingsDirectory
            .appendingPathComponent(
                "\(prefix.isEmpty ? "LocalShot" : prefix)-\(formatter.string(from: date))-recording"
            )
            .appendingPathExtension("mp4")
    }

    public func recentRecordings(limit: Int? = 20) throws -> [ScreenRecordingAsset] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: recordingsDirectory,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        let recordings = try urls
            .filter(isManagedRecordingURL)
            .map { url in
                let values = try url.resourceValues(
                    forKeys: [.creationDateKey, .contentModificationDateKey]
                )
                return ScreenRecordingAsset(
                    url: url,
                    createdAt: values.contentModificationDate
                        ?? values.creationDate
                        ?? .distantPast
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
        guard let limit else {
            return recordings
        }
        return Array(recordings.prefix(max(0, limit)))
    }

    @discardableResult
    public func removeAllRecordings() throws -> Int {
        let urls = try FileManager.default.contentsOfDirectory(
            at: recordingsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let recordingURLs = urls.filter(isManagedRecordingURL)
        for url in recordingURLs {
            try FileManager.default.removeItem(at: url)
        }
        return recordingURLs.count
    }

    private func isManagedRecordingURL(_ url: URL) -> Bool {
        guard url.deletingLastPathComponent().standardizedFileURL
                == recordingsDirectory.standardizedFileURL,
              url.pathExtension.lowercased() == "mp4" else {
            return false
        }

        let components = url.deletingPathExtension().lastPathComponent.split(separator: "-")
        guard components.count >= 5 else {
            return false
        }
        let date = components[components.count - 4]
        let time = components[components.count - 3]
        let milliseconds = components[components.count - 2]
        let kind = components[components.count - 1]
        return date.count == 8 && Self.isASCIIDigits(date)
            && time.count == 6 && Self.isASCIIDigits(time)
            && milliseconds.count == 3 && Self.isASCIIDigits(milliseconds)
            && kind == "recording"
    }

    private static func isASCIIDigits(_ value: Substring) -> Bool {
        value.allSatisfy { $0.isASCII && $0.isNumber }
    }
}
