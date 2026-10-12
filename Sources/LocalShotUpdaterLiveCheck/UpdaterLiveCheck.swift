import Foundation
import LocalShotUpdater

@main
struct LocalShotUpdaterLiveCheck {
    static func main() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalShotUpdaterLiveCheck-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let service = LocalShotUpdateService()
            let release = try await service.latestRelease()
            let downloadedURL = try await service.download(release, to: directory)
            let digest = try LocalShotUpdateFile.sha256Hex(of: downloadedURL)
            guard digest == release.asset.sha256 else {
                throw LocalShotUpdateError.checksumMismatch
            }
            print(
                "LocalShotUpdaterLiveCheck: PASS - \(release.version.displayName), "
                    + "\(downloadedURL.lastPathComponent), sha256:\(digest)"
            )
        } catch {
            fputs("LocalShotUpdaterLiveCheck: FAIL - \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
