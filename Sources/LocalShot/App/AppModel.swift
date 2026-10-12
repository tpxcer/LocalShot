import AppKit
import ImageIO
import LocalShotCore
import LocalShotEditing
import LocalShotHotkeys
import SwiftUI
import UniformTypeIdentifiers
#if !APP_STORE
import LocalShotUpdater
#endif

enum RecentSaveItem: Identifiable {
    case capture(CaptureAsset)
    case recording(ScreenRecordingAsset)

    var id: URL { url }

    var url: URL {
        switch self {
        case let .capture(asset): asset.url
        case let .recording(asset): asset.url
        }
    }

    var createdAt: Date {
        switch self {
        case let .capture(asset): asset.createdAt
        case let .recording(asset): asset.createdAt
        }
    }

    var symbolName: String {
        switch self {
        case let .capture(asset): asset.mode.symbolName
        case .recording: "record.circle"
        }
    }

    var accessibilityName: String {
        switch self {
        case .capture: "截图"
        case .recording: "录屏"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var recentAssets: [CaptureAsset] = []
    @Published private(set) var recentSaveItems: [RecentSaveItem] = []
    @Published private(set) var isCapturing = false
    @Published private(set) var hasPinnedScreenshots = false
    @Published private(set) var hasScreenCapturePermission = ScreenCapturePermission.isGranted
    @Published private(set) var microphonePermissionStatus = MicrophonePermission.status
    @Published var lastError: String?
    @Published private(set) var hotKeyErrorMessage: String?
    @Published private(set) var launchAtLoginState: LaunchAtLoginState = .disabled
    @Published private(set) var launchAtLoginErrorMessage: String?

    let settings: AppSettings
    let historySearchModel: CaptureHistorySearchModel
    #if !APP_STORE
    let updateController: UpdateController
    #endif
    @Published private(set) var fileStore: CaptureFileStore
    private let quickAccessPanel = QuickAccessPanelController()
    private let hotKeyManager = GlobalHotKeyManager()
    private let selectionOverlay = SelectionOverlayController()
    private let qqCaptureOverlay = QQCaptureOverlayController()
    private let windowSelectionOverlay = WindowSelectionOverlayController()
    private let annotationEditor = AnnotationEditorController()
    private let imageBeautifierController = ImageBeautifierController()
    private let pinnedScreenshotController = PinnedScreenshotController()
    private let ocrResultController = OCRResultController()
    private let translationResultController = TranslationResultController()
    private let captureHistoryController = CaptureHistoryController()
    private let scrollingCaptureController = ScrollingCaptureController()
    private let launchAtLoginController = LaunchAtLoginController()
    private var activeScreenRecordingController: AnyObject?
    private var recordingWindowLockAcceptanceWindow: NSWindow?

    init() {
        settings = AppSettings()
        historySearchModel = CaptureHistorySearchModel()
        #if !APP_STORE
        updateController = UpdateController()
        #endif
        do {
            fileStore = try CaptureFileStore(capturesDirectory: settings.captureDirectoryURL)
        } catch {
            settings.resetCaptureDirectory()
            if let defaultStore = try? CaptureFileStore() {
                fileStore = defaultStore
                lastError = "无法使用自定义截图目录，已恢复默认目录。"
            } else {
                let fallback = FileManager.default.temporaryDirectory
                    .appendingPathComponent("LocalShot-Captures", isDirectory: true)
                fileStore = try! CaptureFileStore(capturesDirectory: fallback)
                lastError = "无法创建应用数据目录，暂时使用临时目录。"
            }
        }

        applyRetentionPolicy()
        refreshHistory()

        hotKeyManager.onCapture = { [weak self] mode in
            self?.capture(mode)
        }
        hotKeyManager.onRecognizeText = { [weak self] in
            self?.recognizeScreenText()
        }
        do {
            try hotKeyManager.start(configuration: settings.hotKeyConfiguration)
        } catch {
            let originalConfiguration = settings.hotKeyConfiguration
            if originalConfiguration != .conflictSafe {
                do {
                    try hotKeyManager.start(configuration: .conflictSafe)
                    settings.setHotKeyConfiguration(.conflictSafe)
                    hotKeyErrorMessage = originalConfiguration == .default
                        ? "默认区域截图快捷键 ⌘⌃A 已被占用，已改用 ⌃⌥1。"
                        : "自定义快捷键无法注册，已改用冲突安全组合：\(error.localizedDescription)"
                } catch {
                    lastError = "全局快捷键注册失败：\(error.localizedDescription)"
                }
            } else {
                lastError = "全局快捷键注册失败：\(error.localizedDescription)"
            }
        }

        pinnedScreenshotController.onWindowsChanged = { [weak self] hasWindows in
            self?.hasPinnedScreenshots = hasWindows
        }
        #if !APP_STORE
        updateController.onUpdateAvailable = { [weak self] release in
            self?.presentUpdateAlert(release)
        }
        #endif
        refreshLaunchAtLoginState()
    }

    #if !APP_STORE
    func checkForUpdatesAutomaticallyIfNeeded() {
        updateController.checkAutomaticallyIfNeeded(
            isEnabled: settings.automaticallyChecksForUpdates
        )
    }

    private func presentUpdateAlert(_ release: LocalShotUpdateRelease) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "发现 LocalShot 新版本 \(release.version.displayName)"
        alert.informativeText = "是否下载并打开新版安装包？下载完成并校验通过后，请把新版拖入“应用程序”覆盖旧版。"
        alert.addButton(withTitle: "下载更新")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            updateController.downloadAndOpen(release)
        }
    }
    #endif

    func refreshPermissionStates() {
        hasScreenCapturePermission = ScreenCapturePermission.isGranted
        microphonePermissionStatus = MicrophonePermission.status
    }

    func updateHotKey(_ shortcut: HotKeyShortcut?, for action: HotKeyAction) {
        var candidate = settings.hotKeyConfiguration
        candidate.setShortcut(shortcut, for: action)
        do {
            try hotKeyManager.apply(candidate)
            settings.setHotKeyConfiguration(candidate)
            hotKeyErrorMessage = nil
        } catch {
            hotKeyErrorMessage = error.localizedDescription
        }
    }

    func resetHotKeys() {
        do {
            try hotKeyManager.apply(.default)
            settings.resetHotKeyConfiguration()
            hotKeyErrorMessage = nil
        } catch {
            hotKeyErrorMessage = error.localizedDescription
        }
    }

    func refreshLaunchAtLoginState() {
        launchAtLoginState = launchAtLoginController.currentState()
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            launchAtLoginState = try launchAtLoginController.setEnabled(enabled)
            launchAtLoginErrorMessage = nil
        } catch {
            refreshLaunchAtLoginState()
            launchAtLoginErrorMessage = "无法更新开机启动：\(error.localizedDescription)"
        }
    }

    func openLoginItemsSettings() {
        launchAtLoginController.openSystemSettings()
    }

    func capture(_ mode: CaptureMode) {
        guard !isCapturing else {
            return
        }

        if !ScreenCapturePermission.isGranted, !ScreenCapturePermission.request() {
            refreshPermissionStates()
            lastError = "需要在系统设置中允许屏幕捕获权限，然后重新尝试。"
            return
        }

        refreshPermissionStates()

        lastError = nil

        switch mode {
        case .area:
            beginAreaCapture()
        case .window:
            beginWindowCapture()
        case .fullScreen:
            beginFullScreenCapture()
        case .scrolling:
            beginScrollingCapture()
        }
    }

    func recognizeScreenText() {
        guard !isCapturing else {
            return
        }
        if !ScreenCapturePermission.isGranted, !ScreenCapturePermission.request() {
            refreshPermissionStates()
            lastError = "需要在系统设置中允许屏幕捕获权限，然后重新尝试。"
            return
        }
        refreshPermissionStates()
        lastError = nil

        #if !APP_STORE
        guard #available(macOS 14.0, *) else {
            beginSystemTextRecognitionCapture()
            return
        }
        #endif
        beginScreenTextRecognitionSelection()
    }

    func beginScreenRecording() {
        guard !isCapturing else { return }
        guard #available(macOS 15.0, *) else {
            lastError = "区域录屏需要 macOS 15 或更高版本。"
            return
        }
        if !ScreenCapturePermission.isGranted, !ScreenCapturePermission.request() {
            refreshPermissionStates()
            lastError = "需要在系统设置中允许屏幕捕获权限，然后重新尝试。"
            return
        }
        refreshPermissionStates()
        lastError = nil
        isCapturing = true

        let scalesByDisplayID = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen in
            screen.localShotDisplayID.map { ($0, screen.backingScaleFactor) }
        })
        let service = ScreenCaptureKitService()
        Task { [self] in
            do {
                let previews = try await service.captureDisplayPreviews(
                    scalesByDisplayID: scalesByDisplayID,
                    showsCursor: false
                )
                let candidates = (try? await service.availableWindows()) ?? []
                selectionOverlay.begin(
                    previewImages: previews,
                    candidates: candidates,
                    showsPreviewAsBackground: true,
                    instructionText: "移动鼠标自动识别窗口，拖动自由选择录制区域  ·  右键或 Esc 取消"
                ) { [weak self] result in
                    guard let self else { return }
                    guard let result else {
                        self.isCapturing = false
                        return
                    }
                    self.prepareScreenRecording(result)
                }
            } catch {
                isCapturing = false
                lastError = "无法准备屏幕录制：\(error.localizedDescription)"
            }
        }
    }

    @available(macOS 14.0, *)
    private func beginScreenTextRecognitionSelection() {
        isCapturing = true
        let scalesByDisplayID = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen in
            screen.localShotDisplayID.map { ($0, screen.backingScaleFactor) }
        })
        let service = ScreenCaptureKitService()

        Task { [self] in
            do {
                let previews = try await service.captureDisplayPreviews(
                    scalesByDisplayID: scalesByDisplayID,
                    showsCursor: false
                )
                selectionOverlay.begin(
                    previewImages: previews,
                    showsPreviewAsBackground: true,
                    instructionText: "拖动选择要识别的文字区域  ·  右键或 Esc 取消"
                ) { [weak self] result in
                    guard let self else {
                        return
                    }
                    guard let result else {
                        self.isCapturing = false
                        return
                    }
                    self.captureSelectedTextRegion(result)
                }
            } catch {
                isCapturing = false
                lastError = "无法准备文字区域选择：\(error.localizedDescription)"
            }
        }
    }

    @available(macOS 14.0, *)
    private func captureSelectedTextRegion(_ result: SelectionOverlayController.Result) {
        let outputURL = nextCaptureURL(mode: .area)
        let service = ScreenCaptureKitService()
        let scaleFactor = result.screen.backingScaleFactor

        Task { [self] in
            do {
                let capturedURL = try await service.capture(
                    displayID: result.displayID,
                    scaleFactor: scaleFactor,
                    sourceRect: result.sourceRect,
                    outputURL: outputURL,
                    showsCursor: false,
                    outputFormat: settings.outputFormat,
                    jpegQuality: settings.jpegQuality
                )
                finishTextRecognitionCapture(url: capturedURL)
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                isCapturing = false
                lastError = "文字区域截图失败：\(error.localizedDescription)"
            }
        }
    }

    #if !APP_STORE
    private func beginSystemTextRecognitionCapture() {
        isCapturing = true
        let outputURL = nextCaptureURL(mode: .area)

        Task { [self] in
            do {
                let capturedURL = try await SystemScreenshotAdapter.capture(
                    mode: .area,
                    outputURL: outputURL,
                    format: settings.outputFormat,
                    showsCursor: false,
                    includesWindowShadow: false
                )
                guard let capturedURL else {
                    isCapturing = false
                    return
                }
                finishTextRecognitionCapture(url: capturedURL)
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                isCapturing = false
                lastError = "文字区域截图失败：\(error.localizedDescription)"
            }
        }
    }
    #endif

    private func finishTextRecognitionCapture(url: URL) {
        isCapturing = false
        let asset = CaptureAsset(url: url, createdAt: .now, mode: .area)
        refreshHistory()
        openOCRResult(asset)
    }

    private func beginScrollingCapture() {
        #if !APP_STORE
        guard #available(macOS 14.0, *) else {
            lastError = "区域长截图需要 macOS 14 或更高版本。"
            return
        }
        #endif
        beginAreaCapture(emphasizesScrollingAction: true)
    }

    private func beginAreaCapture(emphasizesScrollingAction: Bool = false) {
        #if !APP_STORE
        guard #available(macOS 14.0, *) else {
            beginSystemCapture(mode: .area)
            return
        }
        #endif

        isCapturing = true
        let scalesByDisplayID = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen in
            screen.localShotDisplayID.map { ($0, screen.backingScaleFactor) }
        })
        let service = ScreenCaptureKitService()

        Task { [self] in
            do {
                let previews = try await service.captureDisplayPreviews(
                    scalesByDisplayID: scalesByDisplayID,
                    showsCursor: settings.includesCursor
                )
                let candidates = (try? await service.availableWindows()) ?? []
                qqCaptureOverlay.begin(
                    previewImages: previews,
                    candidates: candidates,
                    emphasizesScrollingAction: emphasizesScrollingAction
                ) { [weak self] result in
                    guard let self else {
                        return
                    }
                    guard let result else {
                        self.isCapturing = false
                        return
                    }
                    if result.action == .scrolling {
                        self.beginQQScrollingCapture(result)
                        return
                    }
                    if result.action == .recording {
                        guard #available(macOS 15.0, *) else {
                            self.isCapturing = false
                            self.lastError = "区域录屏需要 macOS 15 或更高版本。"
                            return
                        }
                        self.prepareScreenRecording(SelectionOverlayController.Result(
                            screen: result.screen,
                            displayID: result.displayID,
                            sourceRect: result.sourceRect,
                            targetWindow: result.recordingTargetWindow
                        ))
                        return
                    }
                    self.finishQQAreaCapture(result)
                }
            } catch {
                isCapturing = false
                lastError = "无法冻结屏幕画面：\(error.localizedDescription)"
            }
        }
    }

    @available(macOS 14.0, *)
    private func beginQQScrollingCapture(_ result: QQCaptureOverlayResult) {
        guard let target = result.targetWindow,
              let cropRect = result.windowRelativeRect else {
            isCapturing = false
            lastError = "区域长截图必须完全位于一个可捕获窗口内。"
            return
        }
        let outputURL = fileStore.nextCaptureURL(
            mode: .scrolling,
            format: .png,
            filenamePrefix: settings.filenamePrefix
        )
        let selectionRect = CGRect(
            x: result.screen.frame.minX + result.sourceRect.minX,
            y: result.screen.frame.minY + result.screen.frame.height - result.sourceRect.maxY,
            width: result.sourceRect.width,
            height: result.sourceRect.height
        )
        scrollingCaptureController.start(
            target: target,
            outputURL: outputURL,
            captureCropRect: cropRect,
            selectionRect: selectionRect,
            onComplete: { [weak self] url in
                self?.finishCapture(url: url, mode: .scrolling)
            },
            onCancel: { [weak self] in
                self?.isCapturing = false
            },
            onError: { [weak self] message in
                self?.isCapturing = false
                self?.lastError = "区域长截图失败：\(message)"
            }
        )
    }

    @available(macOS 14.0, *)
    private func finishQQAreaCapture(_ result: QQCaptureOverlayResult) {
        let outputURL = nextCaptureURL(mode: .area)
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let baseURL = temporaryDirectory.appendingPathComponent(
            "LocalShot-QQCapture-\(UUID().uuidString)-base.png"
        )
        let annotatedURL = temporaryDirectory.appendingPathComponent(
            "LocalShot-QQCapture-\(UUID().uuidString)-annotated.png"
        )
        Task { [self] in
            defer {
                try? FileManager.default.removeItem(at: baseURL)
                try? FileManager.default.removeItem(at: annotatedURL)
            }
            do {
                try CaptureImageWriter.write(
                    result.frozenSelectionImage,
                    to: baseURL,
                    format: .png
                )

                let sourceURL: URL
                if result.project.annotations.isEmpty {
                    sourceURL = baseURL
                } else {
                    var project = result.project
                    project.imageFilename = baseURL.lastPathComponent
                    try AnnotationRenderer.render(
                        baseImageURL: baseURL,
                        project: project,
                        outputURL: annotatedURL
                    )
                    sourceURL = annotatedURL
                }

                guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                    throw AnnotationRendererError.imageReadFailed
                }
                try CaptureImageWriter.write(
                    image,
                    to: outputURL,
                    format: settings.outputFormat,
                    jpegQuality: settings.jpegQuality
                )

                let asset = CaptureAsset(url: outputURL, createdAt: .now, mode: .area)
                isCapturing = false
                refreshHistory()
                performQQCaptureAction(result.action, asset: asset)

            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                isCapturing = false
                lastError = "截图失败：\(error.localizedDescription)"
            }
        }
    }

    private func performQQCaptureAction(
        _ action: QQCaptureOverlayAction,
        asset: CaptureAsset
    ) {
        switch action {
        case .finish:
            copyToClipboard(asset)
        case .save:
            saveAs(asset)
        case .recognizeText:
            openOCRResult(asset)
        case .recording:
            assertionFailure("区域录屏不应进入静态截图动作分发。")
        case .translate:
            openTranslationResult(asset)
        case .pin:
            pinScreenshot(asset)
        case .scrolling:
            assertionFailure("区域长截图不应进入静态截图动作分发。")
        }
    }

    @available(macOS 15.0, *)
    private func prepareScreenRecording(_ result: SelectionOverlayController.Result) {
        do {
            let outputURL = try ScreenRecordingFileStore(
                recordingsDirectory: fileStore.capturesDirectory
            ).nextRecordingURL(
                filenamePrefix: settings.filenamePrefix
            )
            let controller = ScreenRecordingController()
            activeScreenRecordingController = controller
            configureScreenRecordingHotKey(for: controller)
            controller.onMessage = { [weak self] message in
                self?.lastError = message
            }
            controller.onCancel = { [weak self] in
                self?.clearScreenRecordingHotKey()
                self?.activeScreenRecordingController = nil
                self?.isCapturing = false
            }
            controller.onError = { [weak self] message in
                self?.clearScreenRecordingHotKey()
                self?.activeScreenRecordingController = nil
                self?.isCapturing = false
                self?.lastError = "屏幕录制失败：\(message)"
            }
            controller.onComplete = { [weak self] url in
                self?.clearScreenRecordingHotKey()
                self?.activeScreenRecordingController = nil
                self?.isCapturing = false
                self?.refreshHistory()
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            controller.prepare(
                result: result,
                outputURL: outputURL,
                quality: settings.screenRecordingQuality,
                frameRate: settings.screenRecordingFrameRate
            )
        } catch {
            activeScreenRecordingController = nil
            isCapturing = false
            lastError = "无法准备录制文件：\(error.localizedDescription)"
        }
    }

    @available(macOS 15.0, *)
    private func configureScreenRecordingHotKey(
        for controller: ScreenRecordingController
    ) {
        hotKeyManager.onStopScreenRecording = { [weak controller] in
            controller?.stopFromGlobalHotKey()
        }
        controller.onRecordingSessionStateChange = { [weak self] isActive in
            guard let self else { return }
            do {
                try hotKeyManager.setScreenRecordingStopEnabled(isActive)
            } catch {
                if isActive {
                    lastError = "录制已开始，但停止快捷键不可用：\(error.localizedDescription)"
                }
            }
        }
        controller.onRecordingPreferencesChanged = { [weak self] quality, frameRate in
            self?.settings.screenRecordingQuality = quality
            self?.settings.screenRecordingFrameRate = frameRate
        }
    }

    private func clearScreenRecordingHotKey() {
        try? hotKeyManager.setScreenRecordingStopEnabled(false)
        hotKeyManager.onStopScreenRecording = nil
    }

    private func beginFullScreenCapture() {
        #if APP_STORE
        guard let screen = NSScreen.main else {
            lastError = "没有找到可捕获的显示器。"
            return
        }
        #else
        guard #available(macOS 14.0, *), let screen = NSScreen.main else {
            beginSystemCapture(mode: .fullScreen)
            return
        }
        #endif

        isCapturing = true
        beginScreenCaptureKit(mode: .fullScreen, screen: screen, sourceRect: nil)
    }

    private func beginWindowCapture() {
        #if !APP_STORE
        guard #available(macOS 14.0, *) else {
            beginSystemCapture(mode: .window)
            return
        }
        #endif

        isCapturing = true
        let service = ScreenCaptureKitService()
        Task { [self] in
            do {
                let candidates = try await service.availableWindows()
                guard !candidates.isEmpty else {
                    isCapturing = false
                    lastError = "没有找到可捕获的窗口。"
                    return
                }
                windowSelectionOverlay.begin(candidates: candidates) { [weak self] windowID in
                    guard let self else {
                        return
                    }
                    guard let windowID else {
                        self.isCapturing = false
                        return
                    }
                    self.beginScreenCaptureKitWindow(windowID: windowID)
                }
            } catch {
                isCapturing = false
                lastError = "读取窗口列表失败：\(error.localizedDescription)"
            }
        }
    }

    @available(macOS 14.0, *)
    private func beginScreenCaptureKitWindow(windowID: CGWindowID) {
        let outputURL = nextCaptureURL(mode: .window)
        let service = ScreenCaptureKitService()

        Task {
            do {
                let capturedURL = try await service.capture(
                    windowID: windowID,
                    outputURL: outputURL,
                    includesShadow: settings.includesWindowShadow,
                    showsCursor: settings.includesCursor,
                    outputFormat: settings.outputFormat,
                    jpegQuality: settings.jpegQuality
                )
                finishCapture(url: capturedURL, mode: .window)
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                isCapturing = false
                lastError = "窗口截图失败：\(error.localizedDescription)"
            }
        }
    }

    @available(macOS 14.0, *)
    private func beginScreenCaptureKit(
        mode: CaptureMode,
        screen: NSScreen,
        sourceRect: CGRect?
    ) {
        guard let displayID = screen.localShotDisplayID else {
            isCapturing = false
            lastError = "无法识别目标显示器。"
            return
        }
        let outputURL = nextCaptureURL(mode: mode)
        let service = ScreenCaptureKitService()
        let scaleFactor = screen.backingScaleFactor

        Task {
            do {
                let capturedURL = try await service.capture(
                    displayID: displayID,
                    scaleFactor: scaleFactor,
                    sourceRect: sourceRect,
                    outputURL: outputURL,
                    showsCursor: settings.includesCursor,
                    outputFormat: settings.outputFormat,
                    jpegQuality: settings.jpegQuality
                )
                finishCapture(url: capturedURL, mode: mode)
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                isCapturing = false
                lastError = "截图失败：\(error.localizedDescription)"
            }
        }
    }

    #if !APP_STORE
    private func beginSystemCapture(mode: CaptureMode) {
        isCapturing = true
        let outputURL = nextCaptureURL(mode: mode)

        Task {
            do {
                let capturedURL = try await SystemScreenshotAdapter.capture(
                    mode: mode,
                    outputURL: outputURL,
                    format: settings.outputFormat,
                    showsCursor: settings.includesCursor,
                    includesWindowShadow: settings.includesWindowShadow
                )
                guard let capturedURL else {
                    isCapturing = false
                    return
                }
                finishCapture(url: capturedURL, mode: mode)
            } catch {
                isCapturing = false
                lastError = "截图失败：\(error.localizedDescription)"
            }
        }
    }
    #endif

    private func finishCapture(url: URL, mode: CaptureMode) {
        isCapturing = false
        let asset = CaptureAsset(
            url: url,
            createdAt: .now,
            mode: mode
        )
        refreshHistory()
        showQuickAccess(for: asset)
    }

    func refreshHistory() {
        do {
            let captures = try fileStore.recentCaptures(limit: nil).filter {
                !settings.isHiddenFromRecentSaves($0.url)
            }
            let recordings = try ScreenRecordingFileStore(
                recordingsDirectory: fileStore.capturesDirectory
            ).recentRecordings(limit: nil).filter {
                !settings.isHiddenFromRecentSaves($0.url)
            }
            recentAssets = captures
            recentSaveItems = (
                captures.map(RecentSaveItem.capture)
                    + recordings.map(RecentSaveItem.recording)
            ).sorted { $0.createdAt > $1.createdAt }
        } catch {
            lastError = "读取最近保存失败：\(error.localizedDescription)"
        }
    }

    func openRecentSave(_ item: RecentSaveItem) {
        switch item {
        case let .capture(asset):
            showQuickAccess(for: asset)
        case let .recording(asset):
            NSWorkspace.shared.activateFileViewerSelecting([asset.url])
        }
    }

    func showQuickAccess(for asset: CaptureAsset) {
        quickAccessPanel.show(
            asset: asset,
            autoCloseInterval: settings.quickAccessDuration,
            actions: QuickAccessActions(
                copy: { [weak self] in self?.copyToClipboard(asset) },
                annotate: { [weak self] in self?.openAnnotationEditor(asset) },
                beautify: { [weak self] in self?.openImageBeautifier(asset) },
                pin: { [weak self] in self?.pinScreenshot(asset) },
                recognizeText: { [weak self] in self?.openOCRResult(asset) },
                translate: { [weak self] in self?.openTranslationResult(asset) },
                saveAs: { [weak self] in self?.saveAs(asset) },
                reveal: { [weak self] in self?.revealInFinder(asset) },
                delete: { [weak self] in self?.delete(asset) },
                dismiss: { [weak self] in self?.quickAccessPanel.dismiss() }
            )
        )
    }

    func openCaptureDirectory() {
        NSWorkspace.shared.open(fileStore.capturesDirectory)
    }

    func openCaptureHistory() {
        captureHistoryController.open(
            appModel: self,
            searchModel: historySearchModel
        )
        historySearchModel.synchronize(assets: recentAssets)
    }

    func importImageForAnnotation() {
        chooseLocalImage { [weak self] url in
            self?.annotationEditor.openImportedImage(imageURL: url) { message in
                self?.lastError = message
            }
        }
    }

    func importImageForOCR() {
        chooseLocalImage { [weak self] url in
            guard let self else { return }
            self.ocrResultController.open(asset: self.importedAsset(url))
        }
    }

    func importImageForTranslation() {
        chooseLocalImage { [weak self] url in
            guard let self else { return }
            self.translationResultController.open(asset: self.importedAsset(url)) { message in
                self.lastError = message
            }
        }
    }

    func importImageForBeautification() {
        chooseLocalImage { [weak self] url in
            guard let self else { return }
            self.imageBeautifierController.open(asset: self.importedAsset(url)) { message in
                self.lastError = message
            }
        }
    }

    func openUIAcceptance(action: String, fileURL: URL) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            lastError = "UI 验收图片不存在：\(fileURL.path)"
            return
        }
        let asset = importedAsset(fileURL)
        switch action {
        case "settings":
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        case "quick-access":
            showQuickAccess(for: asset)
        case "annotation":
            annotationEditor.openImportedImage(imageURL: fileURL) { [weak self] message in
                self?.lastError = message
            }
        case "ocr":
            ocrResultController.open(asset: asset)
        case "translation":
            translationResultController.open(asset: asset) { [weak self] message in
                self?.lastError = message
            }
        case "beautification":
            imageBeautifierController.open(asset: asset) { [weak self] message in
                self?.lastError = message
            }
        case "pin":
            pinScreenshot(asset)
        case "history":
            openCaptureHistory()
        case "area-selection":
            openUIAcceptanceAreaSelection(fileURL: fileURL)
        case "area-selection-cursor":
            openUIAcceptanceAreaSelection(fileURL: fileURL, isInteractive: true)
        case "area-selection-scrolling":
            openUIAcceptanceAreaSelection(
                fileURL: fileURL,
                emphasizesScrollingAction: true
            )
        case "area-selection-pixelate":
            openUIAcceptanceAreaSelection(
                fileURL: fileURL,
                showsPixelateProperties: true
            )
        case "scrolling-progress":
            scrollingCaptureController.showUIAcceptance(previewURL: fileURL)
        case "recording-controls":
            if #available(macOS 15.0, *) {
                openUIAcceptanceRecordingControls()
            } else {
                lastError = "区域录屏需要 macOS 15 或更高版本。"
            }
        case "recording-selection":
            openUIAcceptanceRecordingSelection(fileURL: fileURL)
        case "recording-window-lock":
            if #available(macOS 15.0, *) {
                openUIAcceptanceRecordingWindowLock()
            } else {
                lastError = "锁定窗口录制需要 macOS 15 或更高版本。"
            }
        case "recording-showcase":
            if #available(macOS 15.0, *) {
                openUIAcceptanceRecordingWindowLock(showsTestControls: false)
            } else {
                lastError = "锁定窗口录制需要 macOS 15 或更高版本。"
            }
        case "window-selection":
            openUIAcceptanceWindowSelection(fileURL: fileURL)
        case "capture-area":
            capture(.area)
        case "capture-window":
            capture(.window)
        case "capture-fullscreen":
            capture(.fullScreen)
        case "capture-scrolling":
            capture(.scrolling)
        case "capture-recording":
            beginScreenRecording()
        default:
            lastError = "未知 UI 验收动作：\(action)"
        }
    }

    @available(macOS 15.0, *)
    private func openUIAcceptanceRecordingControls() {
        guard let screen = NSScreen.screens.first(where: {
            abs($0.frame.minX) < 0.5 && abs($0.frame.minY) < 0.5
        }) ?? NSScreen.screens.first,
        let displayID = screen.localShotDisplayID else {
            lastError = "无法准备区域录屏验收界面。"
            return
        }

        let width = min(900, max(320, screen.frame.width - 120))
        let height = min(520, max(240, screen.frame.height - 220))
        let frame = CGRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.midY - height / 2 + 40,
            width: width,
            height: height
        )
        let sourceRect = CGRect(
            x: frame.minX - screen.frame.minX,
            y: screen.frame.maxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )

        do {
            let outputURL = try ScreenRecordingFileStore(
                recordingsDirectory: fileStore.capturesDirectory
            ).nextRecordingURL(
                filenamePrefix: "LocalShot-UI-Acceptance"
            )
            let controller = ScreenRecordingController()
            activeScreenRecordingController = controller
            configureScreenRecordingHotKey(for: controller)
            controller.onCancel = { [weak self] in
                self?.clearScreenRecordingHotKey()
                self?.activeScreenRecordingController = nil
            }
            controller.onError = { [weak self] message in
                self?.clearScreenRecordingHotKey()
                self?.activeScreenRecordingController = nil
                self?.lastError = message
            }
            controller.onComplete = { [weak self] url in
                self?.clearScreenRecordingHotKey()
                self?.activeScreenRecordingController = nil
                self?.refreshHistory()
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            controller.prepare(
                result: SelectionOverlayController.Result(
                    screen: screen,
                    displayID: displayID,
                    sourceRect: sourceRect
                ),
                outputURL: outputURL,
                quality: settings.screenRecordingQuality,
                frameRate: settings.screenRecordingFrameRate
            )
        } catch {
            lastError = "无法准备区域录屏验收界面：\(error.localizedDescription)"
        }
    }

    private func openUIAcceptanceRecordingSelection(fileURL: URL) {
        guard let previewImages = uiAcceptancePreviewImages(fileURL: fileURL),
              let screen = NSScreen.screens.first(where: {
                  abs($0.frame.minX) < 0.5 && abs($0.frame.minY) < 0.5
              }) ?? NSScreen.screens.first,
              let displayID = screen.localShotDisplayID else {
            lastError = "无法准备区域录屏选窗验收界面。"
            return
        }

        let localFrame = CGRect(
            x: screen.frame.width * 0.18,
            y: screen.frame.height * 0.20,
            width: screen.frame.width * 0.64,
            height: screen.frame.height * 0.58
        )
        let candidate = WindowCaptureCandidate(
            id: 910_001,
            frame: CGRect(
                x: screen.frame.minX + localFrame.minX,
                y: screen.frame.height - localFrame.maxY,
                width: localFrame.width,
                height: localFrame.height
            ),
            processID: ProcessInfo.processInfo.processIdentifier,
            applicationName: "LocalShot 验收",
            title: "自动识别窗口"
        )

        isCapturing = true
        selectionOverlay.begin(
            previewImages: previewImages,
            candidates: [candidate],
            initialCursorPoints: [displayID: CGPoint(x: localFrame.midX, y: localFrame.midY)],
            showsPreviewAsBackground: true,
            locksSnappedWindows: false,
            instructionText: "移动鼠标自动识别窗口，拖动自由选择录制区域  ·  右键或 Esc 取消"
        ) { [weak self] result in
            guard let self else { return }
            guard let result else {
                self.isCapturing = false
                return
            }
            guard #available(macOS 15.0, *) else {
                self.isCapturing = false
                self.lastError = "区域录屏需要 macOS 15 或更高版本。"
                return
            }
            self.prepareScreenRecording(result)
        }
    }

    @available(macOS 15.0, *)
    private func openUIAcceptanceRecordingWindowLock(showsTestControls: Bool = true) {
        guard let screen = NSScreen.screens.first(where: {
            abs($0.frame.minX) < 0.5 && abs($0.frame.minY) < 0.5
        }) ?? NSScreen.screens.first,
        let displayID = screen.localShotDisplayID else {
            lastError = "无法准备锁定窗口录制验收界面。"
            return
        }

        let size = CGSize(width: 680, height: showsTestControls ? 420 : 330)
        let frame = CGRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2 + 60,
            width: size.width,
            height: size.height
        )
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.title = showsTestControls
            ? "LocalShot 锁定窗口验收"
            : "LocalShot 锁定窗口录屏"
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        recordingWindowLockAcceptanceWindow = window

        let primaryScreenHeight = NSScreen.screens
            .first(where: { abs($0.frame.minX) < 0.5 && abs($0.frame.minY) < 0.5 })?
            .frame.height ?? screen.frame.height
        let candidate = WindowCaptureCandidate(
            id: CGWindowID(window.windowNumber),
            frame: CGRect(
                x: frame.minX,
                y: primaryScreenHeight - frame.maxY,
                width: frame.width,
                height: frame.height
            ),
            processID: ProcessInfo.processInfo.processIdentifier,
            applicationName: "LocalShot 验收",
            title: window.title
        )
        let localFrame = frame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        let sourceRect = ScreenCoordinateConverter.screenCaptureKitSourceRect(
            fromAppKitSelection: localFrame,
            screenHeight: screen.frame.height
        )

        do {
            let outputURL = try ScreenRecordingFileStore(
                recordingsDirectory: fileStore.capturesDirectory
            ).nextRecordingURL(
                filenamePrefix: "LocalShot-Window-Lock-Acceptance"
            )
            let controller = ScreenRecordingController()
            activeScreenRecordingController = controller
            configureScreenRecordingHotKey(for: controller)
            controller.onMessage = { [weak self] message in
                self?.lastError = message
            }
            controller.onCancel = { [weak self] in
                self?.clearScreenRecordingHotKey()
                self?.activeScreenRecordingController = nil
                self?.recordingWindowLockAcceptanceWindow?.close()
                self?.recordingWindowLockAcceptanceWindow = nil
            }
            controller.onError = { [weak self] message in
                self?.clearScreenRecordingHotKey()
                self?.activeScreenRecordingController = nil
                self?.lastError = message
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "锁定窗口录制验收失败"
                alert.informativeText = message
                alert.addButton(withTitle: "确定")
                if let window = self?.recordingWindowLockAcceptanceWindow {
                    alert.beginSheetModal(for: window)
                }
            }
            controller.onComplete = { [weak self] url in
                self?.clearScreenRecordingHotKey()
                self?.activeScreenRecordingController = nil
                self?.recordingWindowLockAcceptanceWindow?.close()
                self?.recordingWindowLockAcceptanceWindow = nil
                self?.refreshHistory()
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            window.contentView = NSHostingView(rootView:
                RecordingWindowLockAcceptanceView(
                    controller: controller,
                    showsTestControls: showsTestControls,
                    onMove: { [weak window] in
                        guard let window else { return }
                        window.setFrame(
                            window.frame.offsetBy(dx: 160, dy: 0),
                            display: true
                        )
                    },
                    onResize: { [weak window] in
                        guard let window else { return }
                        var resized = window.frame
                        resized.size.width += 120
                        resized.size.height += 80
                        window.setFrame(resized, display: true)
                    },
                    onHideBriefly: { [weak window] in
                        window?.orderOut(nil)
                        Task { @MainActor [weak window] in
                            try? await Task.sleep(for: .milliseconds(800))
                            window?.orderFrontRegardless()
                        }
                    },
                    onSimulateSleep: {
                        NSWorkspace.shared.notificationCenter.post(
                            name: NSWorkspace.willSleepNotification,
                            object: NSWorkspace.shared
                        )
                    },
                    onSimulateLowStorage: {
                        controller.simulateLowStorageForAcceptance()
                    },
                    onSimulateGlobalStop: { [weak self] in
                        self?.hotKeyManager.onStopScreenRecording?()
                    }
                )
            )
            controller.prepare(
                result: SelectionOverlayController.Result(
                    screen: screen,
                    displayID: displayID,
                    sourceRect: sourceRect,
                    targetWindow: candidate
                ),
                outputURL: outputURL,
                quality: settings.screenRecordingQuality,
                frameRate: settings.screenRecordingFrameRate
            )
        } catch {
            window.close()
            recordingWindowLockAcceptanceWindow = nil
            lastError = "无法准备锁定窗口录制验收界面：\(error.localizedDescription)"
        }
    }

    private func openUIAcceptanceAreaSelection(
        fileURL: URL,
        emphasizesScrollingAction: Bool = false,
        showsPixelateProperties: Bool = false,
        isInteractive: Bool = false
    ) {
        guard let previewImages = uiAcceptancePreviewImages(fileURL: fileURL),
              !previewImages.isEmpty,
              let primaryScreen = NSScreen.screens.first(where: {
                  abs($0.frame.minX) < 0.5 && abs($0.frame.minY) < 0.5
              }) ?? NSScreen.screens.first,
              let primaryDisplayID = primaryScreen.localShotDisplayID else {
            lastError = "无法准备区域选区验收图片。"
            return
        }

        let screenFrame = primaryScreen.frame
        let candidateFrame = CGRect(
            x: screenFrame.minX + screenFrame.width * 0.12,
            y: screenFrame.minY + screenFrame.height * 0.14,
            width: screenFrame.width * 0.76,
            height: screenFrame.height * 0.70
        )
        let candidate = WindowCaptureCandidate(
            id: 910_001,
            frame: CGRect(
                x: candidateFrame.minX,
                y: screenFrame.height - candidateFrame.maxY,
                width: candidateFrame.width,
                height: candidateFrame.height
            ),
            processID: ProcessInfo.processInfo.processIdentifier,
            applicationName: "LocalShot 验收",
            title: "快捷截图工具条"
        )
        let scale = primaryScreen.backingScaleFactor
        let sampleAnnotations: [AnnotationItem] = [
            .rectangle(RectangleAnnotation(
                rect: AnnotationRect(
                    x: candidateFrame.width * scale * 0.06,
                    y: candidateFrame.height * scale * 0.58,
                    width: candidateFrame.width * scale * 0.42,
                    height: candidateFrame.height * scale * 0.27
                ),
                lineWidth: 3 * scale
            )),
            .arrow(ArrowAnnotation(
                start: AnnotationPoint(
                    x: candidateFrame.width * scale * 0.52,
                    y: candidateFrame.height * scale * 0.34
                ),
                end: AnnotationPoint(
                    x: candidateFrame.width * scale * 0.74,
                    y: candidateFrame.height * scale * 0.58
                ),
                lineWidth: 3 * scale,
                note: "箭头备注",
                noteFontSize: 14 * scale
            )),
            .step(StepAnnotation(
                center: AnnotationPoint(
                    x: candidateFrame.width * scale * 0.79,
                    y: candidateFrame.height * scale * 0.47
                ),
                number: 1,
                diameter: 30 * scale,
                note: "步骤备注"
            )),
            .pixelate(PixelateAnnotation(
                rect: AnnotationRect(
                    x: candidateFrame.width * scale * 0.29,
                    y: candidateFrame.height * scale * 0.08,
                    width: candidateFrame.width * scale * 0.24,
                    height: candidateFrame.height * scale * 0.12
                ),
                scale: 8 * scale,
                effect: showsPixelateProperties ? .blur : .mosaic
            ))
        ]

        qqCaptureOverlay.begin(
            previewImages: previewImages,
            candidates: [candidate],
            initialSelections: isInteractive ? [:] : [
                primaryDisplayID: candidateFrame.offsetBy(
                    dx: -screenFrame.minX,
                    dy: -screenFrame.minY
                )
            ],
            initialAnnotations: isInteractive ? [:] : [
                primaryDisplayID: emphasizesScrollingAction ? [] : sampleAnnotations
            ],
            initialCursorPoints: isInteractive ? [
                primaryDisplayID: CGPoint(
                    x: screenFrame.width * 0.76,
                    y: screenFrame.height * 0.56
                )
            ] : [:],
            showsPropertiesInitially: !emphasizesScrollingAction && !isInteractive,
            showsPixelatePropertiesInitially: showsPixelateProperties,
            isInteractive: isInteractive,
            emphasizesScrollingAction: emphasizesScrollingAction
        ) { _ in }
    }

    private func openUIAcceptanceWindowSelection(fileURL: URL) {
        guard let backgroundImages = uiAcceptancePreviewImages(fileURL: fileURL),
              let primaryScreen = NSScreen.screens.first(where: {
                  abs($0.frame.minX) < 0.5 && abs($0.frame.minY) < 0.5
              }) ?? NSScreen.screens.first else {
            lastError = "无法准备窗口选择验收图片。"
            return
        }

        let screenFrame = primaryScreen.frame
        let backFrame = CGRect(
            x: screenFrame.minX + screenFrame.width * 0.16,
            y: screenFrame.minY + screenFrame.height * 0.20,
            width: screenFrame.width * 0.52,
            height: screenFrame.height * 0.48
        )
        let frontFrame = CGRect(
            x: screenFrame.minX + screenFrame.width * 0.32,
            y: screenFrame.minY + screenFrame.height * 0.30,
            width: screenFrame.width * 0.48,
            height: screenFrame.height * 0.46
        )
        let primaryHeight = screenFrame.height
        func screenCaptureKitFrame(from appKitFrame: CGRect) -> CGRect {
            CGRect(
                x: appKitFrame.minX,
                y: primaryHeight - appKitFrame.maxY,
                width: appKitFrame.width,
                height: appKitFrame.height
            )
        }

        let candidates = [
            WindowCaptureCandidate(
                id: 900_001,
                frame: screenCaptureKitFrame(from: frontFrame),
                processID: ProcessInfo.processInfo.processIdentifier,
                applicationName: "LocalShot 验收",
                title: "前景窗口"
            ),
            WindowCaptureCandidate(
                id: 900_002,
                frame: screenCaptureKitFrame(from: backFrame),
                processID: ProcessInfo.processInfo.processIdentifier,
                applicationName: "LocalShot 验收",
                title: "后方窗口"
            )
        ]
        let pointerLocation = CGPoint(
            x: frontFrame.intersection(backFrame).midX,
            y: frontFrame.intersection(backFrame).midY
        )

        windowSelectionOverlay.begin(
            candidates: candidates,
            backgroundImages: backgroundImages,
            initialPointerLocation: pointerLocation
        ) { [weak self] selectedID in
            guard let self,
                  let selectedID,
                  let selected = candidates.first(where: { $0.id == selectedID }) else {
                return
            }
            let confirmation = WindowCaptureCandidate(
                id: selected.id,
                frame: selected.frame,
                processID: selected.processID,
                applicationName: "已选择",
                title: selected.title
            )
            self.windowSelectionOverlay.begin(
                candidates: [confirmation],
                backgroundImages: backgroundImages,
                initialPointerLocation: pointerLocation,
                tracksPointer: false
            ) { _ in }
        }
    }

    private func uiAcceptancePreviewImages(
        fileURL: URL
    ) -> [CGDirectDisplayID: CGImage]? {
        guard let image = NSImage(contentsOf: fileURL) else {
            return nil
        }
        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard let sourceImage = image.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        ) else {
            return nil
        }

        return Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen in
            guard let displayID = screen.localShotDisplayID,
                  let scaledImage = uiAcceptancePreviewImage(
                      sourceImage,
                      for: screen
                  ) else {
                return nil
            }
            return (displayID, scaledImage)
        })
    }

    private func uiAcceptancePreviewImage(
        _ sourceImage: CGImage,
        for screen: NSScreen
    ) -> CGImage? {
        let scaleFactor = max(1, screen.backingScaleFactor)
        let width = max(1, Int((screen.frame.width * scaleFactor).rounded()))
        let height = max(1, Int((screen.frame.height * scaleFactor).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(
            sourceImage,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )
        return context.makeImage()
    }

    func chooseCaptureDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = fileStore.capturesDirectory
        panel.prompt = "选择"

        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else {
                return
            }
            do {
                let newStore = try CaptureFileStore(capturesDirectory: url)
                try self.settings.setCaptureDirectory(url)
                self.fileStore = newStore
                self.applyRetentionPolicy()
                self.refreshHistory()
            } catch {
                self.lastError = "无法使用所选截图目录：\(error.localizedDescription)"
            }
        }
    }

    func resetCaptureDirectory() {
        do {
            let newStore = try CaptureFileStore()
            settings.resetCaptureDirectory()
            fileStore = newStore
            applyRetentionPolicy()
            refreshHistory()
        } catch {
            lastError = "恢复默认截图目录失败：\(error.localizedDescription)"
        }
    }

    func applyRetentionPolicy() {
        guard settings.retentionDays > 0 else {
            return
        }
        do {
            let cutoff = Date().addingTimeInterval(
                -Double(settings.retentionDays) * 24 * 60 * 60
            )
            try fileStore.removeCaptures(olderThan: cutoff)
        } catch {
            lastError = "清理过期截图失败：\(error.localizedDescription)"
        }
    }

    func confirmAndClearHistory() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "清空保存记录？"
        alert.informativeText = "不勾选时只清空 LocalShot 内的截图和录屏记录，原文件继续保留。勾选后会永久删除当前目录中的全部 LocalShot 截图、对应标注项目和录屏文件，无法撤销。"
        let deleteFilesCheckbox = NSButton(
            checkboxWithTitle: "同时删除截图和录屏文件",
            target: nil,
            action: nil
        )
        deleteFilesCheckbox.state = .off
        alert.accessoryView = deleteFilesCheckbox
        alert.addButton(withTitle: "清空记录")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        do {
            if deleteFilesCheckbox.state == .on {
                try fileStore.removeAllCaptures()
                try ScreenRecordingFileStore(
                    recordingsDirectory: fileStore.capturesDirectory
                ).removeAllRecordings()
                settings.removeHiddenRecentSaveRecords(
                    in: fileStore.capturesDirectory
                )
            } else {
                settings.hideRecentSaveRecords(recentSaveItems.map(\.url))
            }
            refreshHistory()
            historySearchModel.synchronize(assets: [])
        } catch {
            lastError = "清空保存记录失败：\(error.localizedDescription)"
        }
    }

    func openScreenCaptureSettings() {
        ScreenCapturePermission.openSystemSettings()
    }

    func openMicrophoneSettings() {
        MicrophonePermission.openSystemSettings()
    }

    func restorePinnedScreenshotInteraction() {
        pinnedScreenshotController.restoreInteraction()
    }

    func closeAllPinnedScreenshots() {
        pinnedScreenshotController.closeAll()
    }

    private func openAnnotationEditor(_ asset: CaptureAsset) {
        quickAccessPanel.dismiss()
        annotationEditor.open(asset: asset) { [weak self] message in
            self?.lastError = message
        }
    }

    private func openOCRResult(_ asset: CaptureAsset) {
        quickAccessPanel.dismiss()
        ocrResultController.open(asset: asset)
    }

    private func openImageBeautifier(_ asset: CaptureAsset) {
        quickAccessPanel.dismiss()
        imageBeautifierController.open(asset: asset) { [weak self] message in
            self?.lastError = message
        }
    }

    private func pinScreenshot(_ asset: CaptureAsset) {
        quickAccessPanel.dismiss()
        pinnedScreenshotController.open(asset: asset) { [weak self] message in
            self?.lastError = message
        }
    }

    private func openTranslationResult(_ asset: CaptureAsset) {
        quickAccessPanel.dismiss()
        translationResultController.open(asset: asset) { [weak self] message in
            self?.lastError = message
        }
    }

    private func copyToClipboard(_ asset: CaptureAsset) {
        guard let image = NSImage(contentsOf: asset.url) else {
            lastError = "无法读取截图文件。"
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if !pasteboard.writeObjects([image]) {
            lastError = "复制到剪贴板失败。"
        }
    }

    private func nextCaptureURL(mode: CaptureMode) -> URL {
        fileStore.nextCaptureURL(
            mode: mode,
            format: settings.outputFormat,
            filenamePrefix: settings.filenamePrefix
        )
    }

    private func chooseLocalImage(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            completion(url)
        }
    }

    private func importedAsset(_ url: URL) -> CaptureAsset {
        CaptureAsset(
            url: url,
            createdAt: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .now,
            mode: .area
        )
    }

    private func saveAs(_ asset: CaptureAsset) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: asset.url.pathExtension) ?? .png
        ]
        panel.nameFieldStringValue = asset.url.lastPathComponent
        panel.canCreateDirectories = true

        panel.begin { [weak self] response in
            guard response == .OK, let destination = panel.url else {
                return
            }
            do {
                try LocalFileExporter.exportCopy(from: asset.url, to: destination)
            } catch {
                Task { @MainActor in
                    self?.lastError = "另存为失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func revealInFinder(_ asset: CaptureAsset) {
        NSWorkspace.shared.activateFileViewerSelecting([asset.url])
    }

    private func delete(_ asset: CaptureAsset) {
        do {
            try fileStore.delete(asset)
            historySearchModel.removeRecord(for: asset)
            quickAccessPanel.dismiss()
            refreshHistory()
        } catch {
            lastError = "删除截图失败：\(error.localizedDescription)"
        }
    }
}

@available(macOS 15.0, *)
private struct RecordingWindowLockAcceptanceView: View {
    @ObservedObject var controller: ScreenRecordingController
    let showsTestControls: Bool
    let onMove: () -> Void
    let onResize: () -> Void
    let onHideBriefly: () -> Void
    let onSimulateSleep: () -> Void
    let onSimulateLowStorage: () -> Void
    let onSimulateGlobalStop: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.rectangle")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.blue)
            Text("拖动或缩放这个窗口")
                .font(.title2.weight(.semibold))
            Text("红色边框、录屏内容和控制条应始终跟随窗口")
                .foregroundStyle(.secondary)
            ScreenRecordingControlView(controller: controller)
                .frame(width: 448, height: 50)
            if showsTestControls {
                HStack(spacing: 10) {
                    Button("右移 160 点", action: onMove)
                    Button("放大窗口", action: onResize)
                    Button("短暂隐藏", action: onHideBriefly)
                    Button("模拟睡眠", action: onSimulateSleep)
                }
                HStack(spacing: 10) {
                    Button(controller.pauseButtonLabel) {
                        controller.togglePause()
                    }
                    .disabled(!controller.canTogglePause)
                    Button("模拟低磁盘", action: onSimulateLowStorage)
                        .disabled(!controller.isRecording)
                    Button("模拟全局停止", action: onSimulateGlobalStop)
                        .disabled(!controller.isRecording && !controller.isPaused)
                    Button(controller.primaryButtonTitle) {
                        controller.performPrimaryAction()
                    }
                    .tint(controller.isRecording ? .red : .blue)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
