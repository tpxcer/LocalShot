import AppKit
import SwiftUI

@MainActor
final class CaptureHistoryController {
    private let windowCoordinator = SingleWindowCoordinator()

    func open(
        appModel: AppModel,
        searchModel: CaptureHistorySearchModel
    ) {
        appModel.refreshHistory()
        let filterModel = CaptureHistoryFilterModel()
        let rootView = CaptureHistoryView(
            appModel: appModel,
            filterModel: filterModel,
            searchModel: searchModel
        )
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "截图历史"
        window.contentViewController = hostingController
        window.minSize = NSSize(width: 700, height: 480)
        window.center()
        window.isReleasedWhenClosed = false

        windowCoordinator.show(window)
    }
}
