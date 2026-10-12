import AppKit
import AVFoundation
import LocalShotCore
import SwiftUI

@available(macOS 15.0, *)
@MainActor
final class ScreenRecordingController: ObservableObject {
    enum State: Equatable {
        case prepared
        case countingDown(Int)
        case starting
        case recording
        case pausing
        case paused
        case resuming
        case stopping
    }

    @Published private(set) var state: State = .prepared
    @Published private(set) var elapsedText = "00:00:00"
    @Published var capturesSystemAudio = true {
        didSet { refreshStorageInformation() }
    }
    @Published private(set) var capturesMicrophone = false {
        didSet { refreshStorageInformation() }
    }
    @Published var recordingQuality: ScreenRecordingQuality = .original {
        didSet {
            refreshStorageInformation()
            onRecordingPreferencesChanged?(recordingQuality, recordingFrameRate)
        }
    }
    @Published var recordingFrameRate: ScreenRecordingFrameRate = .fps60 {
        didSet {
            refreshStorageInformation()
            onRecordingPreferencesChanged?(recordingQuality, recordingFrameRate)
        }
    }
    @Published private(set) var estimatedFileSizeText = "正在估算文件大小…"
    @Published private(set) var availableStorageText = "正在读取可用空间…"

    var onComplete: ((URL) -> Void)?
    var onCancel: (() -> Void)?
    var onError: ((String) -> Void)?
    var onMessage: ((String) -> Void)?
    var onRecordingSessionStateChange: ((Bool) -> Void)?
    var onRecordingPreferencesChanged: ((ScreenRecordingQuality, ScreenRecordingFrameRate) -> Void)?

    private var borderPanel: NSPanel?
    private var controlPanel: NSPanel?
    private var service: ScreenRecordingService?
    private var timer: Timer?
    private var countdownTask: Task<Void, Never>?
    private var borderVisibilityTimer: Timer?
    private var activeSegmentStartedAt: Date?
    private var recordedElapsedInterval: TimeInterval = 0
    private var result: SelectionOverlayController.Result?
    private var outputURL: URL?
    private var recordingSegmentURLs: [URL] = []
    private var recordingOutputSize: CGSize = .zero
    private var missingTargetWindowChecks = 0
    private var isHandlingMissingTargetWindow = false
    private var targetAvailabilityCheckInFlight = false
    private var pendingInterruptionMessage: String?
    private var pendingStopRequested = false
    private var recordingSessionIsActive = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var applicationObservers: [NSObjectProtocol] = []
    private var recordingActivityToken: NSObjectProtocol?
    private var estimatedBytesPerMinute = ScreenRecordingSizeEstimate(
        lowerBytesPerMinute: 0,
        upperBytesPerMinute: 0
    )
    private var lastStorageCheckAt: Date?
    private var hasShownStorageWarning = false
    private var isStoppingForLowStorage = false
    private var storageCapacityOverride: Int64?

    var isRecording: Bool { state == .recording }
    var isPaused: Bool { state == .paused }
    var controlsEnabled: Bool { state == .prepared }
    var isTransitioning: Bool {
        [.starting, .pausing, .resuming, .stopping].contains(state)
    }
    var canTogglePause: Bool { state == .recording || state == .paused }
    var pauseButtonSymbol: String { state == .paused ? "play.fill" : "pause.fill" }
    var pauseButtonLabel: String { state == .paused ? "继续录制" : "暂停录制" }
    var recordingStatusSymbol: String { state == .paused ? "pause.circle.fill" : "record.circle.fill" }
    var recordingStatusLabel: String {
        switch state {
        case .prepared:
            "准备录制"
        case let .countingDown(value):
            "\(value) 秒后开始录制"
        case .starting:
            "正在启动录制"
        case .recording:
            "录制中 \(elapsedText)"
        case .pausing:
            "正在暂停录制"
        case .paused:
            "录制已暂停 \(elapsedText)"
        case .resuming:
            "正在继续录制"
        case .stopping:
            "正在保存录制"
        }
    }
    var primaryButtonTitle: String {
        switch state {
        case .prepared:
            "开始录制"
        case let .countingDown(value):
            "取消 \(value)"
        case .starting:
            "正在启动…"
        case .recording:
            "停止录制"
        case .pausing:
            "正在暂停…"
        case .paused:
            "停止录制"
        case .resuming:
            "正在继续…"
        case .stopping:
            "正在保存…"
        }
    }

    var countdownText: String? {
        guard case let .countingDown(value) = state else { return nil }
        return String(value)
    }

    var recordingModeTitle: String {
        result?.targetWindow == nil ? "固定区域" : "锁定窗口"
    }

    var recordingModeSymbol: String {
        result?.targetWindow == nil ? "viewfinder" : "lock.rectangle"
    }

    var recordingPreferencesTitle: String {
        "\(recordingQuality.shortDisplayName) · \(recordingFrameRate.rawValue)"
    }

    func prepare(
        result: SelectionOverlayController.Result,
        outputURL: URL,
        quality: ScreenRecordingQuality = .original,
        frameRate: ScreenRecordingFrameRate = .fps60
    ) {
        closePanels()
        self.result = result
        self.outputURL = outputURL
        recordingQuality = quality
        recordingFrameRate = frameRate
        state = .prepared
        elapsedText = "00:00:00"
        activeSegmentStartedAt = nil
        recordedElapsedInterval = 0
        recordingSegmentURLs = []
        recordingOutputSize = .zero
        capturesSystemAudio = true
        capturesMicrophone = false
        missingTargetWindowChecks = 0
        isHandlingMissingTargetWindow = false
        targetAvailabilityCheckInFlight = false
        pendingInterruptionMessage = nil
        pendingStopRequested = false
        lastStorageCheckAt = nil
        hasShownStorageWarning = false
        isStoppingForLowStorage = false

        let selectionFrame = result.targetWindow.flatMap(Self.currentAppKitFrame(for:))
            ?? Self.appKitSelectionFrame(for: result)
        showBorder(frame: selectionFrame)
        startBorderVisibilityTimer()
        showControls(selectionFrame: selectionFrame, screen: result.screen)
        startLifecycleMonitoring()
        refreshStorageInformation()
    }

    func toggleMicrophone() {
        guard controlsEnabled else { return }
        guard !capturesMicrophone else {
            capturesMicrophone = false
            return
        }
        Task { [weak self] in
            guard let self else { return }
            if await MicrophonePermission.request() {
                capturesMicrophone = true
            } else {
                onMessage?("麦克风未授权，录制将不包含麦克风声音。")
            }
        }
    }

    func performPrimaryAction() {
        switch state {
        case .prepared:
            beginCountdown()
        case .countingDown:
            cancelCountdown()
        case .recording:
            Task { await finishRecording() }
        case .paused:
            Task { await finishRecording() }
        case .starting, .pausing, .resuming, .stopping:
            break
        }
    }

    func togglePause() {
        switch state {
        case .recording:
            Task { await pauseRecording() }
        case .paused:
            Task { await resumeRecording() }
        case .prepared, .countingDown, .starting, .pausing, .resuming, .stopping:
            break
        }
    }

    func stopFromGlobalHotKey() {
        switch state {
        case .recording, .paused:
            Task { await finishRecording() }
        case .pausing, .resuming:
            pendingStopRequested = true
        case .prepared, .countingDown, .starting, .stopping:
            break
        }
    }

    func simulateLowStorageForAcceptance() {
        guard state == .recording else { return }
        storageCapacityOverride = 0
        lastStorageCheckAt = nil
        checkStorageDuringRecordingIfNeeded()
    }

    func cancel() {
        switch state {
        case .prepared:
            cleanup(deleteOutput: true)
            onCancel?()
            return
        case .countingDown:
            cancelCountdown()
            return
        case .starting, .pausing, .resuming, .stopping:
            return
        case .recording, .paused:
            break
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "取消屏幕录制？"
        alert.informativeText = "当前录制内容将被删除，无法恢复。"
        alert.addButton(withTitle: "取消录制")
        alert.addButton(withTitle: "继续录制")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await cancelRecording() }
    }

    private func beginCountdown() {
        guard state == .prepared else { return }
        countdownTask?.cancel()
        state = .countingDown(3)
        countdownTask = Task { [weak self] in
            for value in [3, 2, 1] {
                guard let self, !Task.isCancelled else { return }
                self.state = .countingDown(value)
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }
            guard let self, !Task.isCancelled else { return }
            self.countdownTask = nil
            await self.startRecording()
        }
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        state = .prepared
        ensureBorderOnTop()
    }

    private func startRecording() async {
        guard let result, let outputURL else { return }
        guard checkStorageBeforeRecording() else {
            state = .prepared
            ensureBorderOnTop()
            return
        }
        state = .starting
        beginRecordingActivity()
        ensureBorderOnTop()
        let service = ScreenRecordingService()
        do {
            try await service.start(
                displayID: result.displayID,
                sourceRect: result.sourceRect,
                scaleFactor: result.screen.backingScaleFactor,
                outputURL: outputURL,
                capturesSystemAudio: capturesSystemAudio,
                capturesMicrophone: capturesMicrophone,
                targetWindowID: result.targetWindow?.id,
                quality: recordingQuality,
                frameRate: recordingFrameRate
            )
            configureFailureHandler(for: service)
            self.service = service
            recordingSegmentURLs = [outputURL]
            recordingOutputSize = service.outputSize
            state = .recording
            activeSegmentStartedAt = .now
            setRecordingSessionActive(true)
            startTimer()
            ensureBorderOnTop()
            if let pendingInterruptionMessage {
                self.pendingInterruptionMessage = nil
                await finishRecording(message: pendingInterruptionMessage)
            } else if pendingStopRequested {
                pendingStopRequested = false
                await finishRecording()
            }
        } catch {
            fail(error)
        }
    }

    private func pauseRecording() async {
        guard state == .recording, let service else { return }
        state = .pausing
        stopTimer()
        accumulateActiveSegmentElapsed()
        service.onFailure = nil
        do {
            try await service.stop()
            self.service = nil
            state = .paused
            updateElapsedText()
            ensureBorderOnTop()
            if let pendingInterruptionMessage {
                self.pendingInterruptionMessage = nil
                await finishRecording(message: pendingInterruptionMessage)
            } else if pendingStopRequested {
                pendingStopRequested = false
                await finishRecording()
            }
        } catch {
            self.service = nil
            if let currentSegment = recordingSegmentURLs.last,
               await Self.isPlayableRecording(at: currentSegment) {
                state = .paused
                updateElapsedText()
                onMessage?("暂停录制时系统返回异常，已保留当前内容；你仍可停止并保存。")
            } else {
                fail(error)
            }
        }
    }

    private func resumeRecording() async {
        guard state == .paused, let result else { return }
        let segmentURL = nextSegmentURL()
        state = .resuming
        ensureBorderOnTop()
        try? FileManager.default.removeItem(at: segmentURL)
        let service = ScreenRecordingService()
        do {
            try await service.start(
                displayID: result.displayID,
                sourceRect: result.sourceRect,
                scaleFactor: result.screen.backingScaleFactor,
                outputURL: segmentURL,
                capturesSystemAudio: capturesSystemAudio,
                capturesMicrophone: capturesMicrophone,
                targetWindowID: result.targetWindow?.id,
                fixedOutputSize: recordingOutputSize == .zero ? nil : recordingOutputSize,
                quality: recordingQuality,
                frameRate: recordingFrameRate
            )
            configureFailureHandler(for: service)
            self.service = service
            recordingSegmentURLs.append(segmentURL)
            state = .recording
            activeSegmentStartedAt = .now
            startTimer()
            ensureBorderOnTop()
            if let pendingInterruptionMessage {
                self.pendingInterruptionMessage = nil
                await finishRecording(message: pendingInterruptionMessage)
            } else if pendingStopRequested {
                pendingStopRequested = false
                await finishRecording()
            }
        } catch {
            try? FileManager.default.removeItem(at: segmentURL)
            self.service = nil
            state = .paused
            updateElapsedText()
            onMessage?("继续录制失败：\(error.localizedDescription) 已录制内容仍可停止并保存。")
        }
    }

    private func finishRecording(message: String? = nil) async {
        guard state != .stopping,
              let outputURL,
              !recordingSegmentURLs.isEmpty else { return }
        state = .stopping
        stopTimer()
        accumulateActiveSegmentElapsed()
        if let service {
            service.onFailure = nil
            self.service = nil
            do {
                try await service.stop()
            } catch {
                guard let currentSegment = recordingSegmentURLs.last,
                      await Self.isPlayableRecording(at: currentSegment) else {
                    failPreservingSegments(error)
                    return
                }
            }
        }

        do {
            try await ScreenRecordingSegmentMerger.merge(
                segmentURLs: recordingSegmentURLs,
                outputURL: outputURL
            )
            guard await Self.isPlayableRecording(at: outputURL) else {
                throw ScreenRecordingSegmentMergerError.videoTrackUnavailable
            }
        } catch {
            failPreservingSegments(error)
            return
        }

        cleanup(deleteOutput: false)
        if let message {
            onMessage?(message)
        }
        onComplete?(outputURL)
    }

    private func cancelRecording() async {
        state = .stopping
        stopTimer()
        do {
            try await service?.stop()
        } catch {
            // 取消时仍继续清理不完整文件。
        }
        cleanup(deleteOutput: true)
        onCancel?()
    }

    private func fail(_ error: Error) {
        guard result != nil else { return }
        cleanup(deleteOutput: true)
        onError?(error.localizedDescription)
    }

    private func failPreservingSegments(_ error: Error) {
        guard result != nil else { return }
        cleanup(deleteOutput: false)
        onError?("\(error.localizedDescription) 已录制的 MP4 分段仍保留在截图目录。")
    }

    private func configureFailureHandler(for service: ScreenRecordingService) {
        service.onFailure = { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if self.state == .recording,
                   let targetWindow = self.result?.targetWindow,
                   Self.currentAppKitFrame(for: targetWindow) == nil {
                    self.handleMissingTargetWindow()
                } else {
                    self.fail(error)
                }
            }
        }
    }

    private func nextSegmentURL() -> URL {
        guard let outputURL else {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("LocalShot-recording-part.mp4")
        }
        let partNumber = recordingSegmentURLs.count + 1
        return outputURL.deletingLastPathComponent()
            .appendingPathComponent(
                "\(outputURL.deletingPathExtension().lastPathComponent)-part-\(partNumber)"
            )
            .appendingPathExtension("mp4")
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateElapsedText()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateElapsedText() {
        let activeInterval = activeSegmentStartedAt.map {
            Date().timeIntervalSince($0)
        } ?? 0
        let seconds = max(0, Int(recordedElapsedInterval + activeInterval))
        elapsedText = String(
            format: "%02d:%02d:%02d",
            seconds / 3_600,
            (seconds % 3_600) / 60,
            seconds % 60
        )
        checkStorageDuringRecordingIfNeeded()
    }

    private func accumulateActiveSegmentElapsed() {
        if let activeSegmentStartedAt {
            recordedElapsedInterval += max(0, Date().timeIntervalSince(activeSegmentStartedAt))
        }
        activeSegmentStartedAt = nil
        updateElapsedText()
    }

    private func refreshStorageInformation() {
        if let result {
            let sourcePixelSize = CGSize(
                width: result.sourceRect.width * result.screen.backingScaleFactor,
                height: result.sourceRect.height * result.screen.backingScaleFactor
            )
            let outputPixelSize = recordingQuality.outputSize(for: sourcePixelSize)
            estimatedBytesPerMinute = ScreenRecordingSizeEstimator.estimatePerMinute(
                pixelSize: outputPixelSize,
                frameRate: recordingFrameRate,
                capturesAudio: capturesSystemAudio || capturesMicrophone
            )
            estimatedFileSizeText = "预计每分钟 \(Self.byteText(estimatedBytesPerMinute.lowerBytesPerMinute))–\(Self.byteText(estimatedBytesPerMinute.upperBytesPerMinute))"
        }

        if let availableBytes = availableStorageCapacity() {
            availableStorageText = "磁盘可用 \(Self.byteText(availableBytes))"
        } else {
            availableStorageText = "无法读取磁盘可用空间"
        }
    }

    private func checkStorageBeforeRecording() -> Bool {
        refreshStorageInformation()
        guard let availableBytes = availableStorageCapacity() else { return true }
        if availableBytes <= storageHardStopThreshold {
            onMessage?("磁盘可用空间只有 \(Self.byteText(availableBytes))，低于安全录制空间 \(Self.byteText(storageHardStopThreshold))。请清理空间后重试。")
            return false
        }
        if availableBytes <= storageWarningThreshold, !hasShownStorageWarning {
            hasShownStorageWarning = true
            onMessage?("磁盘可用空间为 \(Self.byteText(availableBytes))。LocalShot 会在低于 \(Self.byteText(storageHardStopThreshold)) 时自动停止并保存。")
        }
        return true
    }

    private func checkStorageDuringRecordingIfNeeded() {
        guard state == .recording, !isStoppingForLowStorage else { return }
        let now = Date()
        if let lastStorageCheckAt,
           now.timeIntervalSince(lastStorageCheckAt) < 5 {
            return
        }
        self.lastStorageCheckAt = now
        refreshStorageInformation()
        guard let availableBytes = availableStorageCapacity() else { return }
        if availableBytes <= storageHardStopThreshold {
            isStoppingForLowStorage = true
            Task {
                await finishRecording(
                    message: "磁盘空间不足，录制已自动停止并保存。"
                )
            }
        } else if availableBytes <= storageWarningThreshold,
                  !hasShownStorageWarning {
            hasShownStorageWarning = true
            onMessage?("磁盘空间偏低，剩余 \(Self.byteText(availableBytes))；达到安全线时将自动停止并保存。")
        }
    }

    private func availableStorageCapacity() -> Int64? {
        if let storageCapacityOverride {
            return storageCapacityOverride
        }
        guard let directoryURL = outputURL?.deletingLastPathComponent(),
              let values = try? directoryURL.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey]
              ) else {
            return nil
        }
        return values.volumeAvailableCapacityForImportantUsage
    }

    private var storageHardStopThreshold: Int64 {
        max(512 * 1_024 * 1_024, estimatedBytesPerMinute.upperBytesPerMinute * 2)
    }

    private var storageWarningThreshold: Int64 {
        max(1_024 * 1_024 * 1_024, estimatedBytesPerMinute.upperBytesPerMinute * 5)
    }

    private static func byteText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func cleanup(deleteOutput: Bool) {
        countdownTask?.cancel()
        countdownTask = nil
        stopTimer()
        stopBorderVisibilityTimer()
        stopLifecycleMonitoring()
        endRecordingActivity()
        setRecordingSessionActive(false)
        borderPanel?.close()
        controlPanel?.close()
        borderPanel = nil
        controlPanel = nil
        service = nil
        result = nil
        missingTargetWindowChecks = 0
        isHandlingMissingTargetWindow = false
        targetAvailabilityCheckInFlight = false
        pendingInterruptionMessage = nil
        pendingStopRequested = false
        lastStorageCheckAt = nil
        hasShownStorageWarning = false
        isStoppingForLowStorage = false
        storageCapacityOverride = nil
        if deleteOutput {
            var urls = recordingSegmentURLs
            if let outputURL, !urls.contains(outputURL) {
                urls.append(outputURL)
            }
            for url in urls {
                try? FileManager.default.removeItem(at: url)
            }
        }
        activeSegmentStartedAt = nil
        recordedElapsedInterval = 0
        recordingSegmentURLs = []
        recordingOutputSize = .zero
        self.outputURL = nil
        state = .prepared
        elapsedText = "00:00:00"
    }

    private func closePanels() {
        stopBorderVisibilityTimer()
        stopLifecycleMonitoring()
        endRecordingActivity()
        setRecordingSessionActive(false)
        borderPanel?.close()
        controlPanel?.close()
        borderPanel = nil
        controlPanel = nil
    }

    private func setRecordingSessionActive(_ isActive: Bool) {
        guard recordingSessionIsActive != isActive else { return }
        recordingSessionIsActive = isActive
        onRecordingSessionStateChange?(isActive)
    }

    private func showBorder(frame: CGRect) {
        let panel = ScreenRecordingBorderPanel(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = Self.recordingOverlayLevel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.sharingType = .none
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.setAccessibilityElement(false)
        panel.contentView = NSHostingView(rootView: ScreenRecordingBorderView(controller: self))
        panel.orderFrontRegardless()
        borderPanel = panel
    }

    private func showControls(selectionFrame: CGRect, screen: NSScreen) {
        let panel = NSPanel(
            contentRect: Self.controlPanelFrame(
                selectionFrame: selectionFrame,
                screen: screen
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = Self.recordingOverlayLevel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.sharingType = .none
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.contentView = NSHostingView(rootView: ScreenRecordingControlView(controller: self))
        panel.orderFrontRegardless()
        controlPanel = panel
    }

    private static func appKitSelectionFrame(
        for result: SelectionOverlayController.Result
    ) -> CGRect {
        CGRect(
            x: result.screen.frame.minX + result.sourceRect.minX,
            y: result.screen.frame.minY + result.screen.frame.height - result.sourceRect.maxY,
            width: result.sourceRect.width,
            height: result.sourceRect.height
        )
    }

    private func startBorderVisibilityTimer() {
        stopBorderVisibilityTimer()
        let interval = result?.targetWindow == nil ? 0.5 : 0.05
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshRecordingOverlay()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        borderVisibilityTimer = timer
    }

    private func stopBorderVisibilityTimer() {
        borderVisibilityTimer?.invalidate()
        borderVisibilityTimer = nil
    }

    private func ensureBorderOnTop() {
        guard result != nil else { return }
        borderPanel?.orderFrontRegardless()
    }

    private func refreshRecordingOverlay() {
        guard let result else { return }
        if let targetWindow = result.targetWindow {
            if let frame = Self.currentAppKitFrame(for: targetWindow) {
                missingTargetWindowChecks = 0
                updateOverlayFrames(selectionFrame: frame, fallbackScreen: result.screen)
            } else {
                missingTargetWindowChecks += 1
                verifyTargetWindowAvailability(targetWindow)
            }
        }
        ensureBorderOnTop()
    }

    private func verifyTargetWindowAvailability(_ targetWindow: WindowCaptureCandidate) {
        guard !targetAvailabilityCheckInFlight else { return }
        targetAvailabilityCheckInFlight = true
        Task { [weak self] in
            do {
                let screenCaptureKitFrame = try await ScreenRecordingService.windowFrame(
                    windowID: targetWindow.id,
                    processID: targetWindow.processID
                )
                guard let self else { return }
                self.targetAvailabilityCheckInFlight = false
                guard self.result?.targetWindow?.id == targetWindow.id else { return }
                if let screenCaptureKitFrame,
                   screenCaptureKitFrame.width >= 4,
                   screenCaptureKitFrame.height >= 4,
                   let fallbackScreen = self.result?.screen
                    ?? NSScreen.main
                    ?? NSScreen.screens.first {
                    self.missingTargetWindowChecks = 0
                    self.updateOverlayFrames(
                        selectionFrame: Self.appKitFrame(
                            fromScreenCaptureKitFrame: screenCaptureKitFrame
                        ),
                        fallbackScreen: fallbackScreen
                    )
                } else {
                    self.handleMissingTargetWindow()
                }
            } catch {
                self?.targetAvailabilityCheckInFlight = false
            }
        }
    }

    private func updateOverlayFrames(selectionFrame: CGRect, fallbackScreen: NSScreen) {
        if borderPanel?.frame != selectionFrame {
            borderPanel?.setFrame(selectionFrame, display: true)
        }
        let screen = Self.screen(containingMostOf: selectionFrame) ?? fallbackScreen
        let controlFrame = Self.controlPanelFrame(
            selectionFrame: selectionFrame,
            screen: screen
        )
        if controlPanel?.frame != controlFrame {
            controlPanel?.setFrame(controlFrame, display: true)
        }
    }

    private func handleMissingTargetWindow() {
        guard !isHandlingMissingTargetWindow else { return }
        switch state {
        case .prepared:
            isHandlingMissingTargetWindow = true
            cleanup(deleteOutput: true)
            onCancel?()
            onMessage?("锁定的窗口已关闭，录制已取消。")
        case .countingDown:
            isHandlingMissingTargetWindow = true
            cleanup(deleteOutput: true)
            onCancel?()
            onMessage?("锁定的窗口已关闭，录制倒计时已取消。")
        case .recording, .paused:
            isHandlingMissingTargetWindow = true
            onMessage?("锁定的窗口已关闭，正在停止并保存录制。")
            Task { await finishRecordingAfterTargetClosed() }
        case .starting, .pausing, .resuming:
            isHandlingMissingTargetWindow = true
            pendingInterruptionMessage = "锁定的窗口已关闭，录制已自动停止并保存。"
        case .stopping:
            break
        }
    }

    private func finishRecordingAfterTargetClosed() async {
        await finishRecording(message: "锁定的窗口已关闭，录制已自动停止并保存。")
    }

    private static func isPlayableRecording(at url: URL) async -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              (values.fileSize ?? 0) > 0 else {
            return false
        }
        let asset = AVURLAsset(url: url)
        guard let isPlayable = try? await asset.load(.isPlayable),
              isPlayable,
              let duration = try? await asset.load(.duration) else {
            return false
        }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite && seconds > 0
    }

    private static func currentAppKitFrame(
        for targetWindow: WindowCaptureCandidate
    ) -> CGRect? {
        guard let info = (CGWindowListCopyWindowInfo(
            [.optionIncludingWindow],
            targetWindow.id
        ) as? [[String: Any]])?.first,
        (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            == targetWindow.processID,
        let bounds = info[kCGWindowBounds as String] as? NSDictionary,
        let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
        frame.width >= 4,
        frame.height >= 4 else {
            return nil
        }
        return appKitFrame(fromScreenCaptureKitFrame: frame)
    }

    private static func appKitFrame(fromScreenCaptureKitFrame frame: CGRect) -> CGRect {
        let primaryScreenHeight = NSScreen.screens
            .first(where: { abs($0.frame.minX) < 0.5 && abs($0.frame.minY) < 0.5 })?
            .frame.height ?? NSScreen.screens.first?.frame.height ?? 0
        return ScreenCoordinateConverter.appKitWindowRect(
            fromScreenCaptureKitFrame: frame,
            primaryScreenHeight: primaryScreenHeight
        )
    }

    private func startLifecycleMonitoring() {
        stopLifecycleMonitoring()
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleLifecycleInterruption(
                    "系统即将睡眠，录制已自动停止并保存。"
                )
            }
        })
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleLifecycleInterruption(
                    "用户会话已切换，录制已自动停止并保存。"
                )
            }
        })
        applicationObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshRecordingOverlay()
            }
        })
    }

    private func stopLifecycleMonitoring() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(workspaceCenter.removeObserver)
        workspaceObservers.removeAll()
        applicationObservers.forEach(NotificationCenter.default.removeObserver)
        applicationObservers.removeAll()
    }

    private func handleLifecycleInterruption(_ message: String) {
        switch state {
        case .prepared:
            cleanup(deleteOutput: true)
            onCancel?()
            onMessage?(message.replacingOccurrences(of: "录制已自动停止并保存。", with: "录制准备已取消。"))
        case .countingDown:
            cleanup(deleteOutput: true)
            onCancel?()
            onMessage?(message.replacingOccurrences(of: "录制已自动停止并保存。", with: "录制倒计时已取消。"))
        case .starting:
            pendingInterruptionMessage = message
        case .recording, .paused:
            Task { await finishRecording(message: message) }
        case .pausing, .resuming:
            pendingInterruptionMessage = message
        case .stopping:
            break
        }
    }

    private func beginRecordingActivity() {
        endRecordingActivity()
        recordingActivityToken = ProcessInfo.processInfo.beginActivity(
            options: [
                .userInitiated,
                .idleDisplaySleepDisabled,
                .idleSystemSleepDisabled,
                .suddenTerminationDisabled
            ],
            reason: "LocalShot 正在录制屏幕"
        )
    }

    private func endRecordingActivity() {
        if let recordingActivityToken {
            ProcessInfo.processInfo.endActivity(recordingActivityToken)
            self.recordingActivityToken = nil
        }
    }

    private static func screen(containingMostOf frame: CGRect) -> NSScreen? {
        NSScreen.screens.max {
            $0.frame.intersection(frame).area < $1.frame.intersection(frame).area
        }
    }

    private static func controlPanelFrame(
        selectionFrame: CGRect,
        screen: NSScreen
    ) -> CGRect {
        let size = CGSize(width: 448, height: 50)
        let visibleFrame = screen.visibleFrame
        var origin = CGPoint(
            x: selectionFrame.maxX - size.width,
            y: selectionFrame.minY - size.height - 10
        )
        if origin.y < visibleFrame.minY + 8 {
            origin.y = selectionFrame.maxY + 10
        }
        origin.x = min(
            max(origin.x, visibleFrame.minX + 8),
            visibleFrame.maxX - size.width - 8
        )
        origin.y = min(
            max(origin.y, visibleFrame.minY + 8),
            visibleFrame.maxY - size.height - 8
        )
        return CGRect(origin: origin, size: size)
    }

    private static let recordingOverlayLevel = NSWindow.Level(
        rawValue: NSWindow.Level.screenSaver.rawValue + 1
    )
}

private extension CGRect {
    var area: CGFloat {
        max(0, width) * max(0, height)
    }
}

@available(macOS 15.0, *)
private final class ScreenRecordingBorderPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@available(macOS 15.0, *)
private struct ScreenRecordingBorderView: View {
    @ObservedObject var controller: ScreenRecordingController

    var body: some View {
        ZStack {
            Rectangle()
                .strokeBorder(Color.red, lineWidth: 2.5)
                .background(Color.clear)
            if let countdownText = controller.countdownText {
                Text(countdownText)
                    .font(.system(size: 80, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.72), radius: 8, y: 2)
                    .accessibilityLabel("\(countdownText) 秒后开始录制")
            }
        }
    }
}

@available(macOS 15.0, *)
struct ScreenRecordingControlView: View {
    @ObservedObject var controller: ScreenRecordingController

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: controller.recordingStatusSymbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(controller.isPaused ? Color.orange : Color.red)
                .accessibilityHidden(true)
            Text(controller.elapsedText)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .frame(width: 68, alignment: .leading)
                .accessibilityLabel(controller.recordingStatusLabel)

            HStack(spacing: 4) {
                Image(systemName: controller.recordingModeSymbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(controller.recordingModeTitle)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .frame(width: 68)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("录制模式：\(controller.recordingModeTitle)")

            Divider().frame(height: 22)

            controlButton(
                symbol: controller.capturesSystemAudio ? "speaker.wave.2.fill" : "speaker.slash.fill",
                label: controller.capturesSystemAudio ? "关闭系统声音" : "开启系统声音"
            ) {
                controller.capturesSystemAudio.toggle()
            }
            .disabled(!controller.controlsEnabled)

            controlButton(
                symbol: controller.capturesMicrophone ? "mic.fill" : "mic.slash.fill",
                label: controller.capturesMicrophone ? "关闭麦克风" : "开启麦克风"
            ) {
                controller.toggleMicrophone()
            }
            .disabled(!controller.controlsEnabled)

            recordingPreferencesMenu
                .disabled(!controller.controlsEnabled)

            Divider().frame(height: 22)

            controlButton(
                symbol: controller.pauseButtonSymbol,
                label: controller.pauseButtonLabel
            ) {
                controller.togglePause()
            }
            .disabled(!controller.canTogglePause)

            controlButton(symbol: "xmark", label: "取消录制") {
                controller.cancel()
            }
            .disabled(controller.isTransitioning)

            Button(controller.primaryButtonTitle) {
                controller.performPrimaryAction()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(controller.isRecording || controller.isPaused ? .red : .blue)
            .disabled(controller.isTransitioning)
            .accessibilityLabel(controller.primaryButtonTitle)
            .help(
                controller.isRecording || controller.isPaused
                    ? "停止录制（全局快捷键 ⌘⇧R）"
                    : controller.primaryButtonTitle
            )
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.white.opacity(0.32), lineWidth: 1)
        )
    }

    private func controlButton(
        symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(label)
        .help(label)
    }

    private var recordingPreferencesMenu: some View {
        Menu {
            Section("画质") {
                ForEach(ScreenRecordingQuality.allCases) { quality in
                    Button {
                        controller.recordingQuality = quality
                    } label: {
                        Label(
                            quality.displayName,
                            systemImage: controller.recordingQuality == quality
                                ? "checkmark"
                                : "circle"
                        )
                    }
                }
            }
            Section("帧率") {
                ForEach(ScreenRecordingFrameRate.allCases) { frameRate in
                    Button {
                        controller.recordingFrameRate = frameRate
                    } label: {
                        Label(
                            frameRate.displayName,
                            systemImage: controller.recordingFrameRate == frameRate
                                ? "checkmark"
                                : "circle"
                        )
                    }
                }
            }
            Divider()
            Text(controller.estimatedFileSizeText)
            Text(controller.availableStorageText)
            Text("空间不足时自动停止并保存")
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("录制设置：\(controller.recordingPreferencesTitle)")
        .help("录制设置：\(controller.recordingPreferencesTitle)；\(controller.estimatedFileSizeText)")
    }
}
