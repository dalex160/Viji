// Generates Resources/AppIcon.icns and docs/logo.png.
// Usage: swift scripts/make-icon.swift
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func circle(_ c: NSPoint, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
}

/// An eye whose lower lid is a "V" and whose iris is the dot of an "i".
func drawIcon(size s: CGFloat) {
    // macOS icon grid: 824/1024 body, centered.
    let inset = s * 100 / 1024
    let body = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let w = body.width
    let squircle = NSBezierPath(roundedRect: body, xRadius: w * 0.225, yRadius: w * 0.225)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.35)
    shadow.shadowBlurRadius = s * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.008)
    shadow.set()
    color(0x0B2545).setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    NSGradient(colors: [color(0x2B6CB0), color(0x13315C), color(0x081A33)])!.draw(in: body, angle: 270)

    let c = NSPoint(x: body.midX, y: body.midY + w * 0.04)
    let hw = w * 0.38
    let eye = NSBezierPath()
    eye.move(to: NSPoint(x: c.x - hw, y: c.y))
    eye.curve(to: NSPoint(x: c.x + hw, y: c.y),
              controlPoint1: NSPoint(x: c.x - hw * 0.45, y: c.y + w * 0.27),
              controlPoint2: NSPoint(x: c.x + hw * 0.45, y: c.y + w * 0.27))
    eye.line(to: NSPoint(x: c.x, y: c.y - w * 0.3))
    eye.close()
    color(0xF4F7FB).setFill()
    eye.fill()

    NSGraphicsContext.saveGraphicsState()
    eye.addClip()
    let irisC = NSPoint(x: c.x, y: c.y + w * 0.03)
    let irisR = w * 0.11
    NSGradient(colors: [color(0x5EEAD4), color(0x0F766E)])!
        .draw(in: circle(irisC, irisR), relativeCenterPosition: NSPoint(x: 0, y: 0.3))
    color(0x081A33).setFill()
    circle(irisC, irisR * 0.45).fill()
    color(0xFFFFFF, 0.9).setFill()
    circle(NSPoint(x: irisC.x - irisR * 0.42, y: irisC.y + irisR * 0.38), irisR * 0.17).fill()
    let stem = NSBezierPath()
    stem.move(to: NSPoint(x: c.x, y: c.y - w * 0.17))
    stem.line(to: NSPoint(x: c.x, y: c.y - w * 0.11))
    stem.lineWidth = w * 0.055
    stem.lineCapStyle = .round
    color(0x0F766E).setStroke()
    stem.stroke()
    NSGraphicsContext.restoreGraphicsState()

    color(0x081A33).setStroke()
    eye.lineWidth = w * 0.022
    eye.lineJoinStyle = .round
    eye.stroke()
    NSGraphicsContext.restoreGraphicsState()
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(size: CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let fm = FileManager.default
let iconset = fm.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try fm.createDirectory(at: root.appendingPathComponent("Resources"), withIntermediateDirectories: true)
try fm.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: true)
let icns = root.appendingPathComponent("Resources/AppIcon.icns").path
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", icns]
try task.run()
task.waitUntilExit()
try png(size: 512).write(to: root.appendingPathComponent("docs/logo.png"))
print("Wrote \(icns) and docs/logo.png")
