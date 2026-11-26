import Foundation
import ScreechDSP

// Usage: screech-render [output-dir]
// Writes <material>-drag.wav and <material>-resize.wav for every material.

func stats(_ x: [Float]) -> (peak: Float, rms: Float) {
    var peak: Float = 0
    var sum: Double = 0
    for v in x {
        peak = max(peak, abs(v))
        sum += Double(v * v)
    }
    return (peak, Float((sum / Double(max(x.count, 1))).squareRoot()))
}

// screech-render --analyze : steady-state loudness (rms) and zero-crossing rate per speed.
if CommandLine.arguments.contains("--analyze") {
    let sr: Float = 48000
    let speeds: [Float] = [40, 150, 400, 800, 1500, 3000]
    // --linear: render at 1/10 level (far below the clipper) and scale back up.
    let linear = CommandLine.arguments.contains("--linear")
    let mats = Materials.all.map { m -> Material in var m = m; if linear { m.level *= 0.1 }; return m }
    for (index, material) in mats.enumerated() {
        for mode in [MotionMode.drag, .resize] {
            var line = "\(material.id) \(mode == .drag ? "drag  " : "resize")"
            for v in speeds {
                let synth = Synth(sampleRate: sr, materials: mats,
                                  samples: DragSamples.load(from: URL(fileURLWithPath: "Resources/Samples"), materials: mats))
                synth.control.material = index
                synth.control.volume = 1
                synth.control.mode = mode
                synth.control.speed = v
                synth.control.grow = 1
                let n = Int(sr)
                var l = [Float](repeating: 0, count: n), r = [Float](repeating: 0, count: n)
                l.withUnsafeMutableBufferPointer { lp in
                    r.withUnsafeMutableBufferPointer { rp in
                        var o = 0
                        while o < n { synth.render(left: lp.baseAddress! + o, right: rp.baseAddress! + o, frames: 512); o += 512 }
                    }
                }
                let x = zip(l, r).map { $0 + $1 }.suffix(n / 2)
                var zc = 0
                var prev: Float = 0
                for v in x { if (v < 0) != (prev < 0) { zc += 1 }; prev = v }
                line += String(format: "  %4.0f:%.3f/%5d", v, stats(Array(x)).rms * (linear ? 10 : 1), zc * 2)
            }
            print(line)
        }
    }
    exit(0)
}

// screech-render --demo <dir> : data for the README demo video (see scripts/demo.swift).
// Writes audio.wav (every segment back to back), frames.csv (window per video frame) and
// hand.csv (hand speed vs sound level for the wood drag, every 10 ms).
if let i = CommandLine.arguments.firstIndex(of: "--demo"), i + 1 < CommandLine.arguments.count {
    let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let samples = DragSamples.load(from: URL(fileURLWithPath: "Resources/Samples"))
    let segments: [(String, DemoMotion.Kind)] = [("wood", .drag), ("metal", .drag), ("stone", .drag), ("glass", .drag),
                                                 ("rubber", .drag), ("rubber", .resize), ("metal", .resize)]
    let sr = 48000, fps = 30.0, gap = 0.5
    var left: [Float] = [], right: [Float] = []
    var csv = "segment,material,kind,time,x,y,width,height,speed,held\n"
    var hand = "time,speed,level\n"
    for (index, (id, kind)) in segments.enumerated() {
        // A calm hand at the app's default volume, like a real drag, not the edge-case gesture.
        let (l, r) = OfflineRender.gesture(kind, material: Materials.index(of: id), style: .smooth, volume: 0.7, samples: samples)
        let start = Double(left.count) / Double(sr)
        left += l + [Float](repeating: 0, count: Int(gap * Double(sr)))
        right += r + [Float](repeating: 0, count: Int(gap * Double(sr)))
        let frames = DemoMotion.frames(kind, style: .smooth)
        let length = Double(l.count) / Double(sr) + gap
        let name = Materials.all[Materials.index(of: id)].name
        var t = 0.0
        while t < length {
            let f = frames.last { $0.time <= t }?.frame ?? frames[0].frame
            let held = t < DemoMotion.duration
            let v = held ? DemoMotion.profile(t, style: .smooth).speed : 0
            csv += String(format: "%d,%@,%@,%.4f,%.1f,%.1f,%.1f,%.1f,%.1f,%d\n", index, name,
                          kind == .drag ? "drag" : "resize", start + t, f.x, f.y, f.width, f.height, v, held ? 1 : 0)
            t += 1 / fps
        }
    }
    // The chart uses the uneven gesture: it shows more of how the sound follows the hand.
    let (hl, hr) = OfflineRender.gesture(.drag, material: Materials.index(of: "wood"), volume: 0.7, samples: samples)
    let hop = sr / 100
    for k in 0..<(hl.count / hop) {
        let tt = Double(k) / 100
        var peak: Float = 0
        for j in (k * hop)..<((k + 1) * hop) { peak = max(peak, abs(hl[j]), abs(hr[j])) }
        hand += String(format: "%.2f,%.1f,%.4f\n", tt, tt < DemoMotion.duration ? DemoMotion.profile(tt).speed : 0, peak)
    }
    // Bring the whole track up to -1 dBFS peak with plain gain: louder, with no added distortion.
    let peak = zip(left, right).reduce(Float(0)) { max($0, abs($1.0), abs($1.1)) }
    let gain = peak > 0 ? 0.89 / peak : 1
    left = left.map { $0 * gain }
    right = right.map { $0 * gain }
    try OfflineRender.wav(left: left, right: right, sampleRate: sr).write(to: dir.appendingPathComponent("audio.wav"))
    try csv.write(to: dir.appendingPathComponent("frames.csv"), atomically: true, encoding: .utf8)
    try hand.write(to: dir.appendingPathComponent("hand.csv"), atomically: true, encoding: .utf8)
    print("Wrote demo data to \(dir.path): \(String(format: "%.1f", Double(left.count) / Double(sr))) s")
    exit(0)
}

// screech-render [output-dir] [--ring 0...1]
var args = Array(CommandLine.arguments.dropFirst())
var ring: Float = 1
if let i = args.firstIndex(of: "--ring"), i + 1 < args.count {
    ring = Float(args[i + 1]) ?? 1
    args.removeSubrange(i...(i + 1))
}
// Recorded drag sounds; --synth renders the synthesized scrape instead.
let samples = CommandLine.arguments.contains("--synth") ? [:]
    : DragSamples.load(from: URL(fileURLWithPath: "Resources/Samples"))
args.removeAll { $0 == "--synth" }
let outDir = URL(fileURLWithPath: args.first ?? "previews")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

print("file                     peak    rms")
for (index, material) in Materials.all.enumerated() {
    for (kind, label) in [(DemoMotion.Kind.drag, "drag"), (.resize, "resize")] {
        let (l, r) = OfflineRender.gesture(kind, material: index, ring: ring, samples: samples)
        let name = "\(material.id)-\(label).wav"
        try OfflineRender.wav(left: l, right: r, sampleRate: 48000).write(to: outDir.appendingPathComponent(name))
        let mono = zip(l, r).map { ($0 + $1) * 0.5 }
        let s = stats(mono)
        print(name.padding(toLength: 24, withPad: " ", startingAt: 0), String(format: "%.3f  %.3f", s.peak, s.rms))
    }
}
print("Wrote previews to \(outDir.path)")
