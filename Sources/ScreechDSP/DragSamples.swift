import Foundation

/// A real recording of something being dragged, used as the drag sound of one material.
public struct DragSample: Sendable {
    public let samples: [Float]
    public let sampleRate: Float

    public init(samples: [Float], sampleRate: Float) {
        self.samples = samples
        self.sampleRate = sampleRate
    }
}

public enum DragSamples {
    /// `<material id>-resize.wav` holds a material's resize sound.
    public static let resizeSuffix = "-resize"

    /// Loads `<material id>.wav` (drag) and `<material id>-resize.wav` (resize) for every material
    /// found in `directory`, keyed by file name without the extension. Missing files are skipped,
    /// and that material falls back to the synthesized scrape or squeal.
    public static func load(from directory: URL, materials: [Material] = Materials.all) -> [String: DragSample] {
        var out: [String: DragSample] = [:]
        for m in materials {
            for key in [m.id, m.id + resizeSuffix] {
                if let s = try? loadWAV(directory.appendingPathComponent("\(key).wav")) { out[key] = s }
            }
        }
        return out
    }

    /// Minimal WAV reader: PCM 16/24-bit or 32-bit float, any channel count (mixed to mono).
    public static func loadWAV(_ url: URL) throws -> DragSample {
        let data = try Data(contentsOf: url)
        func u16(_ o: Int) -> Int { Int(data[o]) | Int(data[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        guard data.count > 12, String(decoding: data[0..<4], as: UTF8.self) == "RIFF",
              String(decoding: data[8..<12], as: UTF8.self) == "WAVE" else { throw CocoaError(.fileReadCorruptFile) }

        var format = 0, channels = 0, rate = 0, bits = 0
        var body: Range<Int>?
        var o = 12
        while o + 8 <= data.count {
            let id = String(decoding: data[o..<o + 4], as: UTF8.self)
            let size = u32(o + 4)
            let start = o + 8
            if id == "fmt " {
                format = u16(start); channels = u16(start + 2); rate = u32(start + 4); bits = u16(start + 14)
                if format == 0xFFFE { format = u16(start + 24) }   // WAVE_FORMAT_EXTENSIBLE
            } else if id == "data" {
                body = start..<min(start + size, data.count)
            }
            o = start + size + (size & 1)
        }
        guard let body, channels > 0, rate > 0 else { throw CocoaError(.fileReadCorruptFile) }
        let bytes = bits / 8
        let frameBytes = bytes * channels
        let frames = body.count / frameBytes
        var samples = [Float](repeating: 0, count: frames)
        for f in 0..<frames {
            var sum: Float = 0
            for c in 0..<channels {
                let p = body.lowerBound + f * frameBytes + c * bytes
                switch (format, bits) {
                case (1, 16): sum += Float(Int16(bitPattern: UInt16(u16(p)))) / 32768
                case (1, 24): sum += Float(Int32(bitPattern: UInt32(u16(p) << 8 | Int(data[p + 2]) << 24)) >> 8) / 8_388_608
                case (3, 32): sum += Float(bitPattern: UInt32(u32(p)))
                default: throw CocoaError(.fileReadUnsupportedScheme)
                }
            }
            samples[f] = sum / Float(channels)
        }
        return DragSample(samples: samples, sampleRate: Float(rate))
    }
}

/// Plays a drag recording as overlapping grains taken from random places in it, at a rate that
/// follows the window speed: faster hand = faster, brighter, louder; still hand = silence.
/// Random grain positions mean the recording never audibly loops.
struct SampleVoice {
    private let sampleRate: Float
    private var buffer: UnsafePointer<Float>?
    private var count = 0
    private var sourceStep: Float = 1   // source samples per output sample at rate 1

    private static let grains = 2
    private var pos: (Double, Double) = (0, 0)
    private var age: (Int, Int) = (0, 0)
    private var grainLength = 1
    private var nextGrain = 0
    private var slot = 0

    private var amp: Float = 0
    private var ampTarget: Float = 0
    private var rate: Float = 1
    private var rateTarget: Float = 1
    private var lowpass = SVF()
    private var gain: Float = 1
    private var rng = Rng(seed: 0x2468_ACE1)

    init(sampleRate: Float) {
        self.sampleRate = sampleRate
        grainLength = Int(0.16 * sampleRate)
    }

    var hasSample: Bool { buffer != nil }

    mutating func configure(buffer: UnsafePointer<Float>?, count: Int, sourceRate: Float, gain: Float) {
        // Grains read up to 1.5x faster than real time, so the recording must hold a few of them.
        let usable = buffer != nil && count > Int(Float(grainLength) * 2 * 1.5 * sourceRate / sampleRate) + 4
        self.buffer = usable ? buffer : nil
        self.count = usable ? count : 0
        self.gain = gain
        sourceStep = sourceRate / sampleRate
        age = (grainLength, grainLength)
        nextGrain = 0
    }

    /// `s` is normalised speed 0...1, `jerk` 0...1 a sudden speed-up.
    mutating func control(s: Float, jerk: Float) {
        ampTarget = s < 1e-4 ? 0 : gain * powf(s, 0.85) * (1 + 0.5 * jerk)
        // A real object barely changes pitch with speed; it gets louder and grittier. So speed
        // nudges the playback rate by about a semitone either way: crawl 0.94x, fling 1.06x.
        rateTarget = 0.94 + 0.12 * s
        let cutoff = 1500 + 18000 * powf(s, 0.6)
        lowpass.set(cutoff: min(cutoff, sampleRate * 0.45), q: 0.6, sampleRate: sampleRate)
    }

    @inline(__always) private func read(_ p: Double) -> Float {
        guard let buffer else { return 0 }
        let i = Int(p)
        let f = Float(p - Double(i))
        return buffer[i] + (buffer[i + 1] - buffer[i]) * f
    }

    @inline(__always) mutating func tick() -> Float {
        guard buffer != nil else { return 0 }
        amp += (ampTarget - amp) * 0.004
        rate += (rateTarget - rate) * 0.0002   // ~100 ms glide, so hand jitter never wobbles the pitch
        if ampTarget == 0 && amp < 1e-5 { return 0 }

        let step = Double(rate * sourceStep)
        nextGrain -= 1
        if nextGrain <= 0 {
            // Start a grain in the slot whose grain has finished (they alternate every half grain).
            let span = Double(grainLength) * 1.5 * Double(sourceStep) + 2
            let start = Double(rng.uniform()) * (Double(count) - span)
            if slot == 0 { pos.0 = start; age.0 = 0 } else { pos.1 = start; age.1 = 0 }
            slot ^= 1
            nextGrain = grainLength / 2
        }

        var y: Float = 0
        let inv = Float.pi / Float(grainLength)
        if age.0 < grainLength {
            y += read(pos.0) * sinf(Float(age.0) * inv)
            pos.0 += step; age.0 += 1
        }
        if age.1 < grainLength {
            y += read(pos.1) * sinf(Float(age.1) * inv)
            pos.1 += step; age.1 += 1
        }
        return lowpass.tick(y).low * amp
    }
}
