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
