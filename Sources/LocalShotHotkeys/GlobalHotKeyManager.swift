import Carbon
import LocalShotCore

private let localShotHotKeyHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else {
        return OSStatus(eventNotHandledErr)
    }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else {
        return status
    }

    let manager = Unmanaged<GlobalHotKeyManager>
        .fromOpaque(userData)
        .takeUnretainedValue()

    Task { @MainActor in
        manager.handleHotKey(id: hotKeyID.id)
    }
    return noErr
}

@MainActor
public final class GlobalHotKeyManager: @unchecked Sendable {
    private let signature: OSType = 0x4C534854 // LSHT
    private var eventHandler: EventHandlerRef?
    private var hotKeyReferences: [HotKeyAction: EventHotKeyRef] = [:]
    private var registeredActions: [UInt32: HotKeyAction] = [:]
    private var screenRecordingStopHotKey: EventHotKeyRef?
    private var currentConfiguration: HotKeyConfiguration?

    public var onCapture: ((CaptureMode) -> Void)?
    public var onRecognizeText: (() -> Void)?
    public var onStopScreenRecording: (() -> Void)?

    public var isStarted: Bool {
        eventHandler != nil
    }

    public var registeredActionCount: Int {
        hotKeyReferences.count
    }

    public var isScreenRecordingStopEnabled: Bool {
        screenRecordingStopHotKey != nil
    }

    public init() {}

    public func start(configuration: HotKeyConfiguration) throws {
        if eventHandler != nil {
            try apply(configuration)
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            localShotHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard handlerStatus == noErr else {
            eventHandler = nil
            throw GlobalHotKeyManagerError.eventHandlerInstallationFailed
        }

        do {
            try apply(configuration)
        } catch {
            stop()
            throw error
        }
    }

    public func apply(_ configuration: HotKeyConfiguration) throws {
        if let invalidAction = configuration.invalidActions.first {
            throw GlobalHotKeyManagerError.invalidShortcut(invalidAction)
        }
        if let conflict = configuration.conflicts.first {
            throw GlobalHotKeyManagerError.duplicateShortcut(conflict)
        }

        let previous = currentConfiguration
        unregisterHotKeys()
        do {
            try register(configuration)
            currentConfiguration = configuration
        } catch {
            unregisterHotKeys()
            if let previous {
                do {
                    try register(previous)
                    currentConfiguration = previous
                } catch {
                    currentConfiguration = nil
                    throw GlobalHotKeyManagerError.rollbackFailed
                }
            }
            throw error
        }
    }

    public func stop() {
        try? setScreenRecordingStopEnabled(false)
        unregisterHotKeys()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        eventHandler = nil
        currentConfiguration = nil
    }

    public func setScreenRecordingStopEnabled(_ enabled: Bool) throws {
        if !enabled {
            if let screenRecordingStopHotKey {
                UnregisterEventHotKey(screenRecordingStopHotKey)
            }
            screenRecordingStopHotKey = nil
            return
        }
        guard screenRecordingStopHotKey == nil else { return }
        guard eventHandler != nil else {
            throw GlobalHotKeyManagerError.eventHandlerInstallationFailed
        }

        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(
            signature: signature,
            id: Self.screenRecordingStopHotKeyID
        )
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_R),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else {
            throw GlobalHotKeyManagerError.screenRecordingStopRegistrationFailed
        }
        screenRecordingStopHotKey = reference
    }

    private func register(_ configuration: HotKeyConfiguration) throws {
        for action in HotKeyAction.allCases {
            guard let shortcut = configuration.shortcut(for: action) else {
                continue
            }
            var reference: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: signature, id: action.hotKeyID)
            let status = RegisterEventHotKey(
                shortcut.keyCode,
                carbonModifiers(for: shortcut.modifiers),
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &reference
            )
            guard status == noErr, let reference else {
                throw GlobalHotKeyManagerError.registrationFailed(action, shortcut)
            }
            hotKeyReferences[action] = reference
            registeredActions[action.hotKeyID] = action
        }
    }

    func handleHotKey(id: UInt32) {
        if id == Self.screenRecordingStopHotKeyID {
            onStopScreenRecording?()
            return
        }
        guard let action = registeredActions[id] else {
            return
        }
        switch action {
        case .area:
            onCapture?(.area)
        case .window:
            onCapture?(.window)
        case .fullScreen:
            onCapture?(.fullScreen)
        case .recognizeText:
            onRecognizeText?()
        }
    }

    private func unregisterHotKeys() {
        for reference in hotKeyReferences.values {
            UnregisterEventHotKey(reference)
        }
        hotKeyReferences.removeAll()
        registeredActions.removeAll()
    }

    private func carbonModifiers(for modifiers: HotKeyModifiers) -> UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    private static let screenRecordingStopHotKeyID: UInt32 = 100
}

private extension HotKeyAction {
    var hotKeyID: UInt32 {
        switch self {
        case .area: 1
        case .window: 2
        case .fullScreen: 3
        case .recognizeText: 5
        }
    }
}

private enum GlobalHotKeyManagerError: LocalizedError {
    case eventHandlerInstallationFailed
    case invalidShortcut(HotKeyAction)
    case duplicateShortcut(HotKeyConflict)
    case registrationFailed(HotKeyAction, HotKeyShortcut)
    case screenRecordingStopRegistrationFailed
    case rollbackFailed

    var errorDescription: String? {
        switch self {
        case .eventHandlerInstallationFailed:
            "无法启动全局快捷键监听。"
        case let .invalidShortcut(action):
            "“\(action.displayName)”快捷键无效，请至少使用 ⌘、⌥ 或 ⌃ 中的一个修饰键。"
        case let .duplicateShortcut(conflict):
            "“\(conflict.first.displayName)”和“\(conflict.second.displayName)”不能同时使用 \(conflict.shortcut.displayString)。"
        case let .registrationFailed(action, shortcut):
            "无法注册“\(action.displayName)”的 \(shortcut.displayString)，它可能已被系统或其他应用占用。"
        case .screenRecordingStopRegistrationFailed:
            "无法注册录制停止快捷键 ⌘⇧R，它可能已被系统或其他应用占用。"
        case .rollbackFailed:
            "快捷键更新失败，而且无法恢复上一组快捷键。请重新启动 LocalShot。"
        }
    }
}
