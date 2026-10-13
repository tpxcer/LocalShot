import CryptoKit
import Foundation

public struct LocalShotVersion: Comparable, Equatable, Sendable {
    public let marketingVersion: String
    public let build: Int

    private let components: [Int]

    public init?(marketingVersion: String, build: Int) {
        let parts = marketingVersion.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...4).contains(parts.count),
              build >= 0,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let parsed = parts.map({ Int($0) }).allValues else {
            return nil
        }
        self.marketingVersion = parsed.map(String.init).joined(separator: ".")
        self.build = build
        components = parsed
    }

    public init?(tagName: String) {
        guard tagName.hasPrefix("v"),
              let separator = tagName.range(of: "-build", options: .backwards),
              separator.lowerBound > tagName.index(after: tagName.startIndex),
              separator.upperBound < tagName.endIndex,
              let build = Int(tagName[separator.upperBound...]) else {
            return nil
        }
        self.init(
            marketingVersion: String(tagName[tagName.index(after: tagName.startIndex)..<separator.lowerBound]),
            build: build
        )
    }

    public var displayName: String {
        "\(marketingVersion) (\(build))"
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        let componentCount = max(lhs.components.count, rhs.components.count)
        for index in 0..<componentCount {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return lhs.build < rhs.build
    }
}

public struct LocalShotUpdateAsset: Equatable, Sendable {
    public let name: String
    public let downloadURL: URL
    public let sha256: String
    public let size: Int64
}

public struct LocalShotUpdateRelease: Equatable, Sendable {
    public let tagName: String
    public let name: String
    public let version: LocalShotVersion
    public let asset: LocalShotUpdateAsset
}

public enum LocalShotUpdateArchitecture: String, Equatable, Sendable {
    case arm64
    case x86_64

    public static var current: Self {
        #if arch(arm64)
        .arm64
        #elseif arch(x86_64)
        .x86_64
        #else
        #error("LocalShot 更新器仅支持 arm64 与 x86_64")
        #endif
    }
}

public enum LocalShotUpdateError: LocalizedError, Equatable {
    case invalidResponse
    case noCompatibleRelease
    case downloadFailed
    case checksumMismatch
    case cannotSaveDownload

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "GitHub 返回了无效的更新响应，请稍后重试。"
        case .noCompatibleRelease:
            "没有找到适用于此 Mac 的 LocalShot 安装包。"
        case .downloadFailed:
            "新版安装包下载失败，请检查网络后重试。"
        case .checksumMismatch:
            "新版安装包校验失败，文件不会被打开。"
        case .cannotSaveDownload:
            "无法把新版安装包保存到“下载”文件夹。"
        }
    }
}

public enum LocalShotUpdateCatalog {
    public static let releasesAPIURL = URL(
        string: "https://api.github.com/repos/tpxcer/LocalShot/releases?per_page=20"
    )!

    public static func latestRelease(
        from data: Data,
        architecture: LocalShotUpdateArchitecture = .current
    ) throws -> LocalShotUpdateRelease {
        let decoder = JSONDecoder()
        guard let releases = try? decoder.decode([GitHubRelease].self, from: data) else {
            throw LocalShotUpdateError.invalidResponse
        }
        let candidates = releases.compactMap { validRelease($0, architecture: architecture) }
        guard let latest = candidates.max(by: { $0.version < $1.version }) else {
            throw LocalShotUpdateError.noCompatibleRelease
        }
        return latest
    }

    private static func validRelease(
        _ release: GitHubRelease,
        architecture: LocalShotUpdateArchitecture
    ) -> LocalShotUpdateRelease? {
        guard !release.draft,
              let version = LocalShotVersion(tagName: release.tagName) else {
            return nil
        }
        let validAssets = release.assets.compactMap { asset -> (LocalShotUpdateAsset, Int)? in
            guard asset.name.hasPrefix("LocalShot-"),
                  asset.name.hasSuffix(".dmg"),
                  !asset.name.contains("/"),
                  !asset.name.contains("\\"),
                  let compatibilityPriority = compatibilityPriority(
                    of: asset.name,
                    architecture: architecture
                  ),
                  asset.size > 0,
                  let digest = normalizedDigest(asset.digest),
                  let url = asset.browserDownloadURL,
                  isTrustedDownloadURL(url, tagName: release.tagName, assetName: asset.name) else {
                return nil
            }
            return (
                LocalShotUpdateAsset(
                    name: asset.name,
                    downloadURL: url,
                    sha256: digest,
                    size: asset.size
                ),
                compatibilityPriority
            )
        }
        guard let highestPriority = validAssets.map(\.1).max() else {
            return nil
        }
        let preferredAssets = validAssets.filter { $0.1 == highestPriority }
        guard preferredAssets.count == 1, let asset = preferredAssets.first?.0 else {
            return nil
        }
        return LocalShotUpdateRelease(
            tagName: release.tagName,
            name: release.name ?? release.tagName,
            version: version,
            asset: asset
        )
    }

    private static func compatibilityPriority(
        of assetName: String,
        architecture: LocalShotUpdateArchitecture
    ) -> Int? {
        let normalizedName = assetName.lowercased()
        let isUniversal2 = normalizedName.contains("universal2")
            && normalizedName.contains("arm64")
            && normalizedName.contains("x86_64")
        if isUniversal2 {
            return 2
        }
        return normalizedName.contains(architecture.rawValue) ? 1 : nil
    }

    private static func normalizedDigest(_ digest: String?) -> String? {
        guard let digest,
              digest.hasPrefix("sha256:") else {
            return nil
        }
        let value = String(digest.dropFirst("sha256:".count)).lowercased()
        guard value.count == 64, value.allSatisfy(\.isHexDigit) else {
            return nil
        }
        return value
    }

    private static func isTrustedDownloadURL(
        _ url: URL,
        tagName: String,
        assetName: String
    ) -> Bool {
        guard url.scheme == "https", url.host == "github.com" else {
            return false
        }
        let expectedPath = "/tpxcer/LocalShot/releases/download/\(tagName)/\(assetName)"
        return url.path == expectedPath
    }
}

public enum LocalShotUpdateFile {
    public static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func uniqueDestinationURL(
        filename: String,
        directory: URL,
        fileManager: FileManager = .default
    ) -> URL {
        let original = directory.appendingPathComponent(filename, isDirectory: false)
        guard fileManager.fileExists(atPath: original.path) else {
            return original
        }
        let extensionName = original.pathExtension
        let basename = original.deletingPathExtension().lastPathComponent
        for number in 2...999 {
            let candidate = directory
                .appendingPathComponent("\(basename) (\(number))")
                .appendingPathExtension(extensionName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return directory
            .appendingPathComponent("\(basename)-\(UUID().uuidString)")
            .appendingPathExtension(extensionName)
    }
}

public actor LocalShotUpdateService {
    private let session: URLSession
    private let fileManager: FileManager

    public init(session: URLSession? = nil, fileManager: FileManager = .default) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 300
            self.session = URLSession(configuration: configuration)
        }
        self.fileManager = fileManager
    }

    public func latestRelease() async throws -> LocalShotUpdateRelease {
        var request = URLRequest(url: LocalShotUpdateCatalog.releasesAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("LocalShot-UpdateChecker", forHTTPHeaderField: "User-Agent")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LocalShotUpdateError.invalidResponse
        }
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              data.count <= 5_000_000 else {
            throw LocalShotUpdateError.invalidResponse
        }
        return try LocalShotUpdateCatalog.latestRelease(from: data)
    }

    public func download(
        _ release: LocalShotUpdateRelease,
        to directory: URL
    ) async throws -> URL {
        let temporaryURL: URL
        let response: URLResponse
        do {
            (temporaryURL, response) = try await session.download(from: release.asset.downloadURL)
        } catch {
            throw LocalShotUpdateError.downloadFailed
        }
        defer { try? fileManager.removeItem(at: temporaryURL) }
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let attributes = try? fileManager.attributesOfItem(atPath: temporaryURL.path),
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.int64Value == release.asset.size else {
            throw LocalShotUpdateError.downloadFailed
        }
        let digest: String
        do {
            digest = try LocalShotUpdateFile.sha256Hex(of: temporaryURL)
        } catch {
            throw LocalShotUpdateError.downloadFailed
        }
        guard digest == release.asset.sha256 else {
            throw LocalShotUpdateError.checksumMismatch
        }
        let destination = LocalShotUpdateFile.uniqueDestinationURL(
            filename: release.asset.name,
            directory: directory,
            fileManager: fileManager
        )
        do {
            try fileManager.copyItem(at: temporaryURL, to: destination)
        } catch {
            throw LocalShotUpdateError.cannotSaveDownload
        }
        return destination
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let draft: Bool
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case draft
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let size: Int64
    let digest: String?
    let browserDownloadURL: URL?

    enum CodingKeys: String, CodingKey {
        case name
        case size
        case digest
        case browserDownloadURL = "browser_download_url"
    }
}

private extension Array where Element == Int? {
    var allValues: [Int]? {
        guard allSatisfy({ $0 != nil }) else {
            return nil
        }
        return compactMap { $0 }
    }
}
