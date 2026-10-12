import Foundation
import LocalShotCore
import LocalShotHotkeys

enum HotKeyCheckError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message): message
        }
    }
}

@main
struct LocalShotHotKeyCheck {
    @MainActor
    static func main() {
        let manager = GlobalHotKeyManager()
        do {
            let modifiers: HotKeyModifiers = [.command, .option, .control, .shift]
            var configuration = HotKeyConfiguration(
                area: HotKeyShortcut(keyCode: 105, modifiers: modifiers),
                window: HotKeyShortcut(keyCode: 107, modifiers: modifiers),
                fullScreen: HotKeyShortcut(keyCode: 113, modifiers: modifiers),
                recognizeText: HotKeyShortcut(keyCode: 109, modifiers: modifiers)
            )
            try manager.start(configuration: configuration)
            guard manager.isStarted, manager.registeredActionCount == 4 else {
                throw HotKeyCheckError.failed("四个 Carbon 快捷键没有全部注册")
            }

            configuration.setShortcut(nil, for: .recognizeText)
            try manager.apply(configuration)
            guard manager.registeredActionCount == 3 else {
                throw HotKeyCheckError.failed("禁用快捷键后仍保留注册")
            }

            try manager.setScreenRecordingStopEnabled(true)
            guard manager.isScreenRecordingStopEnabled else {
                throw HotKeyCheckError.failed("录制期间的 ⌘⇧R 停止快捷键没有注册")
            }
            try manager.setScreenRecordingStopEnabled(false)
            guard !manager.isScreenRecordingStopEnabled else {
                throw HotKeyCheckError.failed("录制结束后仍残留 ⌘⇧R 停止快捷键")
            }

            var conflicting = configuration
            conflicting.setShortcut(configuration.area, for: .window)
            do {
                try manager.apply(conflicting)
                throw HotKeyCheckError.failed("重复快捷键配置被错误接受")
            } catch let error as HotKeyCheckError {
                throw error
            } catch {
                guard manager.registeredActionCount == 3 else {
                    throw HotKeyCheckError.failed("冲突配置破坏了原有快捷键注册")
                }
            }

            try manager.setScreenRecordingStopEnabled(true)
            manager.stop()
            guard !manager.isStarted,
                  manager.registeredActionCount == 0,
                  !manager.isScreenRecordingStopEnabled else {
                throw HotKeyCheckError.failed("停止后仍残留 Carbon 快捷键")
            }
            print("LocalShotHotKeyCheck: PASS")
        } catch {
            manager.stop()
            fputs("LocalShotHotKeyCheck: FAIL - \(error)\n", stderr)
            exit(1)
        }
    }
}
