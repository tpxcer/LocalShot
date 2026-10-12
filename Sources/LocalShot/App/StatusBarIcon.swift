import AppKit

@MainActor
enum StatusBarIcon {
    static let image: NSImage = {
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.scaleBy(x: 0.82, y: 0.82)
            context.translateBy(x: -size.width / 2, y: -size.height / 2)

            NSColor.black.setStroke()
            NSColor.black.setFill()

            let brackets = NSBezierPath()
            brackets.lineWidth = 1.7
            brackets.lineCapStyle = .round
            brackets.lineJoinStyle = .round
            let minimum: CGFloat = 2.7
            let maximum: CGFloat = 19.3
            let length: CGFloat = 4.6
            let corners: [(NSPoint, CGFloat, CGFloat)] = [
                (NSPoint(x: minimum, y: maximum), 1, -1),
                (NSPoint(x: maximum, y: maximum), -1, -1),
                (NSPoint(x: minimum, y: minimum), 1, 1),
                (NSPoint(x: maximum, y: minimum), -1, 1)
            ]
            for (corner, horizontal, vertical) in corners {
                brackets.move(to: NSPoint(x: corner.x + horizontal * length, y: corner.y))
                brackets.line(to: corner)
                brackets.line(to: NSPoint(x: corner.x, y: corner.y + vertical * length))
            }
            brackets.stroke()

            let handles = NSBezierPath()
            handles.lineWidth = 1.55
            handles.appendOval(in: NSRect(x: 5.1, y: 4.7, width: 4.8, height: 4.8))
            handles.appendOval(in: NSRect(x: 5.1, y: 12.5, width: 4.8, height: 4.8))
            handles.stroke()

            let blades = NSBezierPath()
            blades.lineWidth = 1.65
            blades.lineCapStyle = .round
            blades.lineJoinStyle = .round
            blades.move(to: NSPoint(x: 8.8, y: 8.6))
            blades.curve(
                to: NSPoint(x: 11.2, y: 11),
                controlPoint1: NSPoint(x: 9.7, y: 9.2),
                controlPoint2: NSPoint(x: 10.5, y: 10.2)
            )
            blades.line(to: NSPoint(x: 17.2, y: 16.9))
            blades.move(to: NSPoint(x: 8.8, y: 13.4))
            blades.curve(
                to: NSPoint(x: 11.2, y: 11),
                controlPoint1: NSPoint(x: 9.7, y: 12.8),
                controlPoint2: NSPoint(x: 10.5, y: 11.8)
            )
            blades.line(to: NSPoint(x: 17.2, y: 5.1))
            blades.stroke()

            NSBezierPath(ovalIn: NSRect(x: 10.25, y: 10.05, width: 1.9, height: 1.9)).fill()
            context.restoreGState()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
