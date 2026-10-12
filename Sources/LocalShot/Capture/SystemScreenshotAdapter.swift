import Foundation
import LocalShotCore
import LocalShotSystemScreenshot

enum SystemScreenshotAdapter {
    static func capture(
        mode: CaptureMode,
        outputURL: URL,
        format: CaptureOutputFormat = .png,
        showsCursor: Bool = false,
        includesWindowShadow: Bool = true
    ) async throws -> URL? {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = SystemScreenshotCommand.executableURL
            process.arguments = SystemScreenshotCommand.arguments(
                for: mode,
                outputURL: outputURL,
                format: format,
                showsCursor: showsCursor,
                includesWindowShadow: includesWindowShadow
            )

            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0,
                  FileManager.default.fileExists(atPath: outputURL.path) else {
                try? FileManager.default.removeItem(at: outputURL)
                return nil
            }

            return outputURL
        }.value
    }

}
