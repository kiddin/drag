// Draws the README demo: video frames of a window being dragged and resized, and a chart of
// hand speed against sound level. Input comes from `screech-render --demo <dir>`.
// usage: swift scripts/demo.swift <dir>      (writes <dir>/frames/*.png and <dir>/hand.png)
import AppKit

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let W = 1280.0, H = 720.0

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}

func canvas(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSGraphicsContext.current!.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func text(_ s: String, at p: CGPoint, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .white, alignRight: Bool = false) {
    let a = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
    a.draw(at: alignRight ? CGPoint(x: p.x - a.size().width, y: p.y) : p)
}

func background(_ ctx: CGContext) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                       colors: [rgb(0x1B2236).cgColor, rgb(0x3B2C4E).cgColor, rgb(0x7A3B3B).cgColor] as CFArray, locations: [0, 0.6, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])
    // Soft light blobs, like a wallpaper.
    for (x, y, r, c) in [(260.0, 560.0, 380.0, rgb(0x5B6CFF, 0.18)), (1050.0, 160.0, 420.0, rgb(0xFF8A3D, 0.16))] {
        let blob = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [c.cgColor, c.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(blob, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
    }
}

func window(_ ctx: CGContext, _ r: CGRect, title: String) {
    let path = CGPath(roundedRect: r, cornerWidth: 12, cornerHeight: 12, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: NSColor.black.withAlphaComponent(0.55).cgColor)
    ctx.addPath(path); ctx.setFillColor(rgb(0xF6F5F3).cgColor); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    ctx.setFillColor(rgb(0xE4E2DF).cgColor); ctx.fill(CGRect(x: r.minX, y: r.maxY - 34, width: r.width, height: 34))
    // A few lines of "content".
    ctx.setFillColor(rgb(0xD9D6D2).cgColor)
    var y = r.maxY - 70
    var k = 0
    while y > r.minY + 20 {
        let w = (r.width - 48) * [0.82, 0.64, 0.9, 0.48, 0.73][k % 5]
        ctx.fill(CGRect(x: r.minX + 24, y: y, width: w, height: 10)); y -= 26; k += 1
    }
    ctx.restoreGState()
    for (i, c) in [rgb(0xFF5F57), rgb(0xFEBC2E), rgb(0x28C840)].enumerated() {
        ctx.setFillColor(c.cgColor)
        ctx.fillEllipse(in: CGRect(x: r.minX + 14 + CGFloat(i) * 20, y: r.maxY - 23, width: 12, height: 12))
    }
    text(title, at: CGPoint(x: r.midX - 30, y: r.maxY - 26), size: 13, weight: .semibold, color: rgb(0x55524E))
}

func cursor(_ ctx: CGContext, at p: CGPoint, resize: Bool) {
    ctx.saveGState()
    ctx.translateBy(x: p.x, y: p.y)
    let path = CGMutablePath()
    if resize {   // diagonal double arrow
        let pts: [CGPoint] = [(-14, 14), (-14, 4), (-10, 8), (8, -10), (4, -14), (14, -14), (14, -4), (10, -8), (-8, 10), (-4, 14)].map { CGPoint(x: $0.0, y: $0.1) }
        path.addLines(between: pts); path.closeSubpath()
    } else {      // arrow pointer
        let pts: [CGPoint] = [(0, 0), (0, -26), (6, -20), (11, -31), (15, -29), (10, -18), (18, -18)].map { CGPoint(x: $0.0, y: $0.1) }
        path.addLines(between: pts); path.closeSubpath()
    }
    ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 4, color: NSColor.black.withAlphaComponent(0.5).cgColor)
    ctx.addPath(path); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.addPath(path); ctx.setStrokeColor(NSColor.white.cgColor); ctx.setLineWidth(2); ctx.strokePath()
    ctx.restoreGState()
}

// MARK: frames

struct Row { var seg: Int; var material: String; var kind: String; var t: Double; var r: CGRect; var speed: Double; var held: Bool }
let rows: [Row] = try String(contentsOf: dir.appendingPathComponent("frames.csv"), encoding: .utf8)
    .split(separator: "\n").dropFirst().map { line in
        let f = line.split(separator: ",").map(String.init)
        return Row(seg: Int(f[0])!, material: f[1], kind: f[2], t: Double(f[3])!,
                   r: CGRect(x: Double(f[4])!, y: Double(f[5])!, width: Double(f[6])!, height: Double(f[7])!),
                   speed: Double(f[8])!, held: f[9] == "1")
    }

// One mapping per kind, from desktop points to the video, so each scene fits.
var mapping: [String: (scale: Double, dx: Double, dy: Double)] = [:]
for kind in ["drag", "resize"] {
    let rs = rows.filter { $0.kind == kind }.map(\.r)
    let minX = rs.map(\.minX).min()!, maxX = rs.map(\.maxX).max()!, minY = rs.map(\.minY).min()!, maxY = rs.map(\.maxY).max()!
    let scale = min((W - 160) / (maxX - minX), (H - 230) / (maxY - minY))
    let dx = (W - (maxX - minX) * scale) / 2 - minX * scale
    let dy = 110 + (H - 230 - (maxY - minY) * scale) / 2 - minY * scale
    mapping[kind] = (scale, dx, dy)
}

let framesDir = dir.appendingPathComponent("frames")
try? FileManager.default.removeItem(at: framesDir)
try FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)
let segments = Dictionary(grouping: rows, by: \.seg)
for (n, row) in rows.enumerated() {
    let m = mapping[row.kind]!
    // Desktop y grows downwards; the video's grows upwards.
    let r = CGRect(x: row.r.minX * m.scale + m.dx, y: H - (row.r.maxY * m.scale + m.dy), width: row.r.width * m.scale, height: row.r.height * m.scale)
    let png = canvas(Int(W), Int(H)) { ctx in
        background(ctx)
        window(ctx, r, title: row.material)
        if row.held {
            cursor(ctx, at: row.kind == "drag" ? CGPoint(x: r.midX + 40, y: r.maxY - 14) : CGPoint(x: r.maxX - 4, y: r.minY + 4), resize: row.kind == "resize")
        }
        // Scene label.
        let label = "\(row.material) · \(row.kind == "drag" ? "drag" : "resize")"
        let pill = CGRect(x: 40, y: H - 76, width: CGFloat(label.count) * 15 + 40, height: 46)
        ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 23, cornerHeight: 23, transform: nil))
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor); ctx.fillPath()
        text(label, at: CGPoint(x: 60, y: H - 66), size: 24, weight: .semibold)
        text("Screech · sound on", at: CGPoint(x: W - 40, y: H - 66), size: 20, weight: .medium, color: NSColor.white.withAlphaComponent(0.7), alignRight: true)
        // Hand speed meter.
        let track = CGRect(x: 160, y: 40, width: W - 320, height: 14)
        text("hand speed", at: CGPoint(x: 40, y: 34), size: 18, color: NSColor.white.withAlphaComponent(0.75))
        ctx.addPath(CGPath(roundedRect: track, cornerWidth: 7, cornerHeight: 7, transform: nil))
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.15).cgColor); ctx.fillPath()
        let fill = track.width * CGFloat(min(row.speed / 1800, 1))
        if fill > 1 {
            ctx.addPath(CGPath(roundedRect: CGRect(x: track.minX, y: track.minY, width: max(fill, 14), height: track.height), cornerWidth: 7, cornerHeight: 7, transform: nil))
            ctx.setFillColor(rgb(0xFF8A3D).cgColor); ctx.fillPath()
        }
        text("\(Int(row.speed)) pt/s", at: CGPoint(x: W - 40, y: 34), size: 18, color: NSColor.white.withAlphaComponent(0.75), alignRight: true)
    }
    try png.write(to: framesDir.appendingPathComponent(String(format: "%05d.png", n)))
}
_ = segments

// MARK: hand chart

let hand = try String(contentsOf: dir.appendingPathComponent("hand.csv"), encoding: .utf8)
    .split(separator: "\n").dropFirst().map { $0.split(separator: ",").map { Double($0)! } }
let CW = 1600.0, CH = 560.0
let chart = canvas(Int(CW), Int(CH)) { ctx in
    ctx.setFillColor(rgb(0x14161C).cgColor); ctx.fill(CGRect(x: 0, y: 0, width: CW, height: CH))
    let left = 80.0, right = CW - 40, span = hand.last![0]
    func x(_ t: Double) -> CGFloat { left + (right - left) * t / span }
    // Phases of the scripted hand.
    let phases: [(Double, Double, String)] = [(0.25, 1.0, "slow"), (1.0, 1.45, "fling"), (1.45, 1.7, "brake"), (1.7, 2.0, "pause"),
                                              (2.0, 2.45, "jerky"), (2.45, 2.95, "reverse"), (2.95, 3.45, "crawl"), (3.45, span, "let go")]
    for (i, p) in phases.enumerated() {
        if i % 2 == 0 { ctx.setFillColor(NSColor.white.withAlphaComponent(0.04).cgColor); ctx.fill(CGRect(x: x(p.0), y: 40, width: x(p.1) - x(p.0), height: CH - 100)) }
        text(p.2, at: CGPoint(x: x(p.0) + 6, y: CH - 52), size: 18, color: NSColor.white.withAlphaComponent(0.6))
    }
    // Hand speed, top half.
    let speedBase = 300.0, speedTop = 470.0
    ctx.setStrokeColor(rgb(0xFF8A3D).cgColor); ctx.setLineWidth(4); ctx.setLineJoin(.round)
    for (i, row) in hand.enumerated() {
        let p = CGPoint(x: x(row[0]), y: speedBase + (speedTop - speedBase) * min(row[1] / 1800, 1))
        if i == 0 { ctx.move(to: p) } else { ctx.addLine(to: p) }
    }
    ctx.strokePath()
    text("hand speed", at: CGPoint(x: left, y: speedTop + 2), size: 20, weight: .semibold, color: rgb(0xFF8A3D))
    // Sound, bottom half, as a mirrored level.
    let mid = 160.0, amp = 120.0
    let peak = hand.map { $0[2] }.max()!
    ctx.setFillColor(rgb(0x7AA7FF).cgColor)
    for row in hand {
        let h = amp * row[2] / peak
        ctx.fill(CGRect(x: x(row[0]) - 1.2, y: mid - h, width: 2.4, height: max(2 * h, 1)))
    }
    text("sound (wood)", at: CGPoint(x: left, y: mid - amp - 34), size: 20, weight: .semibold, color: rgb(0x7AA7FF))
}
try chart.write(to: dir.appendingPathComponent("hand.png"))
print("Wrote \(rows.count) frames and hand.png to \(dir.path)")
