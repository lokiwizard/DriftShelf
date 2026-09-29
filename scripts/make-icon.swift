import AppKit
import Foundation

let out = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let factor = CGFloat(pixels) / 512
        let transform = NSAffineTransform()
        transform.scale(by: factor)
        transform.concat()
        let shape = NSBezierPath(roundedRect: NSRect(x: 36, y: 36, width: 440, height: 440), xRadius: 100, yRadius: 100)
        NSGradient(colors: [NSColor(srgbRed: 0.17, green: 0.12, blue: 0.48, alpha: 1), NSColor(srgbRed: 0.20, green: 0.40, blue: 0.82, alpha: 1), NSColor(srgbRed: 0.23, green: 0.79, blue: 0.89, alpha: 1)])!.draw(in: shape, angle: 55)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        NSGradient(starting: NSColor.white.withAlphaComponent(0.20), ending: NSColor.white.withAlphaComponent(0))!.draw(in: NSBezierPath(ovalIn: NSRect(x: 130, y: 270, width: 490, height: 330)), relativeCenterPosition: .zero)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.28).setStroke()
        shape.lineWidth = 2
        shape.stroke()

        // Two lifted sheets, with a quiet offset instead of a generic download arrow.
        NSGraphicsContext.saveGraphicsState()
        let tilt = NSAffineTransform()
        tilt.translateX(by: 250, yBy: 284)
        tilt.rotate(byDegrees: 12)
        tilt.translateX(by: -250, yBy: -284)
        tilt.concat()
        let back = NSBezierPath(roundedRect: NSRect(x: 156, y: 190, width: 178, height: 200), xRadius: 20, yRadius: 20)
        NSColor(srgbRed: 0.62, green: 0.83, blue: 1, alpha: 0.80).setFill()
        back.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(srgbRed: 0.05, green: 0.08, blue: 0.30, alpha: 0.32)
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -9)
        shadow.set()
        let paper = NSBezierPath(roundedRect: NSRect(x: 187, y: 188, width: 170, height: 198), xRadius: 20, yRadius: 20)
        NSGradient(starting: .white, ending: NSColor(srgbRed: 0.80, green: 0.91, blue: 1, alpha: 1))!.draw(in: paper, angle: -90)
        NSGraphicsContext.restoreGraphicsState()
        NSColor(srgbRed: 0.43, green: 0.62, blue: 0.85, alpha: 0.46).setFill()
        NSBezierPath(roundedRect: NSRect(x: 216, y: 332, width: 79, height: 10), xRadius: 5, yRadius: 5).fill()
        NSBezierPath(roundedRect: NSRect(x: 216, y: 307, width: 110, height: 9), xRadius: 4.5, yRadius: 4.5).fill()

        // A translucent pocket gathers the papers into one portable shelf.
        let pocket = NSBezierPath()
        pocket.move(to: NSPoint(x: 112, y: 256))
        pocket.curve(to: NSPoint(x: 130, y: 274), controlPoint1: NSPoint(x: 112, y: 267), controlPoint2: NSPoint(x: 119, y: 274))
        pocket.line(to: NSPoint(x: 203, y: 274))
        pocket.curve(to: NSPoint(x: 228, y: 252), controlPoint1: NSPoint(x: 213, y: 274), controlPoint2: NSPoint(x: 216, y: 252))
        pocket.line(to: NSPoint(x: 284, y: 252))
        pocket.curve(to: NSPoint(x: 309, y: 274), controlPoint1: NSPoint(x: 296, y: 252), controlPoint2: NSPoint(x: 299, y: 274))
        pocket.line(to: NSPoint(x: 382, y: 274))
        pocket.curve(to: NSPoint(x: 400, y: 256), controlPoint1: NSPoint(x: 393, y: 274), controlPoint2: NSPoint(x: 400, y: 267))
        pocket.line(to: NSPoint(x: 390, y: 148))
        pocket.curve(to: NSPoint(x: 360, y: 120), controlPoint1: NSPoint(x: 388, y: 130), controlPoint2: NSPoint(x: 378, y: 120))
        pocket.line(to: NSPoint(x: 152, y: 120))
        pocket.curve(to: NSPoint(x: 122, y: 148), controlPoint1: NSPoint(x: 134, y: 120), controlPoint2: NSPoint(x: 124, y: 130))
        pocket.close()
        NSGradient(starting: NSColor(srgbRed: 0.68, green: 0.88, blue: 1, alpha: 0.93), ending: NSColor(srgbRed: 0.40, green: 0.55, blue: 0.95, alpha: 0.90))!.draw(in: pocket, angle: -90)
        NSColor.white.withAlphaComponent(0.72).setStroke()
        pocket.lineWidth = 3
        pocket.stroke()
        NSColor.white.withAlphaComponent(0.87).setFill()
        NSBezierPath(roundedRect: NSRect(x: 230, y: 162, width: 52, height: 9), xRadius: 4.5, yRadius: 4.5).fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(size)x\(size)\(suffix).png"))
    }
}
