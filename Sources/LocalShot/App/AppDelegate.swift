import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    #if !APP_STORE
    private var updateCheckTimer: Timer?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        scheduleUIAcceptanceRequest()
        #if !APP_STORE
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.model.checkForUpdatesAutomaticallyIfNeeded()
        }
        let timer = Timer(timeInterval: 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.model.checkForUpdatesAutomaticallyIfNeeded()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        updateCheckTimer = timer
        #endif
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        guard !model.isCapturing else {
            return true
        }
        sender.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            sender.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        return true
    }

    private func scheduleUIAcceptanceRequest() {
        let arguments = CommandLine.arguments
        guard let action = value(after: "--ui-acceptance-action", in: arguments),
              let filePath = value(after: "--ui-acceptance-file", in: arguments) else {
            return
        }
        let fileURL = URL(fileURLWithPath: filePath)
        let delay = value(after: "--ui-acceptance-delay", in: arguments)
            .flatMap(Double.init)
            .map { max(0, $0) } ?? 0
        guard delay > 0 else {
            model.openUIAcceptance(action: action, fileURL: fileURL)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.model.openUIAcceptance(action: action, fileURL: fileURL)
        }
    }

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

}
