import Foundation

public struct CaptureAsset: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public let createdAt: Date
    public let mode: CaptureMode

    public init(
        id: UUID = UUID(),
        url: URL,
        createdAt: Date,
        mode: CaptureMode
    ) {
        self.id = id
        self.url = url
        self.createdAt = createdAt
        self.mode = mode
    }
}
