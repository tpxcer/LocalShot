import AppKit
import CoreGraphics
import ImageIO
import LocalShotCore
import LocalShotScrolling
import os

enum ScrollingCaptureError: LocalizedError {
    case targetApplicationUnavailable

    var errorDescription: String? {
        switch self {
        case .targetApplicationUnavailable:
            "目标应用已经退出。"
        }
    }
}

private let scrollingLogger = Logger(subsystem: "com.localshot.prototype", category: "scrolling")

@MainActor
final class ScrollingCaptureController {
    private let progressController = ScrollingCaptureProgressController()
    private let selectionBorderController = ScrollingCaptureSelectionBorderController()
    private var operationTask: Task<Void, Never>?

    var isRunning: Bool {
        operationTask != nil
    }

    @available(macOS 14.0, *)
    func start(
        target: WindowCaptureCandidate,
        outputURL: URL,
        captureCropRect: CGRect? = nil,
        selectionRect: CGRect? = nil,
        maximumSegments: Int = 30,
        onComplete: @escaping (URL) -> Void,
        onCancel: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) {
        cancel()
        if let selectionRect {
            selectionBorderController.show(selectionRect: selectionRect)
        }
        var finishRequested = false
        var isWaitingForOverlap = false
        let progress = progressController.show(
            onFinish: {
                finishRequested = true
            },
            onCancel: { [weak self] in
                self?.cancel()
            }
        )
        let previewComposer = ScrollingCapturePreviewComposer()
        operationTask = Task { [weak self] in
            guard let self else {
                return
            }
            let temporaryDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("LocalShotScrolling-\(UUID().uuidString)", isDirectory: true)
            defer {
                try? FileManager.default.removeItem(at: temporaryDirectory)
                progressController.dismiss()
                selectionBorderController.dismiss()
                operationTask = nil
            }

            do {
                guard let targetApplication = NSRunningApplication(
                    processIdentifier: target.processID
                ) else {
                    throw ScrollingCaptureError.targetApplicationUnavailable
                }
                let activated = targetApplication.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                scrollingLogger.notice(
                    "开始长截图：应用 \(targetApplication.bundleIdentifier ?? "-", privacy: .public)，窗口 \(target.id, privacy: .public)，激活 \(activated, privacy: .public)"
                )

                try FileManager.default.createDirectory(
                    at: temporaryDirectory,
                    withIntermediateDirectories: true
                )
                try await Task.sleep(nanoseconds: 450_000_000)
                try Task.checkCancellation()

                let service = ScreenCaptureKitService()
                _ = try await ScrollingCaptureSession.run(
                    requestedSegmentLimit: maximumSegments,
                    outputURL: outputURL,
                    captureSegment: { index in
                        let startedAt = Date()
                        let slowCaptureNotice = index == 0 ? Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 5_000_000_000)
                            if !Task.isCancelled {
                                progress.status = "仍在等待目标窗口画面。如果系统弹出屏幕录制授权提示，请先允许"
                                scrollingLogger.error("第一段画面超过 5 秒仍未采集完成")
                            }
                        } : nil
                        defer { slowCaptureNotice?.cancel() }
                        let segmentURL: URL
                        let capturedWindowURL: URL
                        if captureCropRect == nil {
                            segmentURL = temporaryDirectory.appendingPathComponent(
                                String(format: "segment-%03d.png", index)
                            )
                            capturedWindowURL = segmentURL
                        } else {
                            capturedWindowURL = temporaryDirectory.appendingPathComponent(
                                String(format: "window-%03d.png", index)
                            )
                            segmentURL = temporaryDirectory.appendingPathComponent(
                                String(format: "segment-%03d.png", index)
                            )
                        }
                        _ = try await service.capture(
                            windowID: target.id,
                            outputURL: capturedWindowURL,
                            includesShadow: false,
                            showsCursor: false,
                            outputFormat: .png
                        )
                        if let captureCropRect {
                            try self.cropCapturedWindow(
                                at: capturedWindowURL,
                                to: segmentURL,
                                cropRect: captureCropRect,
                                windowSize: target.frame.size
                            )
                        }
                        let elapsed = Date().timeIntervalSince(startedAt)
                        if index == 0 {
                            scrollingLogger.notice("第一段画面采集完成，用时 \(elapsed, privacy: .public) 秒")
                        } else {
                            scrollingLogger.debug("采集第 \(index, privacy: .public) 段，用时 \(elapsed, privacy: .public) 秒")
                        }
                        return segmentURL
                    },
                    advance: { _ in
                        if isWaitingForOverlap {
                            // 保留“请往回滚动”的提示，直到重新接上画面
                        } else if targetApplication.isActive {
                            progress.status = "请继续慢慢向下滚动，完成后点击“完成”"
                        } else {
                            progress.status = "请回到目标窗口后继续滚动"
                        }
                        try await Task.sleep(nanoseconds: 200_000_000)
                    },
                    stitch: { segmentURLs, outputURL in
                        progress.status = "正在拼接 \(segmentURLs.count) 段画面…"
                        return try VerticalImageStitcher.stitch(
                            imageURLs: segmentURLs,
                            outputURL: outputURL
                        )
                    },
                    onAcceptedSegment: { segmentURL, transition in
                        if let image = try? previewComposer.append(
                            segmentURL: segmentURL,
                            transition: transition
                        ) {
                            progress.previewImage = NSImage(
                                cgImage: image,
                                size: NSSize(width: image.width, height: image.height)
                            )
                        }
                    },
                    onProgress: { count, transition in
                        isWaitingForOverlap = false
                        progress.pageCount = count
                        if let transition {
                            if transition.topInset > 0, transition.bottomInset > 0 {
                                progress.status = "已识别固定顶部和底部，请继续慢慢向下滚动"
                            } else if transition.topInset > 0 {
                                progress.status = "已识别固定顶部，请继续慢慢向下滚动"
                            } else if transition.bottomInset > 0 {
                                progress.status = "已识别固定底部，请继续慢慢向下滚动"
                            } else {
                                progress.status = "已拼接当前画面，请继续慢慢向下滚动"
                            }
                        } else {
                            progress.status = "请用鼠标或触控板慢慢向下滚动"
                        }
                    },
                    onUnsupportedTransition: {
                        isWaitingForOverlap = true
                        progress.status = "画面变化太大，请稍微往回滚动一点，再慢慢向下"
                        scrollingLogger.notice("相邻画面无法匹配，已跳过该帧")
                    },
                    shouldFinishWhenUnchanged: {
                        if finishRequested {
                            progress.status = "正在完成拼接…"
                        }
                        return finishRequested
                    }
                )
                onComplete(outputURL)
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: outputURL)
                onCancel()
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                scrollingLogger.error("长截图失败：\(error.localizedDescription, privacy: .public)")
                onError(error.localizedDescription)
            }
        }
    }

    func cancel() {
        operationTask?.cancel()
        selectionBorderController.dismiss()
    }

    func showUIAcceptance(previewURL: URL) {
        cancel()
        let model = progressController.show(
            onFinish: { [weak self] in self?.progressController.dismiss() },
            onCancel: { [weak self] in self?.progressController.dismiss() }
        )
        let composer = ScrollingCapturePreviewComposer()
        for _ in 0..<3 {
            if let image = try? composer.append(segmentURL: previewURL, transition: nil) {
                model.previewImage = NSImage(
                    cgImage: image,
                    size: NSSize(width: image.width, height: image.height)
                )
                model.pageCount += 1
            }
        }
        model.pageCount = 3
        model.status = "请用鼠标或触控板慢慢向下滚动，预览会实时拼接并自动缩小"
    }

    private func cropCapturedWindow(
        at sourceURL: URL,
        to outputURL: URL,
        cropRect: CGRect,
        windowSize: CGSize
    ) throws {
        guard windowSize.width > 0,
              windowSize.height > 0,
              let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ScreenCaptureKitServiceError.windowUnavailable
        }
        guard let cropped = ScreenCoordinateConverter.croppedImage(
            image,
            logicalRect: cropRect,
            logicalSize: windowSize
        ) else {
            throw ScreenCaptureKitServiceError.windowUnavailable
        }
        try CaptureImageWriter.write(cropped, to: outputURL, format: .png)
    }
}
