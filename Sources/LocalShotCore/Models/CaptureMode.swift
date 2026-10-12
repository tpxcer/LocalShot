import Foundation

public enum CaptureMode: String, CaseIterable, Codable, Sendable {
    case area
    case window
    case fullScreen
    case scrolling

    public var displayName: String {
        switch self {
        case .area:
            "区域截图"
        case .window:
            "窗口截图"
        case .fullScreen:
            "全屏截图"
        case .scrolling:
            "区域长截图"
        }
    }

    public var symbolName: String {
        switch self {
        case .area:
            "viewfinder"
        case .window:
            "macwindow"
        case .fullScreen:
            "display"
        case .scrolling:
            "scroll"
        }
    }

    public var fileComponent: String {
        switch self {
        case .area:
            "area"
        case .window:
            "window"
        case .fullScreen:
            "screen"
        case .scrolling:
            "scrolling"
        }
    }
}
