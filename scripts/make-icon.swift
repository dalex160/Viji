// Generates Resources/AppIcon.icns and docs/logo.png.
// Usage: swift scripts/make-icon.swift
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func almond(in r: NSRect) -> NSBezierPath {
    let p = NSBezierPath()
    let left = NSPoint(x: r.minX, y: r.midY), right = NSPoint(x: r.maxX, y: r.midY)
    let k = r.width * 0.28
    p.move(to: left)
    p.curve(to: right, controlPoint1: NSPoint(x: r.minX + k, y: r.maxY), controlPoint2: NSPoint(x: r.maxX - k, y: r.maxY))
    p.curve(to: left, controlPoint1: NSPoint(x: r.maxX - k, y: r.minY), controlPoint2: NSPoint(x: r.minX + k, y: r.minY))
    p.close()
    return p
}

func drawIcon(size s: CGFloat) {
    // macOS icon grid: 824/1024 body, centered.
    let inset = s * 100 / 1024
    let body = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let squircle = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)

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
    let horizonY = body.midY
    NSGradient(colors: [color(0x2B6CB0), color(0x13315C)])!
        .draw(in: NSRect(x: body.minX, y: horizonY, width: body.width, height: body.maxY - horizonY), angle: 270)
    NSGradient(colors: [color(0x0B2545), color(0x081A33)])!
        .draw(in: NSRect(x: body.minX, y: body.minY, width: body.width, height: horizonY - body.minY), angle: 270)
    color(0xFFFFFF, 0.35).setFill()
    NSRect(x: body.minX, y: horizonY - s * 0.003, width: body.width, height: s * 0.006).fill()

    let eyeRect = NSRect(x: body.minX + body.width * 0.12, y: horizonY - body.width * 0.2,
                         width: body.width * 0.76, height: body.width * 0.4)
    let eye = almond(in: eyeRect)
    color(0xF4F7FB).setFill()
    eye.fill()

    NSGraphicsContext.saveGraphicsState()
    eye.addClip()
    let c = NSPoint(x: eyeRect.midX, y: eyeRect.midY)
    let irisR = body.width * 0.165
    let iris = NSBezierPath(ovalIn: NSRect(x: c.x - irisR, y: c.y - irisR, width: 2 * irisR, height: 2 * irisR))
    NSGradient(colors: [color(0x5EEAD4), color(0x0F766E)])!.draw(in: iris, relativeCenterPosition: NSPoint(x: 0, y: 0.3))
    let pupilR = irisR * 0.45
    color(0x081A33).setFill()
    NSBezierPath(ovalIn: NSRect(x: c.x - pupilR, y: c.y - pupilR, width: 2 * pupilR, height: 2 * pupilR)).fill()
    let hlR = irisR * 0.17
    color(0xFFFFFF, 0.9).setFill()
    NSBezierPath(ovalIn: NSRect(x: c.x - irisR * 0.42 - hlR, y: c.y + irisR * 0.38 - hlR, width: 2 * hlR, height: 2 * hlR)).fill()
    NSGraphicsContext.restoreGraphicsState()

    color(0x081A33).setStroke()
    eye.lineWidth = s * 0.018
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
