import Foundation

public struct BeautificationColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
        self.alpha = min(max(alpha, 0), 1)
    }
}

public enum BeautificationBackground: Codable, Hashable, Sendable {
    case solid(BeautificationColor)
    case linearGradient(start: BeautificationColor, end: BeautificationColor)
}

public enum BeautificationBackgroundPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case system
    case ocean
    case sunset
    case graphite
    case paper

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: "系统蓝紫"
        case .ocean: "海洋"
        case .sunset: "日落"
        case .graphite: "石墨"
        case .paper: "浅色纸张"
        }
    }

    public var background: BeautificationBackground {
        switch self {
        case .system:
            .linearGradient(
                start: BeautificationColor(red: 0.21, green: 0.45, blue: 0.96),
                end: BeautificationColor(red: 0.55, green: 0.28, blue: 0.90)
            )
        case .ocean:
            .linearGradient(
                start: BeautificationColor(red: 0.03, green: 0.55, blue: 0.73),
                end: BeautificationColor(red: 0.04, green: 0.24, blue: 0.52)
            )
        case .sunset:
            .linearGradient(
                start: BeautificationColor(red: 1.00, green: 0.55, blue: 0.28),
                end: BeautificationColor(red: 0.78, green: 0.20, blue: 0.47)
            )
        case .graphite:
            .linearGradient(
                start: BeautificationColor(red: 0.19, green: 0.21, blue: 0.25),
                end: BeautificationColor(red: 0.05, green: 0.06, blue: 0.08)
            )
        case .paper:
            .solid(BeautificationColor(red: 0.95, green: 0.95, blue: 0.93))
        }
    }
}

public enum BeautificationAspectRatio: String, CaseIterable, Codable, Identifiable, Sendable {
    case automatic
    case square
    case landscape4x3
    case landscape16x9
    case portrait4x5

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic: "自动"
        case .square: "1:1"
        case .landscape4x3: "4:3"
        case .landscape16x9: "16:9"
        case .portrait4x5: "4:5"
        }
    }

    public var widthToHeight: Double? {
        switch self {
        case .automatic: nil
        case .square: 1
        case .landscape4x3: 4.0 / 3.0
        case .landscape16x9: 16.0 / 9.0
        case .portrait4x5: 4.0 / 5.0
        }
    }
}

public struct ImageBeautificationOptions: Codable, Hashable, Sendable {
    public var background: BeautificationBackground
    public var padding: Double
    public var cornerRadius: Double
    public var shadowRadius: Double
    public var shadowOpacity: Double
    public var aspectRatio: BeautificationAspectRatio

    public init(
        background: BeautificationBackground = BeautificationBackgroundPreset.system.background,
        padding: Double = 56,
        cornerRadius: Double = 18,
        shadowRadius: Double = 20,
        shadowOpacity: Double = 0.28,
        aspectRatio: BeautificationAspectRatio = .automatic
    ) {
        self.background = background
        self.padding = max(0, padding)
        self.cornerRadius = max(0, cornerRadius)
        self.shadowRadius = max(0, shadowRadius)
        self.shadowOpacity = min(max(shadowOpacity, 0), 1)
        self.aspectRatio = aspectRatio
    }
}
