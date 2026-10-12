import Foundation

public extension AnnotationItem {
    var bounds: AnnotationRect {
        switch self {
        case let .arrow(value):
            arrowBounds(value)
        case let .rectangle(value):
            value.rect.normalized
        case let .ellipse(value):
            value.rect.normalized
        case let .line(value):
            AnnotationRect.enclosing([value.start, value.end])
        case let .pen(value):
            AnnotationRect.enclosing(value.points)
        case let .highlight(value):
            AnnotationRect.enclosing(value.points)
        case let .text(value):
            AnnotationRect(
                x: value.position.x,
                y: value.position.y,
                width: max(value.fontSize, Double(value.text.count) * value.fontSize * 0.62),
                height: max(1, value.fontSize * 1.2)
            )
        case let .pixelate(value):
            value.rect.normalized
        case let .redaction(value):
            value.rect.normalized
        case let .step(value):
            stepBounds(value)
        case let .spotlight(value):
            value.focusRect.normalized
        }
    }

    private func stepBounds(_ value: StepAnnotation) -> AnnotationRect {
        let circle = AnnotationRect(
                x: value.center.x - value.diameter / 2,
                y: value.center.y - value.diameter / 2,
                width: value.diameter,
                height: value.diameter
            )
        guard let note = value.note else {
            return circle
        }
        let fontSize = max(11, value.diameter * 0.5)
        let noteWidth = note.reduce(0.0) { width, character in
            let isASCII = character.unicodeScalars.allSatisfy { $0.value < 128 }
            return width + fontSize * (isASCII ? 0.62 : 1)
        }
        let noteHeight = fontSize * 1.2
        let noteMinX = circle.maxX + max(5, value.diameter * 0.18)
        let minY = min(circle.minY, value.center.y - noteHeight / 2)
        let maxY = max(circle.maxY, value.center.y + noteHeight / 2)
        return AnnotationRect(
            x: circle.minX,
            y: minY,
            width: noteMinX + noteWidth - circle.minX,
            height: maxY - minY
        )
    }

    private func arrowBounds(_ value: ArrowAnnotation) -> AnnotationRect {
        let shapeBounds = ArrowShapeGeometry(value).bounds
        guard let noteBounds = arrowNoteBounds(value) else {
            return shapeBounds
        }
        return AnnotationRect(
            x: min(shapeBounds.minX, noteBounds.minX),
            y: min(shapeBounds.minY, noteBounds.minY),
            width: max(shapeBounds.maxX, noteBounds.maxX) - min(shapeBounds.minX, noteBounds.minX),
            height: max(shapeBounds.maxY, noteBounds.maxY) - min(shapeBounds.minY, noteBounds.minY)
        )
    }

    private func arrowNoteBounds(_ value: ArrowAnnotation) -> AnnotationRect? {
        guard let note = value.note else {
            return nil
        }
        let noteWidth = note.reduce(0.0) { width, character in
            let isASCII = character.unicodeScalars.allSatisfy { $0.value < 128 }
            return width + value.noteFontSize * (isASCII ? 0.62 : 1)
        }
        let noteHeight = value.noteFontSize * 1.2
        let origin = value.noteOrigin(width: noteWidth, height: noteHeight)
        return AnnotationRect(
            x: origin.x,
            y: origin.y,
            width: noteWidth,
            height: noteHeight
        )
    }

    func bounds(rotation: Double) -> AnnotationRect {
        AnnotationRect.enclosing(orientedCorners(rotation: rotation))
    }

    func orientedCorners(rotation: Double) -> [AnnotationPoint] {
        let rect = bounds.normalized
        let center = rect.center
        return [
            AnnotationPoint(x: rect.minX, y: rect.maxY),
            AnnotationPoint(x: rect.maxX, y: rect.maxY),
            AnnotationPoint(x: rect.maxX, y: rect.minY),
            AnnotationPoint(x: rect.minX, y: rect.minY)
        ].map { $0.rotated(around: center, by: rotation) }
    }

    func hitTest(
        _ point: AnnotationPoint,
        tolerance: Double = 6,
        rotation: Double = 0
    ) -> Bool {
        let localPoint = point.rotated(around: bounds.center, by: -rotation)
        return hitTestUnrotated(localPoint, tolerance: tolerance)
    }

    private func hitTestUnrotated(_ point: AnnotationPoint, tolerance: Double) -> Bool {
        switch self {
        case let .arrow(value):
            let hitsShape = ArrowShapeGeometry(value).contains(point, tolerance: tolerance)
            let hitsNote = arrowNoteBounds(value)?
                .insetBy(dx: -tolerance, dy: -tolerance)
                .contains(point) ?? false
            return hitsShape || hitsNote
        case let .line(value):
            return distance(point, toSegmentFrom: value.start, to: value.end)
                <= max(tolerance, value.lineWidth * 1.5)
        case let .pen(value):
            guard value.points.count >= 2 else {
                return value.points.first.map {
                    hypot(point.x - $0.x, point.y - $0.y) <= tolerance
                } ?? false
            }
            return zip(value.points, value.points.dropFirst()).contains {
                distance(point, toSegmentFrom: $0.0, to: $0.1) <= max(tolerance, value.lineWidth * 1.5)
            }
        case let .highlight(value):
            guard value.points.count >= 2 else {
                return value.points.first.map {
                    hypot(point.x - $0.x, point.y - $0.y) <= tolerance
                } ?? false
            }
            return zip(value.points, value.points.dropFirst()).contains {
                distance(point, toSegmentFrom: $0.0, to: $0.1)
                    <= max(tolerance, value.lineWidth * 0.6)
            }
        case .rectangle, .ellipse, .text, .pixelate, .redaction, .step, .spotlight:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
    }

    func translated(dx: Double, dy: Double) -> AnnotationItem {
        switch self {
        case .arrow(var value):
            value.start = value.start.offsetBy(dx: dx, dy: dy)
            value.end = value.end.offsetBy(dx: dx, dy: dy)
            return .arrow(value)
        case .rectangle(var value):
            value.rect = value.rect.offsetBy(dx: dx, dy: dy)
            return .rectangle(value)
        case .ellipse(var value):
            value.rect = value.rect.offsetBy(dx: dx, dy: dy)
            return .ellipse(value)
        case .line(var value):
            value.start = value.start.offsetBy(dx: dx, dy: dy)
            value.end = value.end.offsetBy(dx: dx, dy: dy)
            return .line(value)
        case .pen(var value):
            value.points = value.points.map { $0.offsetBy(dx: dx, dy: dy) }
            return .pen(value)
        case .highlight(var value):
            value.points = value.points.map { $0.offsetBy(dx: dx, dy: dy) }
            return .highlight(value)
        case .text(var value):
            value.position = value.position.offsetBy(dx: dx, dy: dy)
            return .text(value)
        case .pixelate(var value):
            value.rect = value.rect.offsetBy(dx: dx, dy: dy)
            return .pixelate(value)
        case .redaction(var value):
            value.rect = value.rect.offsetBy(dx: dx, dy: dy)
            return .redaction(value)
        case .step(var value):
            value.center = value.center.offsetBy(dx: dx, dy: dy)
            return .step(value)
        case .spotlight(var value):
            value.focusRect = value.focusRect.offsetBy(dx: dx, dy: dy)
            return .spotlight(value)
        }
    }

    func scaled(from originalBounds: AnnotationRect, to newBounds: AnnotationRect) -> AnnotationItem {
        let original = originalBounds.normalized
        let target = newBounds.normalized

        switch self {
        case .arrow(var value):
            let scale = min(
                target.width / max(1, original.width),
                target.height / max(1, original.height)
            )
            let originalStart = value.start
            let originalEnd = value.end
            value.start = scaledArrowPoint(
                originalStart,
                other: originalEnd,
                from: original,
                to: target
            )
            value.end = scaledArrowPoint(
                originalEnd,
                other: originalStart,
                from: original,
                to: target
            )
            value.noteFontSize = max(11, value.noteFontSize * scale)
            return .arrow(value)
        case .rectangle(var value):
            value.rect = target
            return .rectangle(value)
        case .ellipse(var value):
            value.rect = target
            return .ellipse(value)
        case .line(var value):
            let originalStart = value.start
            let originalEnd = value.end
            value.start = scaledArrowPoint(
                originalStart,
                other: originalEnd,
                from: original,
                to: target
            )
            value.end = scaledArrowPoint(
                originalEnd,
                other: originalStart,
                from: original,
                to: target
            )
            return .line(value)
        case .pen(var value):
            value.points = value.points.map { scaledPoint($0, from: original, to: target) }
            return .pen(value)
        case .highlight(var value):
            value.points = value.points.map { scaledPoint($0, from: original, to: target) }
            return .highlight(value)
        case .text(var value):
            let heightScale = target.height / max(1, original.height)
            value.position = AnnotationPoint(x: target.minX, y: target.minY)
            value.fontSize = max(8, value.fontSize * heightScale)
            return .text(value)
        case .pixelate(var value):
            value.rect = target
            return .pixelate(value)
        case .redaction(var value):
            value.rect = target
            return .redaction(value)
        case .step(var value):
            let scale = min(
                target.width / max(1, original.width),
                target.height / max(1, original.height)
            )
            value.center = scaledPoint(value.center, from: original, to: target)
            value.diameter = max(16, value.diameter * scale)
            return .step(value)
        case .spotlight(var value):
            value.focusRect = target
            return .spotlight(value)
        }
    }
}

private func scaledPoint(
    _ point: AnnotationPoint,
    from original: AnnotationRect,
    to target: AnnotationRect
) -> AnnotationPoint {
    let relativeX = original.width > 0 ? (point.x - original.minX) / original.width : 0.5
    let relativeY = original.height > 0 ? (point.y - original.minY) / original.height : 0.5
    return AnnotationPoint(
        x: target.minX + relativeX * target.width,
        y: target.minY + relativeY * target.height
    )
}

private func scaledArrowPoint(
    _ point: AnnotationPoint,
    other: AnnotationPoint,
    from original: AnnotationRect,
    to target: AnnotationRect
) -> AnnotationPoint {
    let relativeX: Double
    if original.width > 0 {
        relativeX = (point.x - original.minX) / original.width
    } else {
        relativeX = point == other ? 0.5 : (point.y <= other.y ? 0 : 1)
    }
    let relativeY: Double
    if original.height > 0 {
        relativeY = (point.y - original.minY) / original.height
    } else {
        relativeY = point == other ? 0.5 : (point.x <= other.x ? 0 : 1)
    }
    return AnnotationPoint(
        x: target.minX + relativeX * target.width,
        y: target.minY + relativeY * target.height
    )
}

private func distance(
    _ point: AnnotationPoint,
    toSegmentFrom start: AnnotationPoint,
    to end: AnnotationPoint
) -> Double {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let lengthSquared = dx * dx + dy * dy
    guard lengthSquared > 0 else {
        return hypot(point.x - start.x, point.y - start.y)
    }
    let projection = min(
        1,
        max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared)
    )
    let closestX = start.x + projection * dx
    let closestY = start.y + projection * dy
    return hypot(point.x - closestX, point.y - closestY)
}
