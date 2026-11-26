import Foundation

/// Tiny, allocation-free xorshift generator for the audio thread.
struct Rng {
    private var state: UInt32

    init(seed: UInt32) { state = seed == 0 ? 0x9E37_79B9 : seed }

    @inline(__always) mutating func next() -> UInt32 {
        var x = state
        x ^= x << 13
        x ^= x >> 17
        x ^= x << 5
        state = x
        return x
    }

    /// Uniform in 0..<1.
    @inline(__always) mutating func uniform() -> Float { Float(next() >> 8) * (1.0 / 16_777_216.0) }

    /// Uniform in -1..<1.
    @inline(__always) mutating func bipolar() -> Float { uniform() * 2 - 1 }
}

@inline(__always) func clamp(_ x: Float, _ lo: Float, _ hi: Float) -> Float { min(max(x, lo), hi) }

/// Per-sample coefficient for a one-pole smoother with the given time constant.
@inline(__always) func smoothingCoef(seconds: Float, sampleRate: Float) -> Float {
    1 - expf(-1 / max(seconds * sampleRate, 1))
}

/// Monotonic tanh-like soft clipper, output bounded to ±1.
@inline(__always) func softClip(_ x: Float) -> Float {
    let c = clamp(x, -3, 3)
    let c2 = c * c
    return c * (27 + c2) / (27 + 9 * c2)
}

/// Band-limited step correction for the sawtooth.
@inline(__always) func polyBlep(_ t: Float, _ dt: Float) -> Float {
    if t < dt {
        let x = t / dt
        return x + x - x * x - 1
    } else if t > 1 - dt {
        let x = (t - 1) / dt
        return x * x + x + x + 1
    }
    return 0
}

/// Topology-preserving state variable filter (Simper). Stable under fast cutoff modulation.
struct SVF {
    private var ic1: Float = 0
    private var ic2: Float = 0
    private var a1: Float = 1
    private var a2: Float = 0
    private var a3: Float = 0
    private(set) var k: Float = 1

    mutating func set(cutoff: Float, q: Float, sampleRate: Float) {
        let fc = clamp(cutoff, 10, sampleRate * 0.45)
        let g = tanf(Float.pi * fc / sampleRate)
        k = 1 / max(q, 0.05)
        a1 = 1 / (1 + g * (g + k))
        a2 = g * a1
        a3 = g * a2
    }

    @inline(__always) mutating func tick(_ v0: Float) -> (low: Float, band: Float, high: Float) {
        let v3 = v0 - ic2
        let v1 = a1 * ic1 + a2 * v3
        let v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        return (v2, v1, v0 - k * v1 - v2)
    }
}

/// What a voice feeds into the mix: a dry signal, a continuous excitation for the
/// material's resonant body, and an impulsive excitation (taps, slips, clicks).
struct Excitation {
    var direct: Float
    var cont: Float
    var imp: Float
    static let zero = Excitation(direct: 0, cont: 0, imp: 0)
}
