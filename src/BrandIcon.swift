import AppKit

/// Draws the template mark used by the menu bar and controls.
enum BrandIcon {
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { bounds in
            drawMark(in: bounds.insetBy(dx: 0, dy: 1), color: .black, compact: true)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "AirSkip"
        return image
    }

    static func drawMark(in bounds: NSRect, color: NSColor, compact: Bool = false) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = AffineTransform(translationByX: bounds.minX, byY: bounds.minY)
        (transform as NSAffineTransform).concat()
        NSAffineTransform(transform: AffineTransform(scaleByX: bounds.width / 100,
                                                    byY: bounds.height / 80)).concat()
        color.set()

        // Give the tiny template mark more weight and align its bars to Retina pixels.
        // Larger branding keeps the original proportions.
        let stroke: CGFloat = compact ? 7.5 : 6
        let inset = stroke / 2
        let outline = NSBezierPath(roundedRect: NSRect(x: inset, y: inset,
                                                      width: 100 - stroke, height: 80 - stroke),
                                   xRadius: 25, yRadius: 25)
        outline.lineWidth = stroke
        outline.stroke()

        let seam = NSBezierPath()
        seam.move(to: NSPoint(x: inset, y: compact ? 51.25 : 50))
        seam.line(to: NSPoint(x: 100 - inset, y: compact ? 51.25 : 50))
        seam.lineWidth = stroke
        seam.stroke()

        let play = NSBezierPath()
        play.move(to: NSPoint(x: compact ? 25 : 27, y: compact ? 17.5 : 18))
        play.line(to: NSPoint(x: compact ? 50 : 49, y: 30))
        play.line(to: NSPoint(x: compact ? 25 : 27, y: compact ? 42.5 : 42))
        play.close()
        play.fill()
        let barPositions: [CGFloat] = compact ? [57.5, 72.5] : [58, 71]
        for x in barPositions {
            NSBezierPath(roundedRect: NSRect(x: x, y: compact ? 17.5 : 18,
                                           width: compact ? 7.5 : 7, height: compact ? 25 : 24),
                         xRadius: compact ? 0 : 1.5, yRadius: compact ? 0 : 1.5).fill()
        }
    }
}
