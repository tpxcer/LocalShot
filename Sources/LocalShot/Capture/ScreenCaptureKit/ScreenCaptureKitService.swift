import AppKit
import CoreGraphics
import LocalShotCore
import ScreenCaptureKit

enum ScreenCaptureKitServiceError: LocalizedError {
    case displayUnavailable
    case displayPreviewUnavailable
    case windowUnavailable

    var errorDescription: String? {
        switch self {
        case .displayUnavailable:
            "无法找到目标显示器。"
        case .displayPreviewUnavailable:
            "无法冻结全部显示器画面。"
        case .windowUnavailable:
            "目标窗口已关闭或不可捕获。"
        }
    }
}

@available(macOS 14.0, *)
final class ScreenCaptureKitService: @unchecked Sendable {
    func availableWindows() async throws -> [WindowCaptureCandidate] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            true,
            onScreenWindowsOnly: true
        )
        let bundleIdentifier = Bundle.main.bundleIdentifier

        let candidates: [WindowCaptureCandidate] = content.windows.compactMap { window in
            guard window.isOnScreen,
                  window.windowLayer == 0,
                  window.frame.width >= 80,
                  window.frame.height >= 40,
                  let application = window.owningApplication,
                  application.processID != ProcessInfo.processInfo.processIdentifier,
                  application.bundleIdentifier != bundleIdentifier else {
                return nil
            }
            return WindowCaptureCandidate(
                id: window.windowID,
                frame: window.frame,
                processID: application.processID,
                applicationName: application.applicationName,
                title: window.title ?? ""
            )
        }
        let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []
        let zOrderByWindowID = Dictionary(uniqueKeysWithValues: windowInfo.enumerated().compactMap {
            index, info in
            (info[kCGWindowNumber as String] as? NSNumber).map {
                ($0.uint32Value, index)
            }
        })
        return WindowCaptureOrdering.frontToBack(
            candidates,
            zOrderByWindowID: zOrderByWindowID
        )
    }

    func capture(
        displayID: CGDirectDisplayID,
        scaleFactor: CGFloat,
        sourceRect: CGRect?,
        outputURL: URL,
        showsCursor: Bool = false,
        outputFormat: CaptureOutputFormat = .png,
        jpegQuality: Double = 0.9
    ) async throws -> URL {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenCaptureKitServiceError.displayUnavailable
        }

        let bundleIdentifier = Bundle.main.bundleIdentifier
        let excludedWindows = content.windows.filter {
            $0.owningApplication?.bundleIdentifier == bundleIdentifier
        }
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = showsCursor
        configuration.width = max(1, Int((CGFloat(display.width) * scaleFactor).rounded()))
        configuration.height = max(1, Int((CGFloat(display.height) * scaleFactor).rounded()))

        if let sourceRect {
            configuration.sourceRect = sourceRect
            configuration.width = max(1, Int((sourceRect.width * scaleFactor).rounded()))
            configuration.height = max(1, Int((sourceRect.height * scaleFactor).rounded()))
        }

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        try CaptureImageWriter.write(
            image,
            to: outputURL,
            format: outputFormat,
            jpegQuality: jpegQuality
        )
        return outputURL
    }

    func captureDisplayPreviews(
        scalesByDisplayID: [CGDirectDisplayID: CGFloat],
        showsCursor: Bool = false
    ) async throws -> [CGDirectDisplayID: CGImage] {
        guard !scalesByDisplayID.isEmpty else {
            throw ScreenCaptureKitServiceError.displayPreviewUnavailable
        }
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        let bundleIdentifier = Bundle.main.bundleIdentifier
        let excludedWindows = content.windows.filter {
            $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
                || $0.owningApplication?.bundleIdentifier == bundleIdentifier
        }
        var previews: [CGDirectDisplayID: CGImage] = [:]

        for display in content.displays {
            guard let scaleFactor = scalesByDisplayID[display.displayID] else {
                continue
            }
            let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
            let configuration = SCStreamConfiguration()
            configuration.showsCursor = showsCursor
            configuration.width = max(1, Int((CGFloat(display.width) * scaleFactor).rounded()))
            configuration.height = max(1, Int((CGFloat(display.height) * scaleFactor).rounded()))
            configuration.captureResolution = .best
            previews[display.displayID] = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        }
        guard Set(previews.keys) == Set(scalesByDisplayID.keys) else {
            throw ScreenCaptureKitServiceError.displayPreviewUnavailable
        }
        return previews
    }

    func capture(
        windowID: CGWindowID,
        outputURL: URL,
        includesShadow: Bool = true,
        showsCursor: Bool = false,
        outputFormat: CaptureOutputFormat = .png,
        jpegQuality: Double = 0.9
    ) async throws -> URL {
        let content = try await SCShareableContent.excludingDesktopWindows(
            true,
            onScreenWindowsOnly: true
        )
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw ScreenCaptureKitServiceError.windowUnavailable
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        configuration.width = max(1, Int((filter.contentRect.width * scale).rounded()))
        configuration.height = max(1, Int((filter.contentRect.height * scale).rounded()))
        configuration.showsCursor = showsCursor
        configuration.captureResolution = .best
        configuration.ignoreShadowsSingleWindow = !includesShadow
        configuration.ignoreGlobalClipSingleWindow = true

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        try CaptureImageWriter.write(
            image,
            to: outputURL,
            format: outputFormat,
            jpegQuality: jpegQuality
        )
        return outputURL
    }

}
