import AppKit
import LocalShotCore
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: AppSettings

    init(model: AppModel) {
        self.model = model
        _settings = ObservedObject(wrappedValue: model.settings)
    }

    var body: some View {
        Section("功能") {
            ForEach(menuCaptureModes, id: \.self) { mode in
                Button {
                    model.capture(mode)
                } label: {
                    HStack {
                        Label(mode.displayName, systemImage: mode.symbolName)
                        Spacer()
                        if !shortcutText(for: mode).isEmpty {
                            Text(shortcutText(for: mode))
                        }
                    }
                }
                .disabled(model.isCapturing)
            }

            Button {
                model.recognizeScreenText()
            } label: {
                HStack {
                    Label("识别文字", systemImage: "text.viewfinder")
                    Spacer()
                    if !shortcutText(for: .recognizeText).isEmpty {
                        Text(shortcutText(for: .recognizeText))
                    }
                }
            }
            .disabled(model.isCapturing)

            Button("区域录屏", systemImage: "record.circle") {
                model.beginScreenRecording()
            }
            .disabled(model.isCapturing)
        }
        .onAppear {
            model.refreshPermissionStates()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermissionStates()
        }

        if model.isCapturing {
            Text("正在截图或录制…")
        }

        if model.hasPinnedScreenshots {
            Section("置顶截图") {
                Button("恢复全部窗口交互", systemImage: "cursorarrow") {
                    model.restorePinnedScreenshotInteraction()
                }

                Button("关闭全部置顶截图", systemImage: "xmark.rectangle") {
                    model.closeAllPinnedScreenshots()
                }
            }
        }

        Section("最近保存") {
            if model.recentSaveItems.isEmpty {
                Text("暂无保存记录")
            } else {
                ForEach(model.recentSaveItems.prefix(5)) { item in
                    Button {
                        model.openRecentSave(item)
                    } label: {
                        Label(
                            item.createdAt.formatted(date: .omitted, time: .shortened),
                            systemImage: item.symbolName
                        )
                        .accessibilityLabel(
                            "\(item.accessibilityName) \(item.createdAt.formatted(date: .omitted, time: .shortened))"
                        )
                    }
                }
            }

            Button("打开目录", systemImage: "folder") {
                model.openCaptureDirectory()
            }

            Button("清空记录…", systemImage: "trash") {
                model.confirmAndClearHistory()
            }
            .disabled(model.recentSaveItems.isEmpty)
        }

        Section("本地图片") {
            Button("导入图片进行标注…", systemImage: "pencil.and.outline") {
                model.importImageForAnnotation()
            }
            Button("导入图片识别文字…", systemImage: "text.viewfinder") {
                model.importImageForOCR()
            }
            Button("导入图片原位置翻译…", systemImage: "character.bubble") {
                model.importImageForTranslation()
            }
            Button("导入图片进行美化…", systemImage: "sparkles") {
                model.importImageForBeautification()
            }
        }
        if !model.hasScreenCapturePermission {
            Section("权限") {
                Button("打开屏幕捕获设置", systemImage: "lock.shield") {
                    model.openScreenCaptureSettings()
                }
            }
        }

        if let error = model.lastError {
            Section("状态") {
                Text(error)
            }
        }

        Divider()

        Button("设置…", systemImage: "gearshape") {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }

        Button("退出 LocalShot", systemImage: "power") {
            NSApp.terminate(nil)
        }
    }

    private func shortcutText(for mode: CaptureMode) -> String {
        let action: HotKeyAction?
        switch mode {
        case .area: action = .area
        case .window: action = .window
        case .fullScreen: action = .fullScreen
        case .scrolling: action = nil
        }
        return action.map(shortcutText(for:)) ?? ""
    }

    private var menuCaptureModes: [CaptureMode] {
        [.area, .window, .fullScreen]
    }

    private func shortcutText(for action: HotKeyAction) -> String {
        settings.hotKeyConfiguration.shortcut(for: action)?.displayString ?? ""
    }
}
