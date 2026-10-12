import Foundation

public enum CaptureOutputFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case png
    case jpeg

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        }
    }

    public var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        }
    }

    public var screenshotCommandComponent: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        }
    }
}
