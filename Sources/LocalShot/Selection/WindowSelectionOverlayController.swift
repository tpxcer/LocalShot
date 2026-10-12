import AppKit
import LocalShotCore

@MainActor
final class WindowSelectionOverlayController {
    private struct SelectableWindow {
        let candidate: WindowCaptureCandidate
        let appKitFrame: CGRect
    }

    private var panels: [NSPanel] = []
    private var overlayViews: [WindowSelectionOverlayView] = []
    private var selectableWindows: [SelectableWindow] = []
    private var keyMonitor: Any?
    private var completion: ((CGWindowID?) -> Void)?

    func begin(
        candidates: [WindowCaptureCandidate],
        backgroundImages: [CGDirectDisplayID: CGImage] = [:],
        initialPointerLocation: CGPoint? = nil,
        tracksPointer: Bool = true,
        completion: @escaping (CGWindowID?) -> Void
    ) {
        closePanels()
        self.completion = completion

        let primaryScreenHeight = NSScreen.screens
            .first(where: { abs($0.frame.minX) < 0.5 && abs($0.frame.minY) < 0.5 })?
            .frame.height ?? NSScreen.screens.first?.frame.height ?? 0
        selectableWindows = candidates.map {
            SelectableWindow(
                candidate: $0,
                appKitFrame: ScreenCoordinateConverter.appKitWindowRect(
                    fromScreenCaptureKitFrame: $0.frame,
                    primaryScreenHeight: primaryScreenHeight
                )
            )
        }

        for screen in NSScreen.screens {
            let panel = WindowSelectionPanel(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.acceptsMouseMovedEvents = true

            let view = WindowSelectionOverlayView(
                frame: CGRect(origin: .zero, size: screen.frame.size),
                screenFrame: screen.frame,
                backgroundImage: screen.localShotDisplayID.flatMap { backgroundImages[$0] }
            )
            if tracksPointer {
                view.onPointerMoved = { [weak self] point in
                    self?.updateHighlight(at: point)
                }
            }
            view.onSelect = { [weak self] windowID in
                self?.selectHighlightedWindow(id: windowID)
            }
            view.onCancel = { [weak self] in
                self?.finish(with: nil)
            }
            panel.contentView = view
            panels.append(panel)
            overlayViews.append(view)
            panel.orderFrontRegardless()
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .rightMouseDown]
        ) { [weak self] event in
            if event.type == .rightMouseDown {
                self?.finish(with: nil)
                return nil
            }
            if event.type == .keyDown, event.keyCode == 53 {
                self?.finish(with: nil)
                return nil
            }
            return event
        }

        NSApp.activate(ignoringOtherApps: true)
        panels.first?.makeKey()
        panels.first?.makeFirstResponder(panels.first?.contentView)
        updateHighlight(at: initialPointerLocation ?? NSEvent.mouseLocation)
    }

    func cancel() {
        finish(with: nil)
    }

    private func updateHighlight(at point: CGPoint) {
        let highlighted = selectableWindows.first(where: { $0.appKitFrame.contains(point) })
        for view in overlayViews {
            view.highlightedWindow = highlighted.map {
                WindowSelectionOverlayView.HighlightedWindow(
                    id: $0.candidate.id,
                    frame: $0.appKitFrame,
                    applicationName: $0.candidate.applicationName,
                    title: $0.candidate.title
                )
            }
        }
    }

    private func selectHighlightedWindow(id: CGWindowID) {
        let selected = selectableWindows.first(where: { $0.candidate.id == id })
        finish(with: selected?.candidate.id)
    }

    private func finish(with windowID: CGWindowID?) {
        let completion = completion
        self.completion = nil
        closePanels()
        completion?(windowID)
    }

    private func closePanels() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        panels.forEach { $0.close() }
        panels.removeAll()
        overlayViews.removeAll()
        selectableWindows.removeAll()
    }
}

private final class WindowSelectionPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}
