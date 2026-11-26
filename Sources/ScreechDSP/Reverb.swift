import Foundation

/// Circular delay with linearly interpolated fractional reads.
final class DelayLine {
    private let buffer: UnsafeMutablePointer<Float>
    private let mask: Int
    private var write = 0
    private(set) var lastOut: Float = 0

    init(capacity: Int) {
        var size = 1
        while size < capacity + 2 { size <<= 1 }
        mask = size - 1
        buffer = .allocate(capacity: size)
        buffer.initialize(repeating: 0, count: size)
    }

    deinit { buffer.deallocate() }

    /// Writes `x` and returns the input from `delay` samples ago (delay >= 1).
    @inline(__always) func tick(_ x: Float, delay: Float) -> Float {
        buffer[write] = x
        let pos = Float(write) - delay
        let base = Int(floorf(pos))
        let frac = pos - Float(base)
        let a = buffer[base & mask]
        let b = buffer[(base + 1) & mask]
        write = (write + 1) & mask
        lastOut = a + (b - a) * frac
        return lastOut
    }

    /// Integer-delay read of what was written `delay` samples ago, without writing.
    @inline(__always) func read(_ delay: Int) -> Float {
        buffer[(write - delay) & mask]
    }

    @inline(__always) func push(_ x: Float) {
        buffer[write] = x
        write = (write + 1) & mask
    }
}

/// Schroeder allpass used to diffuse the reverb input.
private final class Allpass {
    private let line: DelayLine
    private let length: Int
    private let gain: Float

    init(length: Int, gain: Float) {
        self.length = length
        self.gain = gain
        line = DelayLine(capacity: length + 1)
    }

    @inline(__always) func tick(_ x: Float) -> Float {
        let delayed = line.read(length)
        let v = x + gain * delayed
        line.push(v)
        return delayed - gain * v
    }
}

/// A small room: pre-delay, input diffusion, then an 8-line feedback delay network with a
/// Householder mixing matrix and frequency-dependent decay. Mono in, decorrelated stereo out.
final class Reverb {
    private static let baseLengths: [Float] = [1427, 1601, 1777, 1949, 2111, 2297, 2459, 2647] // at 48 kHz
    private let lines: [DelayLine]
    private let lengths: [Int]
    private let gains: UnsafeMutablePointer<Float>
    private let damp: UnsafeMutablePointer<Float>
    private let taps: UnsafeMutablePointer<Float>
    private let predelay: DelayLine
    private let predelayLength: Int
    private let diffusers: [Allpass]
    private let dampCoef: Float

    /// `size` scales the room (1 ≈ 30–55 ms between walls), `t60` is the decay in seconds.
    init(sampleRate: Float, size: Float = 0.8, t60: Float = 1.0, damping: Float = 4500) {
        let scale = sampleRate / 48000 * size
        lengths = Self.baseLengths.map { Int($0 * scale) }
        lines = lengths.map { DelayLine(capacity: $0 + 1) }
        gains = .allocate(capacity: 8)
        damp = .allocate(capacity: 8)
        taps = .allocate(capacity: 8)
        for i in 0..<8 {
            gains[i] = powf(10, -3 * Float(lengths[i]) / (t60 * sampleRate))
            damp[i] = 0
            taps[i] = 0
        }
        predelayLength = Int(0.012 * sampleRate)
        predelay = DelayLine(capacity: predelayLength + 1)
        let s = sampleRate / 48000
        diffusers = [142, 107, 379, 277].map { Allpass(length: Int(Float($0) * s), gain: 0.65) }
        dampCoef = 1 - expf(-2 * Float.pi * damping / sampleRate)
    }

    deinit {
        gains.deallocate()
        damp.deallocate()
        taps.deallocate()
    }

    @inline(__always) func tick(_ x: Float) -> (left: Float, right: Float) {
        let pre = predelay.read(predelayLength)
        predelay.push(x)
        var d = pre
        for ap in diffusers { d = ap.tick(d) }

        var sum: Float = 0
        for i in 0..<8 {
            var o = lines[i].read(lengths[i])
            damp[i] += (o - damp[i]) * dampCoef
            o = damp[i]
            taps[i] = o
            sum += o
        }
        let householder = sum * 0.25  // 2/N
        for i in 0..<8 {
            let input = (i & 1 == 0 ? d : -d)
            lines[i].push((taps[i] - householder) * gains[i] + input)
        }
        let left = taps[0] - taps[2] + taps[4] - taps[6]
        let right = taps[1] - taps[3] + taps[5] - taps[7]
        return (left * 0.3, right * 0.3)
    }
}
