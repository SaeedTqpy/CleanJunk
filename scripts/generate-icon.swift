import AppKit
import Foundation

// Deterministic, vector-drawn original CleanJunk icon. No third-party assets.
guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift scripts/generate-icon.swift <iconset-folder>\n", stderr)
    exit(2)
}

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: r, green: g, blue: b, alpha: alpha)
}

func drawIcon(pixelSize: Int) throws -> Data {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelSize,
                                    pixelsHigh: pixelSize, bitsPerSample: 8,
                                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                    colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                    bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: rep) else {
        throw NSError(domain: "CleanJunkIcon", code: 1)
    }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.scaleBy(x: CGFloat(pixelSize) / 1024,
                              y: CGFloat(pixelSize) / 1024)

    let shape = NSBezierPath(roundedRect: NSRect(x: 46, y: 46, width: 932, height: 932),
                             xRadius: 232, yRadius: 232)
    NSGradient(starting: color(0.085, 0.165, 0.190),
               ending: color(0.035, 0.080, 0.105))!.draw(in: shape, angle: -44)

    let glow = NSBezierPath(ovalIn: NSRect(x: 360, y: 475, width: 620, height: 600))
    color(0.29, 0.81, 0.71, 0.09).setFill()
    shape.addClip()
    glow.fill()

    let disk = NSBezierPath(roundedRect: NSRect(x: 208, y: 234, width: 608, height: 550),
                            xRadius: 112, yRadius: 112)
    color(0.13, 0.34, 0.37).setFill()
    disk.fill()
    disk.lineWidth = 16
    color(0.44, 0.91, 0.79, 0.52).setStroke()
    disk.stroke()

    let open = NSBezierPath()
    open.lineWidth = 42
    open.lineCapStyle = .round
    open.lineJoinStyle = .round
    open.move(to: NSPoint(x: 409, y: 597))
    open.line(to: NSPoint(x: 340, y: 517))
    open.line(to: NSPoint(x: 409, y: 437))
    open.move(to: NSPoint(x: 611, y: 597))
    open.line(to: NSPoint(x: 680, y: 517))
    open.line(to: NSPoint(x: 611, y: 437))
    color(0.84, 1.00, 0.94).setStroke()
    open.stroke()

    let slash = NSBezierPath()
    slash.lineWidth = 36
    slash.lineCapStyle = .round
    slash.move(to: NSPoint(x: 565, y: 632))
    slash.line(to: NSPoint(x: 460, y: 401))
    color(0.40, 0.96, 0.79).setStroke()
    slash.stroke()

    let sparkle = NSBezierPath()
    sparkle.lineWidth = 20
    sparkle.lineCapStyle = .round
    sparkle.move(to: NSPoint(x: 760, y: 880))
    sparkle.line(to: NSPoint(x: 760, y: 803))
    sparkle.move(to: NSPoint(x: 720, y: 841))
    sparkle.line(to: NSPoint(x: 800, y: 841))
    NSColor.white.setStroke()
    sparkle.stroke()

    context.flushGraphics()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "CleanJunkIcon", code: 2)
    }
    return data
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let suffix = scale == 2 ? "@2x" : ""
        let name = "icon_\(size)x\(size)\(suffix).png"
        try drawIcon(pixelSize: pixels).write(to: folder.appendingPathComponent(name), options: .atomic)
    }
}
print("Rendered original iconset at \(folder.path)")
