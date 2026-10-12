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

    var body: some View {
        Form {
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
                        set: { value in
                            settings.retentionDays = value
                            model.applyRetentionPolicy()
                            model.refreshHistory()
                        }
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

            Section("隐私") {
                Text("截图、区域录屏、OCR、翻译、历史和编辑都在本机完成。应用不包含账号、同步或云上传服务。")
                    .foregroundStyle(.secondary)

                if let privacyStatementURL {
                    Button("查看随应用附带的隐私说明", systemImage: "hand.raised") {
                        NSWorkspace.shared.open(privacyStatementURL)
                    }
                }
            }

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
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 660, height: 760)
        .onAppear {
            model.refreshPermissionStates()
            model.refreshLaunchAtLoginState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermissionStates()
            model.refreshLaunchAtLoginState()
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
