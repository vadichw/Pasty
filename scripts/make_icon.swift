// Renders AppIcon.icns from original vector shapes (no SF Symbols or other third-party artwork):
// a gradient squircle with a stack of sheets held by a clipboard clip.
// Usage: swift scripts/make_icon.swift <output.icns> [preview.png]
import AppKit

let args = CommandLine.arguments
let out = args[1]
let preview = args.count > 2 ? args[2] : nil

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func roundedRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
}

/// Draws the icon in a 1024×1024 coordinate space (y points up).
func drawIcon() {
    // Background squircle with a soft drop shadow.
    let background = roundedRect(100, 100, 824, 824, 185)
    NSGraphicsContext.saveGraphicsState()
    let backgroundShadow = NSShadow()
    backgroundShadow.shadowColor = color(0, 0, 0, 0.30)
    backgroundShadow.shadowBlurRadius = 24
    backgroundShadow.shadowOffset = NSSize(width: 0, height: -10)
    backgroundShadow.set()
    color(0.40, 0.30, 0.92).setFill()
    background.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0.38, 0.60, 1.00), color(0.42, 0.24, 0.90)])!.draw(in: background, angle: -90)

    // Subtle glossy highlight on the upper half.
    NSGraphicsContext.saveGraphicsState()
    background.addClip()
    NSGradient(colors: [color(1, 1, 1, 0.18), color(1, 1, 1, 0)])!
        .draw(in: NSRect(x: 100, y: 512, width: 824, height: 412), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Back sheets of the stack.
    color(1, 1, 1, 0.35).setFill()
    roundedRect(372, 286, 400, 500, 44).fill()
    color(1, 1, 1, 0.60).setFill()
    roundedRect(336, 250, 400, 500, 44).fill()

    // Front sheet with a shadow.
    NSGraphicsContext.saveGraphicsState()
    let sheetShadow = NSShadow()
    sheetShadow.shadowColor = color(0.15, 0.05, 0.40, 0.35)
    sheetShadow.shadowBlurRadius = 30
    sheetShadow.shadowOffset = NSSize(width: 0, height: -14)
    sheetShadow.set()
    color(1, 1, 1).setFill()
    roundedRect(292, 210, 400, 500, 44).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Text lines on the front sheet.
    let lineColor = color(0.47, 0.40, 0.95, 0.55)
    lineColor.setFill()
    for (y, width) in [(560.0, 260.0), (480.0, 300.0), (400.0, 220.0), (320.0, 280.0)] {
        roundedRect(342, CGFloat(y), CGFloat(width), 36, 18).fill()
    }

    // Clipboard clip: a wide base plus a rounded tab with a hole.
    let clipColor = color(0.20, 0.16, 0.42)
    clipColor.setFill()
    let clip = roundedRect(397, 662, 190, 86, 30)
    clip.append(roundedRect(437, 712, 110, 84, 42))
    clip.fill()
    color(1, 1, 1, 0.90).setFill()
    NSBezierPath(ovalIn: NSRect(x: 474, y: 736, width: 36, height: 36)).fill()
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(px) / 1024
    NSGraphicsContext.current!.cgContext.scaleBy(x: scale, y: scale)
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
if let preview {
    try! render(1024).write(to: URL(fileURLWithPath: preview))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out]
try! task.run()
task.waitUntilExit()
exit(task.terminationStatus)
