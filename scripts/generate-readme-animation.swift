#!/usr/bin/env swift
// Run from the repository root: swift scripts/generate-readme-animation.swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("assets/case-demo.gif")
let width = 800
let height = 340
let size = NSSize(width: width, height: height)
let background = NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.98, alpha: 1)
let ink = NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.20, alpha: 1)
let blue = NSColor(calibratedRed: 0.12, green: 0.40, blue: 0.93, alpha: 1)

struct Frame {
    let pose: Int
    let skipping: Bool
    let delay: Double
}
// Begin closed, open and hold, then close and hold before repeating.
let frames = [Frame(pose: 0, skipping: false, delay: 1.4)]
    + (1...30).map { Frame(pose: $0, skipping: true, delay: $0 == 30 ? 2.0 : 0.03) }
    + (0...29).reversed().map { Frame(pose: $0, skipping: false, delay: $0 == 0 ? 0.5 : 0.03) }

guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
    fatalError("Cannot create GIF destination")
}
CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)

func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color
    ])
}

for frame in frames {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    background.setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

    let source = root.appendingPathComponent(String(format: "src/animation/case-0-%02d.png", frame.pose))
    guard let image = NSImage(contentsOf: source) else { fatalError("Missing frame: \(source.path)") }
    image.draw(in: NSRect(x: 10, y: 26, width: 360, height: 288), from: .zero,
               operation: .sourceOver, fraction: 1)

    text("AIRSKIP", x: 410, y: 277, size: 13, weight: .bold, color: .secondaryLabelColor)
    let iconColor = frame.skipping ? blue : NSColor(calibratedWhite: 0.65, alpha: 1)
    iconColor.setFill()
    for x: CGFloat in [410, 435] {
        let triangle = NSBezierPath()
        triangle.move(to: NSPoint(x: x, y: 204))
        triangle.line(to: NSPoint(x: x + 23, y: 219))
        triangle.line(to: NSPoint(x: x, y: 234))
        triangle.close()
        triangle.fill()
    }
    text(frame.skipping ? "Open case" : "Close case", x: 410, y: 156, size: 30, weight: .bold, color: ink)
    text(frame.skipping ? "Start skipping" : "Stop skipping", x: 410, y: 119, size: 24, weight: .medium,
         color: frame.skipping ? blue : ink)
    text("Your AirPods case. Your video remote.", x: 410, y: 68, size: 16, weight: .regular, color: .darkGray)
    NSGraphicsContext.restoreGraphicsState()
    CGImageDestinationAddImage(destination, bitmap.cgImage!, [
        kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: frame.delay]
    ] as CFDictionary)
}
guard CGImageDestinationFinalize(destination) else { fatalError("GIF encoding failed") }
print("Created \(output.path)")
