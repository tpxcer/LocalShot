import AppKit

@MainActor
final class SingleWindowCoordinator: NSObject, NSWindowDelegate {
    private var windowController: NSWindowController?

    func show(_ window: NSWindow) {
        windowController?.close()

        let controller = NSWindowController(window: window)
        window.delegate = self
        windowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              windowController?.window === closingWindow else {
            return
        }
        windowController = nil
    }
}
