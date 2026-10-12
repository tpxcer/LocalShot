import AppKit
import LocalShotCore

struct SelectionSnappingCandidate {
    let candidate: WindowCaptureCandidate
    let frame: CGRect
    let applicationName: String
    let title: String
}

@MainActor
final class SelectionOverlayController {
    struct Result {
        let screen: NSScreen
        let displayID: CGDirectDisplayID
        let sourceRect: CGRect
        let targetWindow: WindowCaptureCandidate?

        init(
            screen: NSScreen,
            displayID: CGDirectDisplayID,
            sourceRect: CGRect,
            targetWindow: WindowCaptureCandidate? = nil
        ) {
            self.screen = screen
            self.displayID = displayID
            self.sourceRect = sourceRect
            self.targetWindow = targetWindow
        }
    }

    private var panels: [NSPanel] = []
    private var keyMonitor: Any?
    private var completion: ((Result?) -> Void)?

    func begin(
        previewImages: [CGDirectDisplayID: CGImage] = [:],
        candidates: [WindowCaptureCandidate] = [],
        initialSelections: [CGDirectDisplayID: CGRect] = [:],
        initialCursorPoints: [CGDirectDisplayID: CGPoint] = [:],
        showsPreviewAsBackground: Bool = false,
        locksSnappedWindows: Bool = true,
        instructionText: String = "拖动选择截图区域  ·  右键或 Esc 取消",
        completion: @escaping (Result?) -> Void
    ) {
        closePanels()
        self.completion = completion

        let primaryScreenHeight = NSScreen.screens
            .first(where: { abs($0.frame.minX) < 0.5 && abs($0.frame.minY) < 0.5 })?
            .frame.height ?? NSScreen.screens.first?.frame.height ?? 0

        for screen in NSScreen.screens {
            guard let displayID = screen.localShotDisplayID else {
                continue
            }
            let panel = SelectionPanel(
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
            panel.ignoresMouseEvents = false

            let snappingCandidates: [SelectionSnappingCandidate] = candidates.compactMap {
                candidate -> SelectionSnappingCandidate? in
                let globalFrame = ScreenCoordinateConverter.appKitWindowRect(
                    fromScreenCaptureKitFrame: candidate.frame,
                    primaryScreenHeight: primaryScreenHeight
                )
                let intersection = globalFrame.intersection(screen.frame)
                guard intersection.width >= 24, intersection.height >= 24 else {
                    return nil
                }
                return SelectionSnappingCandidate(
                    candidate: candidate,
                    frame: intersection.offsetBy(
                        dx: -screen.frame.minX,
                        dy: -screen.frame.minY
                    ),
                    applicationName: candidate.applicationName,
                    title: candidate.title
                )
            }

            let view = SelectionOverlayView(
                frame: CGRect(origin: .zero, size: screen.frame.size),
                frozenImage: previewImages[displayID],
                scaleFactor: screen.backingScaleFactor,
                snappingCandidates: snappingCandidates,
                initialSelectionRect: initialSelections[displayID] ?? .zero,
                initialCursorPoint: initialCursorPoints[displayID],
                showsFrozenImageAsBackground: showsPreviewAsBackground,
                instructionText: instructionText
            )
            view.onSelection = { [weak self, weak screen] rect, targetWindow in
                guard let self, let screen else {
                    return
                }
                let sourceRect = ScreenCoordinateConverter.screenCaptureKitSourceRect(
                    fromAppKitSelection: rect,
                    screenHeight: screen.frame.height
                )
                self.finish(with: Result(
                    screen: screen,
                    displayID: displayID,
                    sourceRect: sourceRect,
                    targetWindow: locksSnappedWindows ? targetWindow : nil
                ))
            }
            view.onCancel = { [weak self] in
                self?.finish(with: nil)
            }
            panel.contentView = view
            panels.append(panel)
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
    }

    func cancel() {
        finish(with: nil)
    }

    private func finish(with result: Result?) {
        let completion = completion
        self.completion = nil
        closePanels()
        completion?(result)
    }

    private func closePanels() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        panels.forEach { $0.close() }
        panels.removeAll()
    }
}

private final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}
