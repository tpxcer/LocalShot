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

            // 与应用图标一致：取景框四角 + 中心快门圆点
            let brackets = NSBezierPath()
            brackets.lineWidth = 2
            brackets.lineCapStyle = .round
            brackets.lineJoinStyle = .round
            let minimum: CGFloat = 2.7
            let maximum: CGFloat = 19.3
            let length: CGFloat = 4.8
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

            NSBezierPath(ovalIn: NSRect(x: 8.2, y: 8.2, width: 5.6, height: 5.6)).fill()
            context.restoreGState()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
