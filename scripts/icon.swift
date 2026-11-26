// Draws Resources/AppIcon.icns and Resources/AppIcon.png.
// usage: swift scripts/icon.swift [skid|wood|sparks] [--preview <dir>]
import AppKit

let args = CommandLine.arguments
let style = args.dropFirst().first { !$0.hasPrefix("--") && !$0.hasPrefix("/") } ?? "skid"
let previewDir = args.firstIndex(of: "--preview").map { args[$0 + 1] }

struct Rng {
    var s: UInt64
    mutating func next() -> CGFloat {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((s >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
    }
}

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}

func linear(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

/// A macOS window centred at the origin.
func window(_ ctx: CGContext, size: CGSize, body: CGColor, bar: CGColor, outline: CGColor? = nil, lineWidth: CGFloat = 0, lights: Bool = true) {
    let r = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
    let path = CGPath(roundedRect: r, cornerWidth: 40, cornerHeight: 40, transform: nil)
    if let outline {
        ctx.addPath(path); ctx.setStrokeColor(outline); ctx.setLineWidth(lineWidth); ctx.strokePath()
        ctx.move(to: CGPoint(x: r.minX, y: r.maxY - 80)); ctx.addLine(to: CGPoint(x: r.maxX, y: r.maxY - 80)); ctx.strokePath()
    } else {
        ctx.addPath(path); ctx.setFillColor(body); ctx.fillPath()
        ctx.saveGState(); ctx.addPath(path); ctx.clip()
        ctx.setFillColor(bar); ctx.fill(CGRect(x: r.minX, y: r.maxY - 74, width: r.width, height: 74))
        ctx.restoreGState()
    }
    guard lights else { return }
    for (i, c) in [rgb(0xFF5F57), rgb(0xFEBC2E), rgb(0x28C840)].enumerated() {
        ctx.setFillColor(c)
        ctx.fillEllipse(in: CGRect(x: r.minX + 32 + CGFloat(i) * 44, y: r.maxY - (outline == nil ? 52 : 56), width: 28, height: 28))
    }
}

func grain(_ ctx: CGContext, count: Int, seed: UInt64, dark: CGFloat, light: CGFloat) {
    var rng = Rng(s: seed)
    for _ in 0..<count {
        let x = 100 + rng.next() * 824, y = 100 + rng.next() * 824, d = 1.5 + rng.next() * 3.5
        ctx.setFillColor(rng.next() < 0.5 ? CGColor(gray: 0, alpha: dark * rng.next()) : CGColor(gray: 1, alpha: light * rng.next()))
        ctx.fillEllipse(in: CGRect(x: x, y: y, width: d, height: d))
    }
}

func drawSkid(_ ctx: CGContext) {
    linear(ctx, [rgb(0xE4E0D8), rgb(0xA8A298)], from: CGPoint(x: 300, y: 924), to: CGPoint(x: 724, y: 100))
    grain(ctx, count: 9000, seed: 7, dark: 0.16, light: 0.25)
    // Two rubber streaks curving in from the bottom left, darkest where the window is now.
    var rng = Rng(s: 3)
    for offset in [CGFloat(-62), 62] {
        let n = 90
        for i in 0..<n {
            let t0 = CGFloat(i) / CGFloat(n), t1 = CGFloat(i + 1) / CGFloat(n)
            func p(_ t: CGFloat) -> CGPoint {
                // Quadratic curve; the offset is applied along the normal.
                let a = CGPoint(x: 40, y: 150), c = CGPoint(x: 330, y: 260), b = CGPoint(x: 560, y: 520)
                let x = (1 - t) * (1 - t) * a.x + 2 * (1 - t) * t * c.x + t * t * b.x
                let y = (1 - t) * (1 - t) * a.y + 2 * (1 - t) * t * c.y + t * t * b.y
                let dx = 2 * (1 - t) * (c.x - a.x) + 2 * t * (b.x - c.x), dy = 2 * (1 - t) * (c.y - a.y) + 2 * t * (b.y - c.y)
                let len = (dx * dx + dy * dy).squareRoot()
                return CGPoint(x: x - dy / len * offset, y: y + dx / len * offset)
            }
            for lane in 0..<7 {
                let w = CGFloat(lane - 3) * 7
                let a0 = p(t0), a1 = p(t1)
                ctx.setStrokeColor(CGColor(gray: 0.08, alpha: (0.15 + 0.75 * t0 * t0) * (0.55 + 0.45 * rng.next())))
                ctx.setLineWidth(12)
                ctx.move(to: CGPoint(x: a0.x + w * 0.7, y: a0.y - w * 0.7))
                ctx.addLine(to: CGPoint(x: a1.x + w * 0.7, y: a1.y - w * 0.7))
                ctx.strokePath()
            }
        }
    }
    ctx.saveGState()
    ctx.translateBy(x: 615, y: 590); ctx.rotate(by: 0.22)
    ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 34, color: CGColor(gray: 0, alpha: 0.45))
    window(ctx, size: CGSize(width: 420, height: 330), body: rgb(0x1F1F23), bar: rgb(0x34343A))
    ctx.restoreGState()
}

func drawWood(_ ctx: CGContext) {
    linear(ctx, [rgb(0xD39555), rgb(0xA4612D), rgb(0x7A421C)], from: CGPoint(x: 100, y: 924), to: CGPoint(x: 924, y: 100))
    var rng = Rng(s: 11)
    for i in 0..<46 {
        let y0 = 70 + CGFloat(i) * 20 + rng.next() * 10
        let ph = rng.next() * 6, ph2 = rng.next() * 6
        ctx.setStrokeColor(CGColor(srgbRed: 0.33, green: 0.16, blue: 0.05, alpha: 0.12 + 0.22 * rng.next()))
        ctx.setLineWidth(2 + rng.next() * 6)
        ctx.move(to: CGPoint(x: 80, y: y0))
        for x in stride(from: CGFloat(80), through: 950, by: 8) {
            let knot = 60 * exp(-pow((x - 330) / 120, 2) - pow((y0 - 700) / 110, 2))
            ctx.addLine(to: CGPoint(x: x, y: y0 + 14 * sin(x / 160 + ph) + 5 * sin(x / 41 + ph2) + knot))
        }
        ctx.strokePath()
    }
    // Pale scratches the window left behind.
    for (y, w) in [(CGFloat(430), CGFloat(10)), (470, 6), (505, 8)] {
        ctx.setStrokeColor(rgb(0xF6DDB8, 0.55)); ctx.setLineWidth(w); ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: 150, y: y - 40)); ctx.addLine(to: CGPoint(x: 470, y: y)); ctx.strokePath()
    }
    // Motion ghosts, then the window.
    for k in (1...3).reversed() {
        ctx.saveGState()
        ctx.translateBy(x: 620 - CGFloat(k) * 55, y: 560 - CGFloat(k) * 7); ctx.rotate(by: 0.08)
        ctx.setAlpha(0.13 * CGFloat(4 - k))
        window(ctx, size: CGSize(width: 400, height: 320), body: rgb(0xFFFFFF), bar: rgb(0xFFFFFF), lights: false)
        ctx.restoreGState()
    }
    ctx.saveGState()
    ctx.translateBy(x: 620, y: 560); ctx.rotate(by: 0.08)
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: CGColor(gray: 0, alpha: 0.4))
    window(ctx, size: CGSize(width: 400, height: 320), body: rgb(0xFFFFFF), bar: rgb(0xE9E6E1))
    ctx.restoreGState()
}

func drawSparks(_ ctx: CGContext) {
    linear(ctx, [rgb(0x2C2C31), rgb(0x0B0B0D)], from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100))
    // Speed lines.
    ctx.setLineCap(.round)
    for (y, x0, w) in [(CGFloat(700), CGFloat(200), CGFloat(24)), (630, 150, 24), (560, 230, 24)] {
        ctx.setStrokeColor(rgb(0xFF7A1A, 0.9)); ctx.setLineWidth(w)
        ctx.move(to: CGPoint(x: x0, y: y)); ctx.addLine(to: CGPoint(x: 340, y: y)); ctx.strokePath()
    }
    ctx.saveGState()
    ctx.translateBy(x: 590, y: 580); ctx.rotate(by: -0.05)
    window(ctx, size: CGSize(width: 400, height: 320), body: rgb(0), bar: rgb(0), outline: rgb(0xFFFFFF), lineWidth: 30)
    ctx.restoreGState()
    // Sparks thrown from the front corner where the window grinds.
    var rng = Rng(s: 5)
    let origin = CGPoint(x: 395, y: 425)
    for i in 0..<14 {
        let a = CGFloat.pi * 0.52 + CGFloat(i) / 13 * 0.5 * CGFloat.pi + (rng.next() - 0.5) * 0.12
        let r0 = 20 + rng.next() * 25, r1 = r0 + 60 + rng.next() * 120
        ctx.setStrokeColor(i % 3 == 0 ? rgb(0xFFD27A) : rgb(0xFF7A1A)); ctx.setLineWidth(6 + rng.next() * 8)
        ctx.move(to: CGPoint(x: origin.x + cos(a) * r0, y: origin.y - sin(a) * r0 * 0.9))
        ctx.addLine(to: CGPoint(x: origin.x + cos(a) * r1, y: origin.y - sin(a) * r1 * 0.9))
        ctx.strokePath()
    }
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.3))
    ctx.addPath(squircle); ctx.setFillColor(CGColor(gray: 0.5, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()
    switch style {
    case "wood": drawWood(ctx)
    case "sparks": drawSparks(ctx)
    default: drawSkid(ctx)
    }
    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

if let previewDir {
    try render(512).write(to: URL(fileURLWithPath: previewDir).appendingPathComponent("icon-\(style).png"))
    exit(0)
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try render(1024).write(to: root.appendingPathComponent("Resources/AppIcon.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns (\(style))" : "iconutil failed")
