import AppKit

// Draw a native vector icon at each required size; no image dependencies.
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = NSAffineTransform()
        transform.scale(by: CGFloat(pixels) / 1024)
        transform.concat()

        let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 205, yRadius: 205)
        NSGradient(starting: NSColor(calibratedRed: 0.23, green: 0.31, blue: 0.95, alpha: 1),
                   ending: NSColor(calibratedRed: 0.48, green: 0.25, blue: 0.88, alpha: 1))!.draw(in: tile, angle: -45)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: 220, y: 332, width: 405, height: 360), xRadius: 85, yRadius: 85).fill()
        let lens = NSBezierPath()
        lens.move(to: NSPoint(x: 658, y: 593))
        lens.line(to: NSPoint(x: 799, y: 667))
        lens.curve(to: NSPoint(x: 825, y: 649), controlPoint1: NSPoint(x: 815, y: 676), controlPoint2: NSPoint(x: 825, y: 666))
        lens.line(to: NSPoint(x: 825, y: 375))
        lens.curve(to: NSPoint(x: 799, y: 357), controlPoint1: NSPoint(x: 825, y: 357), controlPoint2: NSPoint(x: 815, y: 348))
        lens.line(to: NSPoint(x: 658, y: 431))
        lens.close()
        lens.fill()
        NSColor(calibratedRed: 0.40, green: 0.95, blue: 0.76, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 290, y: 555, width: 70, height: 70)).fill()

        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let url = directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}
