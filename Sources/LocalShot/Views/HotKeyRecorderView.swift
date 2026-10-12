import AppKit
import LocalShotCore
import SwiftUI

struct HotKeyRecorderView: NSViewRepresentable {
    let action: HotKeyAction
    let shortcut: HotKeyShortcut?
    let onChange: (HotKeyShortcut?) -> Void

    func makeNSView(context: Context) -> HotKeyRecorderButton {
        let button = HotKeyRecorderButton()
        button.configure(action: action, shortcut: shortcut, onChange: onChange)
        return button
    }

    func updateNSView(_ nsView: HotKeyRecorderButton, context: Context) {
        nsView.configure(action: action, shortcut: shortcut, onChange: onChange)
    }

    static func dismantleNSView(_ nsView: HotKeyRecorderButton, coordinator: ()) {
        nsView.stopRecording()
    }
}

final class HotKeyRecorderButton: NSButton {
    private var shortcut: HotKeyShortcut?
    private var actionName = "快捷键"
    private var onChange: ((HotKeyShortcut?) -> Void)?
    private var eventMonitor: Any?
    private(set) var isRecordingShortcut = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setButtonType(.momentaryPushIn)
        bezelStyle = .rounded
        alignment = .center
        font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        target = self
        action = #selector(beginRecording)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(greaterThanOrEqualToConstant: 128).isActive = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(
        action: HotKeyAction,
        shortcut: HotKeyShortcut?,
        onChange: @escaping (HotKeyShortcut?) -> Void
    ) {
        actionName = action.displayName
        self.shortcut = shortcut
        self.onChange = onChange
        if !isRecordingShortcut {
            refreshTitle()
        }
        setAccessibilityLabel("设置\(action.displayName)快捷键")
        setAccessibilityValue(self.title)
        setAccessibilityHelp("点击后按新的组合键，按 Escape 取消，按 Delete 清除。")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopRecording()
        }
    }

    @objc private func beginRecording() {
        guard !isRecordingShortcut else {
            stopRecording()
            return
        }
        isRecordingShortcut = true
        title = "请按快捷键…"
        setAccessibilityValue(title)
        window?.makeFirstResponder(self)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    func stopRecording() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        isRecordingShortcut = false
        refreshTitle()
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard isRecordingShortcut else {
            return event
        }
        if event.keyCode == 53 {
            stopRecording()
            return nil
        }

        let modifiers = hotKeyModifiers(from: event.modifierFlags)
        if (event.keyCode == 51 || event.keyCode == 117), modifiers.isEmpty {
            let callback = onChange
            stopRecording()
            callback?(nil)
            return nil
        }

        let candidate = HotKeyShortcut(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers
        )
        guard candidate.isValid else {
            NSSound.beep()
            title = "需包含 ⌘、⌥ 或 ⌃"
            setAccessibilityValue(title)
            return nil
        }

        let callback = onChange
        stopRecording()
        callback?(candidate)
        return nil
    }

    private func refreshTitle() {
        title = shortcut?.displayString ?? "未设置"
        toolTip = "\(actionName)：\(title)。点击录制，Escape 取消，Delete 清除。"
        setAccessibilityValue(title)
    }

    private func hotKeyModifiers(from flags: NSEvent.ModifierFlags) -> HotKeyModifiers {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var result: HotKeyModifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
        return result
    }
}
