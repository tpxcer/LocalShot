import AppKit
import LocalShotCore
import LocalShotEditing

enum QQCaptureOverlayAction: Equatable {
    case finish
    case save
    case recognizeText
    case recording
    case translate
    case pin
    case scrolling
}

struct QQCaptureOverlayResult {
    let screen: NSScreen
    let displayID: CGDirectDisplayID
    let sourceRect: CGRect
    let project: AnnotationProject
    let action: QQCaptureOverlayAction
    let frozenSelectionImage: CGImage
    let targetWindow: WindowCaptureCandidate?
    let windowRelativeRect: CGRect?
    let recordingTargetWindow: WindowCaptureCandidate?
}

struct QQCaptureSnappingCandidate {
    let candidate: WindowCaptureCandidate
    let frame: CGRect
    let applicationName: String
    let title: String
}

@MainActor
final class QQCaptureOverlayController {
    private var panels: [NSPanel] = []
    private var keyMonitor: Any?
    private var completion: ((QQCaptureOverlayResult?) -> Void)?

    func begin(
        previewImages: [CGDirectDisplayID: CGImage],
        candidates: [WindowCaptureCandidate],
        initialSelections: [CGDirectDisplayID: CGRect] = [:],
        initialAnnotations: [CGDirectDisplayID: [AnnotationItem]] = [:],
        initialCursorPoints: [CGDirectDisplayID: CGPoint] = [:],
        showsPropertiesInitially: Bool = false,
        showsPixelatePropertiesInitially: Bool = false,
        isInteractive: Bool = true,
        emphasizesScrollingAction: Bool = false,
        completion: @escaping (QQCaptureOverlayResult?) -> Void
    ) {
        closePanels()
        self.completion = completion

        let primaryScreenHeight = NSScreen.screens
            .first(where: { abs($0.frame.minX) < 0.5 && abs($0.frame.minY) < 0.5 })?
            .frame.height ?? NSScreen.screens.first?.frame.height ?? 0

        let screensWithDisplayIDs = NSScreen.screens.compactMap { screen in
            screen.localShotDisplayID.map { (screen, $0) }
        }
        guard !screensWithDisplayIDs.isEmpty,
              screensWithDisplayIDs.allSatisfy({ previewImages[$0.1] != nil }) else {
            finish(with: nil)
            return
        }

        for (screen, displayID) in screensWithDisplayIDs {

            let panel = QQCapturePanel(
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
            panel.ignoresMouseEvents = !isInteractive

            let snappingCandidates = candidates.compactMap { candidate -> QQCaptureSnappingCandidate? in
                let globalFrame = ScreenCoordinateConverter.appKitWindowRect(
                    fromScreenCaptureKitFrame: candidate.frame,
                    primaryScreenHeight: primaryScreenHeight
                )
                let intersection = globalFrame.intersection(screen.frame)
                guard intersection.width >= 24, intersection.height >= 24 else {
                    return nil
                }
                return QQCaptureSnappingCandidate(
                    candidate: candidate,
                    frame: intersection.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY),
                    applicationName: candidate.applicationName,
                    title: candidate.title
                )
            }

            guard let previewImage = previewImages[displayID] else {
                finish(with: nil)
                return
            }
            let view = QQCaptureOverlayView(
                frame: CGRect(origin: .zero, size: screen.frame.size),
                frozenImage: previewImage,
                scaleFactor: screen.backingScaleFactor,
                snappingCandidates: snappingCandidates,
                initialSelectionRect: initialSelections[displayID] ?? .zero,
                initialAnnotations: initialAnnotations[displayID] ?? [],
                initialCursorPoint: initialCursorPoints[displayID],
                showsPropertiesInitially: showsPropertiesInitially,
                showsPixelatePropertiesInitially: showsPixelatePropertiesInitially,
                emphasizesScrollingAction: emphasizesScrollingAction
            )
            view.onComplete = { [weak self, weak screen] selectionRect, annotations, action in
                guard let self, let screen else {
                    return
                }
                let sourceRect = ScreenCoordinateConverter.screenCaptureKitSourceRect(
                    fromAppKitSelection: selectionRect,
                    screenHeight: screen.frame.height
                )
                guard let frozenSelectionImage = ScreenCoordinateConverter.croppedImage(
                    previewImage,
                    logicalRect: sourceRect,
                    logicalSize: screen.frame.size
                ) else {
                    assertionFailure("无法从冻结屏幕画面裁剪选区。")
                    self.finish(with: nil)
                    return
                }
                let project = AnnotationProject(
                    imageFilename: "",
                    canvasWidth: frozenSelectionImage.width,
                    canvasHeight: frozenSelectionImage.height,
                    annotations: annotations
                )
                let target = snappingCandidates.first(where: {
                    $0.frame.insetBy(dx: -0.5, dy: -0.5).contains(selectionRect)
                })
                let recordingTarget = snappingCandidates.first(where: {
                    abs($0.frame.minX - selectionRect.minX) <= 0.5
                        && abs($0.frame.minY - selectionRect.minY) <= 0.5
                        && abs($0.frame.width - selectionRect.width) <= 0.5
                        && abs($0.frame.height - selectionRect.height) <= 0.5
                })
                let globalAppKitSelection = selectionRect.offsetBy(
                    dx: screen.frame.minX,
                    dy: screen.frame.minY
                )
                let globalScreenCaptureSelection = CGRect(
                    x: globalAppKitSelection.minX,
                    y: primaryScreenHeight - globalAppKitSelection.maxY,
                    width: globalAppKitSelection.width,
                    height: globalAppKitSelection.height
                )
                let windowRelativeRect = target.flatMap {
                    ScreenCoordinateConverter.windowRelativeRect(
                        forGlobalSelection: globalScreenCaptureSelection,
                        inside: $0.candidate.frame
                    )
                }
                self.finish(with: QQCaptureOverlayResult(
                    screen: screen,
                    displayID: displayID,
                    sourceRect: sourceRect,
                    project: project,
                    action: action,
                    frozenSelectionImage: frozenSelectionImage,
                    targetWindow: target?.candidate,
                    windowRelativeRect: windowRelativeRect,
                    recordingTargetWindow: recordingTarget?.candidate
                ))
            }
            view.onCancel = { [weak self] in
                self?.finish(with: nil)
            }
            panel.contentView = view
            panels.append(panel)
            panel.orderFrontRegardless()
        }

        if isInteractive {
            keyMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.keyDown, .rightMouseDown]
            ) { [weak self] event in
                if event.type == .rightMouseDown {
                    self?.finish(with: nil)
                    return nil
                }
                guard event.type == .keyDown, event.keyCode == 53 else {
                    return event
                }
                self?.finish(with: nil)
                return nil
            }
        }

        NSApp.activate(ignoringOtherApps: true)
        panels.first?.makeKey()
        panels.first?.makeFirstResponder(panels.first?.contentView)
    }

    func cancel() {
        finish(with: nil)
    }

    private func finish(with result: QQCaptureOverlayResult?) {
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

private final class QQCapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
