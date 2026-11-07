// Draws the compass app icon and writes an .iconset folder for iconutil, or with --web the PNGs
// for the web app (icon-192/512 plus a full-bleed maskable-512 for Android).
// Usage: swift scripts/make_icon.swift OUT.iconset
//        swift scripts/make_icon.swift --web OUT_DIR
import AppKit

enum Style { case mac, web, maskable }

let web = CommandLine.arguments[1] == "--web"
let out = URL(fileURLWithPath: CommandLine.arguments[web ? 2 : 1], isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int, _ style: Style = .mac) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)

    // macOS icon grid: the tile is inset ~10% with a ~22% corner radius. Android crops
    // maskable icons to its own shape, keeping only the central 80% circle.
    let inset: CGFloat = style == .mac ? 0.1 : style == .web ? 0.02 : 0
    let tile = NSRect(x: s * inset, y: s * inset, width: s * (1 - 2 * inset), height: s * (1 - 2 * inset))
    let radius = style == .maskable ? 0 : tile.width * 0.225
    NSGradient(colors: [
        NSColor(red: 0.08, green: 0.72, blue: 0.65, alpha: 1),
        NSColor(red: 0.06, green: 0.46, blue: 0.43, alpha: 1),
    ])!.draw(in: NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius), angle: -90)

    let c = NSPoint(x: tile.midX, y: tile.midY)
    let r = (style == .maskable ? s * 0.27 : tile.width * 0.33)

    let ring = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    ring.lineWidth = r * 0.12
    NSColor(white: 1, alpha: 0.92).setStroke()
    ring.stroke()

    // Tick marks at N, E, S, W.
    NSColor(white: 1, alpha: 0.92).setFill()
    for i in 0..<4 {
        let a = CGFloat(i) * .pi / 2
        let tick = NSBezierPath()
        tick.lineWidth = r * 0.08
        tick.move(to: NSPoint(x: c.x + cos(a) * r * 0.62, y: c.y + sin(a) * r * 0.62))
        tick.line(to: NSPoint(x: c.x + cos(a) * r * 0.78, y: c.y + sin(a) * r * 0.78))
        NSColor(white: 1, alpha: 0.7).setStroke()
        tick.stroke()
    }

    // The needle points up and to the right: forward and upward.
    let angle: CGFloat = .pi / 4
    let len = r * 0.82, half = r * 0.17
    func pt(_ along: CGFloat, _ across: CGFloat) -> NSPoint {
        NSPoint(x: c.x + cos(angle) * along - sin(angle) * across,
                y: c.y + sin(angle) * along + cos(angle) * across)
    }
    let north = NSBezierPath()
    north.move(to: pt(len, 0)); north.line(to: pt(0, half)); north.line(to: pt(0, -half)); north.close()
    NSColor(red: 0.98, green: 0.75, blue: 0.14, alpha: 1).setFill()
    north.fill()
    let south = NSBezierPath()
    south.move(to: pt(-len, 0)); south.line(to: pt(0, half)); south.line(to: pt(0, -half)); south.close()
    NSColor(red: 1.0, green: 0.98, blue: 0.94, alpha: 1).setFill()
    south.fill()
    let hub = NSBezierPath(ovalIn: NSRect(x: c.x - half * 0.45, y: c.y - half * 0.45, width: half * 0.9, height: half * 0.9))
    NSColor(red: 0.06, green: 0.46, blue: 0.43, alpha: 1).setFill()
    hub.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

if web {
    try render(192, .web).write(to: out.appendingPathComponent("icon-192.png"))
    try render(512, .web).write(to: out.appendingPathComponent("icon-512.png"))
    try render(512, .maskable).write(to: out.appendingPathComponent("maskable-512.png"))
} else {
    for size in [16, 32, 128, 256, 512] {
        try render(size).write(to: out.appendingPathComponent("icon_\(size)x\(size).png"))
        try render(size * 2).write(to: out.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
    }
}
