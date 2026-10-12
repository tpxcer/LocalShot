import AppKit

@MainActor
enum CaptureCursors {
    static let rainbowArrow = makeRainbowArrow()

    private static func makeRainbowArrow() -> NSCursor {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: true) { _ in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 1.4, y: 1))
            path.line(to: NSPoint(x: 2.1, y: 13.2))
            path.line(to: NSPoint(x: 5, y: 10))
            path.line(to: NSPoint(x: 7.35, y: 14.4))
            path.line(to: NSPoint(x: 9.5, y: 13.2))
            path.line(to: NSPoint(x: 7.1, y: 8.9))
            path.line(to: NSPoint(x: 12.2, y: 8.7))
            path.close()
            path.lineJoinStyle = .round

            NSColor.white.withAlphaComponent(0.96).setStroke()
            path.lineWidth = 2.4
            path.stroke()
            NSColor.black.withAlphaComponent(0.92).setStroke()
            path.lineWidth = 1.2
            path.stroke()

            path.addClip()
            let colors = [
                NSColor(srgbRed: 1, green: 0.12, blue: 0.18, alpha: 1),
                NSColor(srgbRed: 1, green: 0.55, blue: 0.05, alpha: 1),
                NSColor(srgbRed: 1, green: 0.92, blue: 0.06, alpha: 1),
                NSColor(srgbRed: 0.16, green: 0.86, blue: 0.28, alpha: 1),
                NSColor(srgbRed: 0.05, green: 0.82, blue: 0.95, alpha: 1),
                NSColor(srgbRed: 0.12, green: 0.36, blue: 1, alpha: 1),
                NSColor(srgbRed: 0.84, green: 0.12, blue: 0.92, alpha: 1)
            ]
            NSGradient(colors: colors)?.draw(
                from: NSPoint(x: 1.6, y: 1),
                to: NSPoint(x: 9, y: 15),
                options: []
            )
            return true
        }
        image.isTemplate = false
        return NSCursor(image: image, hotSpot: NSPoint(x: 1.4, y: 1))
    }
}
