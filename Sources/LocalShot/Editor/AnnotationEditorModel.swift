import AppKit
import ImageIO
import LocalShotCore
import LocalShotEditing
import SwiftUI
import UniformTypeIdentifiers

struct AnnotationGestureDraft {
    var start: CGPoint
    var current: CGPoint
    var points: [CGPoint]
}

enum AnnotationResizeHandle: CaseIterable, Hashable {
    case bottomLeft
    case bottomRight
    case topLeft
    case topRight
}

private struct AnnotationTransformSession {
    let projectBeforeChange: AnnotationProject
    let annotationID: UUID
    let originalItem: AnnotationItem
    let originalRotation: Double
    let startPoint: AnnotationPoint
    let resizeHandle: AnnotationResizeHandle?
    let rotates: Bool
}

enum AnnotationEditorTool: String, CaseIterable, Identifiable {
    case select
    case crop
    case arrow
    case line
    case rectangle
    case ellipse
    case pen
    case highlight
    case text
    case step
    case spotlight
    case pixelate
    case redaction

    var id: String { rawValue }

    var label: String {
        switch self {
        case .select: "选择"
        case .crop: "裁剪"
        case .arrow: "箭头"
        case .line: "直线"
        case .rectangle: "矩形"
        case .ellipse: "椭圆"
        case .pen: "画笔"
        case .highlight: "高亮笔"
        case .text: "文字"
        case .step: "步骤编号"
        case .spotlight: "聚光灯"
        case .pixelate: "马赛克"
        case .redaction: "安全遮挡"
        }
    }

    var symbolName: String {
        switch self {
        case .select: "cursorarrow"
        case .crop: "crop"
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .pen: "pencil.tip"
        case .highlight: "pencil.line"
        case .text: "character"
        case .step: "1.circle.fill"
        case .spotlight: "scope"
        case .pixelate: "square.grid.3x3.fill"
        case .redaction: "rectangle.fill"
        }
    }
}

enum EditorColorPreset: String, CaseIterable, Identifiable {
    case red
    case blue
    case yellow
    case black
    case white

    var id: String { rawValue }

    var annotationColor: AnnotationColor {
        switch self {
        case .red: .red
        case .blue: AnnotationColor(red: 0.12, green: 0.48, blue: 0.95)
        case .yellow: AnnotationColor(red: 1, green: 0.76, blue: 0.08)
        case .black: .black
        case .white: .white
        }
    }

    var swiftUIColor: Color {
        let value = annotationColor
        return Color(
            red: value.red,
            green: value.green,
            blue: value.blue,
            opacity: value.alpha
        )
    }
}

@MainActor
final class AnnotationEditorModel: ObservableObject {
    @Published private(set) var project: AnnotationProject
    @Published var selectedTool: AnnotationEditorTool = .select
    @Published var selectedColor: EditorColorPreset = .red
    @Published var lineWidth: Double = 4
    @Published var lineIsDashed = false
    @Published var pixelateEffect: PixelateEffect = .mosaic
    @Published var textDraft = "文字"
    @Published var errorMessage: String?
    @Published var gestureDraft: AnnotationGestureDraft?
    @Published var selectedAnnotationID: UUID?

    let imageURL: URL
    let projectURL: URL

    private let store = AnnotationProjectStore()
    private var undoStack: [AnnotationProject] = []
    private var redoStack: [AnnotationProject] = []
    private var transformSession: AnnotationTransformSession?

    init(imageURL: URL, projectURL: URL? = nil) throws {
        let resolvedProjectURL = projectURL ?? imageURL
            .deletingPathExtension()
            .appendingPathExtension("localshot.json")
        self.imageURL = imageURL
        self.projectURL = resolvedProjectURL

        if FileManager.default.fileExists(atPath: resolvedProjectURL.path) {
            self.project = try store.load(from: resolvedProjectURL)
            return
        }

        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw AnnotationRendererError.imageReadFailed
        }
        self.project = AnnotationProject(
            imageFilename: imageURL.lastPathComponent,
            canvasWidth: image.width,
            canvasHeight: image.height
        )
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var isTransforming: Bool { transformSession != nil }
    var hasCrop: Bool { project.cropRect != nil }

    var nextStepNumber: Int {
        let highest = project.annotations.compactMap { item -> Int? in
            guard case let .step(step) = item else {
                return nil
            }
            return step.number
        }.max() ?? 0
        return highest + 1
    }

    var selectedAnnotation: AnnotationItem? {
        guard let selectedAnnotationID else {
            return nil
        }
        return project.annotations.first(where: { $0.id == selectedAnnotationID })
    }

    var selectedRotationDegrees: Int? {
        guard let selectedAnnotationID else {
            return nil
        }
        return Int((project.rotation(for: selectedAnnotationID) * 180 / .pi).rounded())
    }

    func add(_ annotation: AnnotationItem) {
        commitChange {
            $0.annotations.append(annotation)
        }
        selectedAnnotationID = annotation.id
    }

    func undo() {
        guard let previous = undoStack.popLast() else {
            return
        }
        redoStack.append(project)
        project = previous
        selectedAnnotationID = nil
        transformSession = nil
        saveProject()
    }

    func redo() {
        guard let next = redoStack.popLast() else {
            return
        }
        undoStack.append(project)
        project = next
        selectedAnnotationID = nil
        transformSession = nil
        saveProject()
    }

    func clear() {
        guard !project.annotations.isEmpty else {
            return
        }
        commitChange {
            $0.annotations.removeAll()
            $0.annotationRotations.removeAll()
        }
        selectedAnnotationID = nil
    }

    func deleteSelected() {
        guard let selectedAnnotationID else {
            return
        }
        commitChange {
            $0.annotations.removeAll(where: { $0.id == selectedAnnotationID })
            $0.removeRotation(for: selectedAnnotationID)
        }
        self.selectedAnnotationID = nil
    }

    func annotation(at point: AnnotationPoint, tolerance: Double) -> AnnotationItem? {
        project.annotations.reversed().first(where: {
            $0.hitTest(
                point,
                tolerance: tolerance,
                rotation: project.rotation(for: $0.id)
            )
        })
    }

    func select(_ annotationID: UUID?) {
        selectedAnnotationID = annotationID
    }

    func beginTransform(
        annotationID: UUID,
        startPoint: AnnotationPoint,
        resizeHandle: AnnotationResizeHandle?,
        rotates: Bool = false
    ) {
        guard transformSession == nil,
              let item = project.annotations.first(where: { $0.id == annotationID }) else {
            return
        }
        selectedAnnotationID = annotationID
        transformSession = AnnotationTransformSession(
            projectBeforeChange: project,
            annotationID: annotationID,
            originalItem: item,
            originalRotation: project.rotation(for: annotationID),
            startPoint: startPoint,
            resizeHandle: resizeHandle,
            rotates: rotates
        )
    }

    func updateTransform(to point: AnnotationPoint) {
        guard let session = transformSession,
              let index = project.annotations.firstIndex(where: { $0.id == session.annotationID }) else {
            return
        }

        if session.rotates {
            let center = session.originalItem.bounds.center
            let startAngle = atan2(
                session.startPoint.y - center.y,
                session.startPoint.x - center.x
            )
            let currentAngle = atan2(point.y - center.y, point.x - center.x)
            let rotation = session.originalRotation + currentAngle - startAngle
            var rotatedItem = session.originalItem
            let rotatedBounds = rotatedItem.bounds(rotation: rotation)
            let delta = clampedTranslation(
                for: rotatedBounds,
                requestedDX: 0,
                requestedDY: 0
            )
            if delta.dx != 0 || delta.dy != 0 {
                rotatedItem = rotatedItem.translated(dx: delta.dx, dy: delta.dy)
            }
            project.annotations[index] = rotatedItem
            project.setRotation(rotation, for: session.annotationID)
        } else if let resizeHandle = session.resizeHandle {
            let bounds = resizedBounds(
                session.originalItem.bounds,
                handle: resizeHandle,
                currentPoint: point,
                rotation: session.originalRotation
            )
            var resizedItem = session.originalItem.scaled(
                from: session.originalItem.bounds,
                to: bounds
            )
            let rotatedBounds = resizedItem.bounds(rotation: session.originalRotation)
            let delta = clampedTranslation(
                for: rotatedBounds,
                requestedDX: 0,
                requestedDY: 0
            )
            if delta.dx != 0 || delta.dy != 0 {
                resizedItem = resizedItem.translated(dx: delta.dx, dy: delta.dy)
            }
            project.annotations[index] = resizedItem
        } else {
            let delta = clampedTranslation(
                for: session.originalItem.bounds(rotation: session.originalRotation),
                requestedDX: point.x - session.startPoint.x,
                requestedDY: point.y - session.startPoint.y
            )
            project.annotations[index] = session.originalItem.translated(dx: delta.dx, dy: delta.dy)
        }
    }

    func finishTransform() {
        guard let session = transformSession else {
            return
        }
        transformSession = nil
        guard project != session.projectBeforeChange else {
            return
        }
        undoStack.append(session.projectBeforeChange)
        redoStack.removeAll()
        project.updatedAt = .now
        saveProject()
    }

    func cancelTransform() {
        guard let session = transformSession else {
            return
        }
        project = session.projectBeforeChange
        transformSession = nil
    }

    func setCrop(_ rect: AnnotationRect) {
        let crop = rect.normalized.intersection(project.fullCanvasRect)
        guard crop.width >= 8, crop.height >= 8 else {
            return
        }
        commitChange {
            $0.cropRect = crop
        }
        selectedAnnotationID = nil
    }

    func resetCrop() {
        guard project.cropRect != nil else {
            return
        }
        commitChange {
            $0.cropRect = nil
        }
        selectedAnnotationID = nil
    }

    func rotateSelected(by radians: Double) {
        guard let selectedAnnotationID,
              let index = project.annotations.firstIndex(where: { $0.id == selectedAnnotationID }) else {
            return
        }
        let item = project.annotations[index]
        let rotation = project.rotation(for: selectedAnnotationID) + radians
        let rotatedBounds = item.bounds(rotation: rotation)
        let delta = clampedTranslation(
            for: rotatedBounds,
            requestedDX: 0,
            requestedDY: 0
        )
        commitChange {
            if delta.dx != 0 || delta.dy != 0 {
                $0.annotations[index] = item.translated(dx: delta.dx, dy: delta.dy)
            }
            $0.setRotation(rotation, for: selectedAnnotationID)
        }
    }

    func resetSelectedRotation() {
        guard let selectedAnnotationID,
              project.rotation(for: selectedAnnotationID) != 0 else {
            return
        }
        commitChange {
            $0.removeRotation(for: selectedAnnotationID)
        }
    }

    func exportAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = imageURL
            .deletingPathExtension()
            .lastPathComponent + "-annotated.png"
        panel.canCreateDirectories = true

        panel.begin { [weak self] response in
            guard let self, response == .OK, let outputURL = panel.url else {
                return
            }
            do {
                try LocalFileExporter.exportGeneratedFile(to: outputURL) { temporaryURL in
                    try AnnotationRenderer.render(
                        baseImageURL: self.imageURL,
                        project: self.project,
                        outputURL: temporaryURL
                    )
                }
            } catch {
                Task { @MainActor in
                    self.errorMessage = "导出失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func saveProject() {
        do {
            try store.save(project, to: projectURL)
            errorMessage = nil
        } catch {
            errorMessage = "保存项目失败：\(error.localizedDescription)"
        }
    }

    private func commitChange(_ mutation: (inout AnnotationProject) -> Void) {
        let previous = project
        mutation(&project)
        guard project != previous else {
            return
        }
        undoStack.append(previous)
        redoStack.removeAll()
        project.updatedAt = .now
        saveProject()
    }

    private func clampedTranslation(
        for bounds: AnnotationRect,
        requestedDX: Double,
        requestedDY: Double
    ) -> (dx: Double, dy: Double) {
        let visible = project.visibleRect
        var dx = requestedDX
        var dy = requestedDY
        let moved = bounds.offsetBy(dx: dx, dy: dy)

        if moved.minX < visible.minX {
            dx += visible.minX - moved.minX
        } else if moved.maxX > visible.maxX {
            dx -= moved.maxX - visible.maxX
        }
        if moved.minY < visible.minY {
            dy += visible.minY - moved.minY
        } else if moved.maxY > visible.maxY {
            dy -= moved.maxY - visible.maxY
        }
        return (dx, dy)
    }

    private func resizedBounds(
        _ originalBounds: AnnotationRect,
        handle: AnnotationResizeHandle,
        currentPoint: AnnotationPoint,
        rotation: Double
    ) -> AnnotationRect {
        let original = originalBounds.normalized
        let center = original.center
        let anchorLocal: AnnotationPoint
        switch handle {
        case .bottomLeft:
            anchorLocal = AnnotationPoint(x: original.maxX, y: original.maxY)
        case .bottomRight:
            anchorLocal = AnnotationPoint(x: original.minX, y: original.maxY)
        case .topLeft:
            anchorLocal = AnnotationPoint(x: original.maxX, y: original.minY)
        case .topRight:
            anchorLocal = AnnotationPoint(x: original.minX, y: original.minY)
        }
        let anchor = anchorLocal.rotated(around: center, by: rotation)
        let dx = currentPoint.x - anchor.x
        let dy = currentPoint.y - anchor.y
        let cosine = cos(rotation)
        let sine = sin(rotation)
        let localDX = dx * cosine + dy * sine
        let localDY = -dx * sine + dy * cosine
        let minimumSize = 6.0
        let width = max(minimumSize, abs(localDX))
        let height = max(minimumSize, abs(localDY))
        let localCenterOffset: (x: Double, y: Double)
        switch handle {
        case .bottomLeft:
            localCenterOffset = (-width / 2, -height / 2)
        case .bottomRight:
            localCenterOffset = (width / 2, -height / 2)
        case .topLeft:
            localCenterOffset = (-width / 2, height / 2)
        case .topRight:
            localCenterOffset = (width / 2, height / 2)
        }
        let worldCenter = AnnotationPoint(
            x: anchor.x
                + localCenterOffset.x * cosine
                - localCenterOffset.y * sine,
            y: anchor.y
                + localCenterOffset.x * sine
                + localCenterOffset.y * cosine
        )
        return AnnotationRect(
            x: worldCenter.x - width / 2,
            y: worldCenter.y - height / 2,
            width: width,
            height: height
        )
    }
}
