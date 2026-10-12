import CoreGraphics
import Foundation

public struct WindowCaptureCandidate: Hashable, Sendable, Identifiable {
    public let id: CGWindowID
    public let frame: CGRect
    public let processID: pid_t
    public let applicationName: String
    public let title: String

    public init(
        id: CGWindowID,
        frame: CGRect,
        processID: pid_t,
        applicationName: String,
        title: String
    ) {
        self.id = id
        self.frame = frame
        self.processID = processID
        self.applicationName = applicationName
        self.title = title
    }
}
