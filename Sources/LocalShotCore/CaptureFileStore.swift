import Foundation

public struct CaptureFileStore: Sendable {
    public let capturesDirectory: URL

    public init(capturesDirectory: URL? = nil) throws {
        if let capturesDirectory {
            self.capturesDirectory = capturesDirectory
        } else {
            let applicationSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.capturesDirectory = applicationSupport
                .appendingPathComponent("LocalShot", isDirectory: true)
                .appendingPathComponent("Captures", isDirectory: true)
        }

        try FileManager.default.createDirectory(
            at: self.capturesDirectory,
            withIntermediateDirectories: true
        )
    }

    public func nextCaptureURL(
        mode: CaptureMode,
        date: Date = Date(),
        format: CaptureOutputFormat = .png,
        filenamePrefix: String = "LocalShot",
        timeZone: TimeZone = .current
    ) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let timestamp = formatter.string(from: date)
        let prefix = Self.sanitizedFilenamePrefix(filenamePrefix)
        return capturesDirectory
            .appendingPathComponent("\(prefix)-\(timestamp)-\(mode.fileComponent)")
            .appendingPathExtension(format.fileExtension)
    }

    public func recentCaptures(limit: Int? = 20) throws -> [CaptureAsset] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: capturesDirectory,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        let captures = try urls
            .filter(isManagedCaptureURL)
            .map { url in
                let values = try url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                let date = values.contentModificationDate ?? values.creationDate ?? .distantPast
                return CaptureAsset(
                    url: url,
                    createdAt: date,
                    mode: Self.inferMode(from: url)
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
        guard let limit else {
            return captures
        }
        return Array(captures.prefix(max(0, limit)))
    }

    public func delete(_ asset: CaptureAsset) throws {
        guard isManagedCaptureURL(asset.url) else {
            return
        }
        try removeCaptureAndProject(at: asset.url)
    }

    @discardableResult
    public func removeCaptures(olderThan cutoffDate: Date) throws -> Int {
        let urls = try FileManager.default.contentsOfDirectory(
            at: capturesDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        )

        var removedCount = 0
        for url in urls where isManagedCaptureURL(url) {
            let values = try url.resourceValues(
                forKeys: [.contentModificationDateKey, .creationDateKey]
            )
            let date = values.contentModificationDate ?? values.creationDate ?? .distantFuture
            guard date < cutoffDate else {
                continue
            }
            try removeCaptureAndProject(at: url)
            removedCount += 1
        }

        for projectURL in urls where isManagedProjectURL(projectURL) {
            guard FileManager.default.fileExists(atPath: projectURL.path),
                  !hasAssociatedCapture(for: projectURL) else {
                continue
            }
            let values = try projectURL.resourceValues(
                forKeys: [.contentModificationDateKey, .creationDateKey]
            )
            let date = values.contentModificationDate ?? values.creationDate ?? .distantFuture
            if date < cutoffDate {
                try FileManager.default.removeItem(at: projectURL)
            }
        }
        return removedCount
    }

    @discardableResult
    public func removeAllCaptures() throws -> Int {
        let urls = try FileManager.default.contentsOfDirectory(
            at: capturesDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let captureURLs = urls.filter {
            isManagedCaptureURL($0)
        }
        for url in captureURLs {
            try removeCaptureAndProject(at: url)
        }
        for projectURL in urls where isManagedProjectURL(projectURL) {
            if FileManager.default.fileExists(atPath: projectURL.path) {
                try FileManager.default.removeItem(at: projectURL)
            }
        }
        return captureURLs.count
    }

    private func removeCaptureAndProject(at captureURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: captureURL.path) {
            try fileManager.removeItem(at: captureURL)
        }

        let projectURL = captureURL
            .deletingPathExtension()
            .appendingPathExtension("localshot.json")
        if fileManager.fileExists(atPath: projectURL.path) {
            try fileManager.removeItem(at: projectURL)
        }
    }

    private func isManagedCaptureURL(_ url: URL) -> Bool {
        let standardizedDirectory = capturesDirectory.standardizedFileURL
        guard url.deletingLastPathComponent().standardizedFileURL == standardizedDirectory,
              Self.supportedImageExtensions.contains(url.pathExtension.lowercased()) else {
            return false
        }

        let components = url.deletingPathExtension().lastPathComponent.split(separator: "-")
        guard components.count >= 5 else {
            return false
        }
        let date = components[components.count - 4]
        let time = components[components.count - 3]
        let milliseconds = components[components.count - 2]
        let mode = components[components.count - 1]
        return date.count == 8 && Self.isASCIIDigits(date)
            && time.count == 6 && Self.isASCIIDigits(time)
            && milliseconds.count == 3 && Self.isASCIIDigits(milliseconds)
            && ["area", "window", "screen", "scrolling"].contains(mode)
    }

    private func isManagedProjectURL(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "json" else {
            return false
        }
        let projectBaseURL = url.deletingPathExtension()
        guard projectBaseURL.pathExtension.lowercased() == "localshot" else {
            return false
        }
        return isManagedCaptureURL(
            projectBaseURL.deletingPathExtension().appendingPathExtension("png")
        )
    }

    private func hasAssociatedCapture(for projectURL: URL) -> Bool {
        let baseURL = projectURL.deletingPathExtension().deletingPathExtension()
        return Self.supportedImageExtensions.contains { fileExtension in
            FileManager.default.fileExists(
                atPath: baseURL.appendingPathExtension(fileExtension).path
            )
        }
    }

    private static func isASCIIDigits(_ value: Substring) -> Bool {
        value.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func inferMode(from url: URL) -> CaptureMode {
        let name = url.deletingPathExtension().lastPathComponent
        if name.hasSuffix("-window") {
            return .window
        }
        if name.hasSuffix("-screen") {
            return .fullScreen
        }
        if name.hasSuffix("-scrolling") {
            return .scrolling
        }
        return .area
    }

    private static let supportedImageExtensions: Set<String> = ["png", "jpg", "jpeg"]

    private static func sanitizedFilenamePrefix(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return sanitized.isEmpty ? "LocalShot" : sanitized
    }
}
