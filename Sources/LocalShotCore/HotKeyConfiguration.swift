import Foundation

public struct HotKeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let command = HotKeyModifiers(rawValue: 1 << 0)
    public static let option = HotKeyModifiers(rawValue: 1 << 1)
    public static let control = HotKeyModifiers(rawValue: 1 << 2)
    public static let shift = HotKeyModifiers(rawValue: 1 << 3)

    public var containsPrimaryModifier: Bool {
        !intersection([.command, .option, .control]).isEmpty
    }

    public var displayString: String {
        var value = ""
        if contains(.command) { value += "⌘" }
        if contains(.control) { value += "⌃" }
        if contains(.option) { value += "⌥" }
        if contains(.shift) { value += "⇧" }
        return value
    }
}

public struct HotKeyShortcut: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: HotKeyModifiers

    public init(keyCode: UInt32, modifiers: HotKeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var isValid: Bool {
        modifiers.containsPrimaryModifier && !Self.modifierKeyCodes.contains(keyCode)
    }

    public var displayString: String {
        modifiers.displayString + Self.keyLabel(for: keyCode)
    }

    private static let modifierKeyCodes: Set<UInt32> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    private static func keyLabel(for keyCode: UInt32) -> String {
        let labels: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G",
            6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
            12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
            18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
            24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
            36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
            42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
            48: "⇥", 49: "空格", 50: "`", 51: "⌫", 53: "Esc",
            64: "F17", 79: "F18", 80: "F19", 90: "F20",
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
            101: "F9", 103: "F11", 105: "F13", 106: "F16", 107: "F14",
            109: "F10", 111: "F12", 113: "F15", 114: "帮助",
            115: "↖", 116: "⇞", 117: "⌦", 118: "F4", 119: "↘",
            120: "F2", 121: "⇟", 122: "F1", 123: "←", 124: "→",
            125: "↓", 126: "↑"
        ]
        return labels[keyCode] ?? "键\(keyCode)"
    }
}

public enum HotKeyAction: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case area
    case window
    case fullScreen
    case recognizeText

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .area: "区域截图"
        case .window: "窗口截图"
        case .fullScreen: "全屏截图"
        case .recognizeText: "识别文字"
        }
    }
}

public struct HotKeyConflict: Hashable, Sendable {
    public let first: HotKeyAction
    public let second: HotKeyAction
    public let shortcut: HotKeyShortcut

    public init(first: HotKeyAction, second: HotKeyAction, shortcut: HotKeyShortcut) {
        self.first = first
        self.second = second
        self.shortcut = shortcut
    }
}

public struct HotKeyConfiguration: Codable, Hashable, Sendable {
    public var area: HotKeyShortcut?
    public var window: HotKeyShortcut?
    public var fullScreen: HotKeyShortcut?
    public var recognizeText: HotKeyShortcut?

    public init(
        area: HotKeyShortcut? = nil,
        window: HotKeyShortcut? = nil,
        fullScreen: HotKeyShortcut? = nil,
        recognizeText: HotKeyShortcut? = nil
    ) {
        self.area = area
        self.window = window
        self.fullScreen = fullScreen
        self.recognizeText = recognizeText
    }

    public static let `default` = HotKeyConfiguration(
        area: HotKeyShortcut(keyCode: 0, modifiers: [.command, .control]),
        window: HotKeyShortcut(keyCode: 19, modifiers: [.control, .option]),
        fullScreen: HotKeyShortcut(keyCode: 20, modifiers: [.control, .option]),
        recognizeText: HotKeyShortcut(keyCode: 31, modifiers: [.command, .shift])
    )

    public static let conflictSafe = HotKeyConfiguration(
        area: HotKeyShortcut(keyCode: 18, modifiers: [.control, .option]),
        window: HotKeyShortcut(keyCode: 19, modifiers: [.control, .option]),
        fullScreen: HotKeyShortcut(keyCode: 20, modifiers: [.control, .option]),
        recognizeText: HotKeyShortcut(keyCode: 31, modifiers: [.command, .shift])
    )

    public static func migratingLegacyDefaultIfNeeded(
        _ configuration: HotKeyConfiguration,
        didMigrate: Bool
    ) -> HotKeyConfiguration {
        configuration == .conflictSafe && !didMigrate ? .default : configuration
    }

    public static func addingDefaultTextRecognitionIfNeeded(
        _ configuration: HotKeyConfiguration,
        didMigrate: Bool
    ) -> HotKeyConfiguration {
        guard !didMigrate, configuration.recognizeText == nil else {
            return configuration
        }
        var result = configuration
        result.recognizeText = Self.default.recognizeText
        return result
    }

    public static func migratingLegacyTextRecognitionShortcutIfNeeded(
        _ configuration: HotKeyConfiguration,
        didMigrate: Bool
    ) -> HotKeyConfiguration {
        let legacyShortcut = HotKeyShortcut(keyCode: 31, modifiers: [.command])
        guard !didMigrate, configuration.recognizeText == legacyShortcut else {
            return configuration
        }
        var result = configuration
        result.recognizeText = Self.default.recognizeText
        return result
    }

    public func shortcut(for action: HotKeyAction) -> HotKeyShortcut? {
        switch action {
        case .area: area
        case .window: window
        case .fullScreen: fullScreen
        case .recognizeText: recognizeText
        }
    }

    public mutating func setShortcut(_ shortcut: HotKeyShortcut?, for action: HotKeyAction) {
        switch action {
        case .area: area = shortcut
        case .window: window = shortcut
        case .fullScreen: fullScreen = shortcut
        case .recognizeText: recognizeText = shortcut
        }
    }

    public var invalidActions: [HotKeyAction] {
        HotKeyAction.allCases.filter {
            shortcut(for: $0).map { !$0.isValid } ?? false
        }
    }

    public var conflicts: [HotKeyConflict] {
        var seen: [HotKeyShortcut: HotKeyAction] = [:]
        var result: [HotKeyConflict] = []
        for action in HotKeyAction.allCases {
            guard let shortcut = shortcut(for: action) else {
                continue
            }
            if let existing = seen[shortcut] {
                result.append(HotKeyConflict(
                    first: existing,
                    second: action,
                    shortcut: shortcut
                ))
            } else {
                seen[shortcut] = action
            }
        }
        return result
    }
}
