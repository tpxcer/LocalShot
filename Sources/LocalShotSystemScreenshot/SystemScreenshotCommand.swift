import Foundation
import LocalShotCore

public enum SystemScreenshotCommand {
    public static let executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")

    public static func arguments(
        for mode: CaptureMode,
        outputURL: URL,
        format: CaptureOutputFormat = .png,
        showsCursor: Bool = false,
        includesWindowShadow: Bool = true
    ) -> [String] {
        var common = ["-x", "-t\(format.screenshotCommandComponent)"]
        if showsCursor {
            common.append("-C")
        }
        switch mode {
        case .area:
            return ["-i", "-s"] + common + [outputURL.path]
        case .window:
            let windowOptions = includesWindowShadow ? ["-i", "-W"] : ["-i", "-W", "-o"]
            return windowOptions + common + [outputURL.path]
        case .fullScreen:
            return ["-m"] + common + [outputURL.path]
        case .scrolling:
            return ["-i", "-s"] + common + [outputURL.path]
        }
    }
}
