import AppKit
import LocalShotCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: AppSettings
    #if !APP_STORE
    @ObservedObject private var updateController: UpdateController
    #endif

    init(model: AppModel) {
        self.model = model
        _settings = ObservedObject(wrappedValue: model.settings)
        #if !APP_STORE
        _updateController = ObservedObject(wrappedValue: model.updateController)
        #endif
    }

    @StateObject private var tabSelection = SettingsTabSelection()
    @Namespace private var tabNamespace

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
                .padding(.top, 10)
                .padding(.bottom, 2)
            Form {
                switch tabSelection.tab {
                case .general: generalSections
                case .capture: captureSections
                case .hotKeys: hotKeySection
                case .storage: storageSections
                case .about: aboutSection
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .ignoresSafeArea(edges: .top)
        .background(LocalShotBackground().ignoresSafeArea())
        .background(SettingsWindowConfigurator())
        .toolbarBackground(.hidden, for: .windowToolbar)
        .modifier(HiddenWindowTitle())
        .tint(LocalShotTheme.accent)
        .frame(width: 620, height: 640)
        .onAppear {
            model.refreshPermissionStates()
            model.refreshLaunchAtLoginState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermissionStates()
            model.refreshLaunchAtLoginState()
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 22, height: 22)
            Text("LocalShot")
                .font(.system(size: 15, weight: .bold))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(SettingsTab.allCases) { tab in
                let isSelected = tabSelection.tab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        tabSelection.tab = tab
                    }
                } label: {
                    Label(tab.title, systemImage: tab.symbolName)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(LocalShotTheme.accent)
                                    .matchedGeometryEffect(id: "selectedTab", in: tabNamespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background {
            Capsule()
                .fill(LocalShotTheme.card.opacity(0.75))
                .overlay(Capsule().strokeBorder(LocalShotTheme.cardStroke, lineWidth: 1))
                .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        }
    }

    @ViewBuilder
    private var generalSections: some View {
        Section("权限") {
            LabeledContent("屏幕捕获") {
                Label(
                    model.hasScreenCapturePermission ? "已允许" : "未允许",
                    systemImage: model.hasScreenCapturePermission
                        ? "checkmark.circle.fill"
                        : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(model.hasScreenCapturePermission ? .green : .orange)
            }

            if !model.hasScreenCapturePermission {
                Button("打开系统设置") {
                    model.openScreenCaptureSettings()
                }
            }

            if #available(macOS 15.0, *) {
                LabeledContent("麦克风") {
                    Label(
                        model.microphonePermissionStatus.displayName,
                        systemImage: model.microphonePermissionStatus.isGranted
                            ? "checkmark.circle.fill"
                            : "mic.slash.fill"
                    )
                    .foregroundStyle(
                        model.microphonePermissionStatus.isGranted ? .green : .secondary
                    )
                }

                Button("打开麦克风设置") {
                    model.openMicrophoneSettings()
                }

                Text("只有你在区域录屏控制条中主动开启麦克风时，LocalShot 才会请求并录制麦克风声音。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Section("通用") {
            Toggle(
                "登录时自动启动 LocalShot",
                isOn: Binding(
                    get: { model.launchAtLoginState.isRequested },
                    set: { model.setLaunchAtLoginEnabled($0) }
                )
            )
            .disabled(model.launchAtLoginState == .unavailable)

            LabeledContent("登录项状态") {
                Label(
                    model.launchAtLoginState.displayName,
                    systemImage: launchAtLoginSymbol
                )
                .foregroundStyle(launchAtLoginColor)
            }

            if model.launchAtLoginState == .requiresApproval {
                Text("macOS 需要你在“系统设置 → 通用 → 登录项与扩展”中允许 LocalShot。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("打开登录项设置") {
                    model.openLoginItemsSettings()
                }
            } else if model.launchAtLoginState == .unavailable {
                Text("系统当前无法注册此应用。请确认 LocalShot.app 位于“应用程序”文件夹；正式发布包还需要有效的 Developer ID 签名。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = model.launchAtLoginErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }

        Section("快速访问") {
            Picker("自动关闭", selection: $settings.quickAccessDuration) {
                Text("不自动关闭").tag(0.0)
                Text("5 秒").tag(5.0)
                Text("10 秒").tag(10.0)
                Text("15 秒").tag(15.0)
                Text("30 秒").tag(30.0)
            }
        }

        if model.hasPinnedScreenshots {
            Section("置顶截图") {
                Text("开启点击穿透后，可在这里恢复全部置顶窗口的交互。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("恢复全部窗口交互", systemImage: "cursorarrow") {
                        model.restorePinnedScreenshotInteraction()
                    }
                    Button("关闭全部置顶截图", systemImage: "xmark.rectangle") {
                        model.closeAllPinnedScreenshots()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var captureSections: some View {
        Section("截图输出") {
            Picker("文件格式", selection: $settings.outputFormat) {
                ForEach(CaptureOutputFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }

            if settings.outputFormat == .jpeg {
                LabeledContent("JPEG 质量") {
                    HStack {
                        Slider(value: $settings.jpegQuality, in: 0.4...1, step: 0.05)
                            .frame(width: 180)
                            .accessibilityLabel("JPEG 质量")
                        Text("\(Int(settings.jpegQuality * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 42, alignment: .trailing)
                    }
                }
            }

            TextField("文件名前缀", text: $settings.filenamePrefix)
            Toggle("截图中包含鼠标光标", isOn: $settings.includesCursor)
            Toggle("窗口截图保留阴影", isOn: $settings.includesWindowShadow)
            Toggle("截图时隐藏 LocalShot 自己的窗口", isOn: $settings.hidesOwnWindowsWhenCapturing)
            Text("关闭后，区域、窗口和全屏截图会包含设置、置顶截图等 LocalShot 窗口；识别文字和录屏仍会隐藏。需要 macOS 14 或更高版本。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if #available(macOS 15.0, *) {
            Section("屏幕录制") {
                Picker("画质", selection: $settings.screenRecordingQuality) {
                    ForEach(ScreenRecordingQuality.allCases) { quality in
                        Text(quality.displayName).tag(quality)
                    }
                }

                Picker("帧率", selection: $settings.screenRecordingFrameRate) {
                    ForEach(ScreenRecordingFrameRate.allCases) { frameRate in
                        Text(frameRate.displayName).tag(frameRate)
                    }
                }

                Text("录制控制条也可临时调整；录制中可用 ⌘⇧R 全局停止。文件大小会随画面变化而波动，因此显示估算范围；磁盘空间达到安全线时会自动停止并保存。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var hotKeySection: some View {
        Section("快捷键") {
            Text("默认区域截图使用 ⌘⌃A，识别文字使用全局 ⌘⇧O；LocalShot 运行时，⌘⇧O 会优先触发文字框选。如果默认区域快捷键被占用，会自动改用 ⌃⌥1。")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(HotKeyAction.allCases) { action in
                LabeledContent(action.displayName) {
                    HotKeyRecorderView(
                        action: action,
                        shortcut: settings.hotKeyConfiguration.shortcut(for: action)
                    ) { shortcut in
                        model.updateHotKey(shortcut, for: action)
                    }
                }
            }

            Text("点击组合键后直接按新快捷键；Esc 取消，Delete 清除。内部重复或系统拒绝注册时会保留原快捷键。macOS 不提供完整的第三方快捷键占用查询，如同时触发其他应用，请改用另一个组合键。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let error = model.hotKeyErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("快捷键错误：\(error)")
            }

            Button("恢复默认快捷键") {
                model.resetHotKeys()
            }
        }
    }

    @ViewBuilder
    private var storageSections: some View {
        Section("本地存储") {
            LabeledContent("截图与录屏目录") {
                Text(model.fileStore.capturesDirectory.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            HStack {
                Button("选择目录…") {
                    model.chooseCaptureDirectory()
                }
                Button("恢复默认") {
                    model.resetCaptureDirectory()
                }
                Spacer()
                Button("在 Finder 中打开") {
                    model.openCaptureDirectory()
                }
            }

            Picker(
                "自动清理",
                selection: Binding(
                    get: { settings.retentionDays },
                    set: { model.setRetentionDays($0) }
                )
            ) {
                Text("1 天后").tag(1)
                Text("7 天后").tag(7)
                Text("30 天后").tag(30)
                Text("永久保留").tag(0)
            }

            Text("LocalShot 只管理自己生成的时间戳截图和录屏，不会把目录中的其他图片或视频加入记录或自动删除。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("清空全部保存记录…", role: .destructive) {
                model.confirmAndClearHistory()
            }
        }

        Section("隐私") {
            Text("截图、区域录屏、OCR、翻译、历史和编辑都在本机完成。应用不包含账号、同步或云上传服务。")
                .foregroundStyle(.secondary)

            if let privacyStatementURL {
                Button("查看随应用附带的隐私说明", systemImage: "hand.raised") {
                    NSWorkspace.shared.open(privacyStatementURL)
                }
            }
        }
    }

    private var aboutSection: some View {
        Section("关于") {
            LabeledContent("版本", value: versionDisplayName)
            LabeledContent("更新方式", value: DistributionChannel.updateMethod)

            Text(DistributionChannel.updateDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            #if !APP_STORE
            Toggle(
                "自动检查更新",
                isOn: Binding(
                    get: { settings.automaticallyChecksForUpdates },
                    set: { enabled in
                        settings.automaticallyChecksForUpdates = enabled
                        if enabled {
                            updateController.checkManually()
                        }
                    }
                )
            )

            HStack {
                Button("检查更新", systemImage: "arrow.clockwise") {
                    updateController.checkManually()
                }
                .disabled(updateController.isBusy)

                if updateController.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }

                if updateController.canDownloadAvailableRelease {
                    Button("下载并打开更新", systemImage: "arrow.down.circle") {
                        updateController.downloadAvailableRelease()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(updateController.isBusy)
                }
            }

            Text(updateController.statusMessage)
                .font(.caption)
                .foregroundStyle(updateController.statusIsError ? Color.red : Color.secondary)
                .textSelection(.enabled)

            Text("自动检查只访问公开 GitHub Release，不上传截图、录屏、识别内容、文件路径或使用记录。")
                .font(.caption)
                .foregroundStyle(.secondary)
            #endif
        }
    }

    private var launchAtLoginSymbol: String {
        switch model.launchAtLoginState {
        case .disabled: "circle"
        case .enabled: "checkmark.circle.fill"
        case .requiresApproval: "clock.badge.exclamationmark"
        case .unavailable: "xmark.circle"
        }
    }

    private var launchAtLoginColor: Color {
        switch model.launchAtLoginState {
        case .disabled: .secondary
        case .enabled: .green
        case .requiresApproval: .orange
        case .unavailable: .secondary
        }
    }

    private var versionDisplayName: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "开发构建"
        guard let build = info?["CFBundleVersion"] as? String,
              !build.isEmpty else {
            return version
        }
        return "\(version) (\(build))"
    }

    private var privacyStatementURL: URL? {
        Bundle.main.url(forResource: "PRIVACY", withExtension: "md")
    }
}

@MainActor
private final class SettingsTabSelection: ObservableObject {
    @Published var tab: SettingsTab = .general
}

private enum SettingsTab: CaseIterable, Identifiable {
    case general
    case capture
    case hotKeys
    case storage
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "通用"
        case .capture: "截图与录屏"
        case .hotKeys: "快捷键"
        case .storage: "存储与隐私"
        case .about: "关于"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .capture: "camera.viewfinder"
        case .hotKeys: "keyboard"
        case .storage: "externaldrive"
        case .about: "info.circle"
        }
    }
}

private struct HiddenWindowTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbar(removing: .title)
        } else {
            content
        }
    }
}

private struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ConfiguringView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ConfiguringView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else {
                return
            }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
        }

        override func viewWillDraw() {
            super.viewWillDraw()
            if window?.titleVisibility != .hidden {
                window?.titleVisibility = .hidden
            }
        }
    }
}
