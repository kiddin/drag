import Foundation

/// Bank of two-pole resonators: the "body" that gives each material its pitch and ring.
///
/// Two inputs per mode, normalised differently:
/// - `imp`: a unit impulse makes the mode ring with amplitude `gain` (taps, slips, clicks).
/// - `cont`: white noise of RMS σ gives an output of RMS ≈ σ·gain whatever the decay (scraping).
final class ModalBank {
    static let maxModes = 48

    private var count = 0
    private let a1 = UnsafeMutablePointer<Float>.allocate(capacity: maxModes)
    private let a2 = UnsafeMutablePointer<Float>.allocate(capacity: maxModes)
    private let bImp = UnsafeMutablePointer<Float>.allocate(capacity: maxModes)
    private let bCont = UnsafeMutablePointer<Float>.allocate(capacity: maxModes)
    private let y1 = UnsafeMutablePointer<Float>.allocate(capacity: maxModes)
    private let y2 = UnsafeMutablePointer<Float>.allocate(capacity: maxModes)

    init() {
        for p in [a1, a2, bImp, bCont, y1, y2] { p.initialize(repeating: 0, count: Self.maxModes) }
    }

    deinit {
        for p in [a1, a2, bImp, bCont, y1, y2] { p.deallocate() }
    }

    /// `scale` shifts every mode (bigger windows sound lower and heavier).
    /// `decay` multiplies every mode's ring time (1 = the material as designed).
    func configure(modes: [Mode], scale: Float, decay: Float = 1, sampleRate: Float) {
        count = min(modes.count, Self.maxModes)
        for i in 0..<count {
            let mode = modes[i]
            let f = mode.freq * scale
            guard f < sampleRate * 0.45 else {
                a1[i] = 0; a2[i] = 0; bImp[i] = 0; bCont[i] = 0
                continue
            }
            let w = 2 * Float.pi * f / sampleRate
            let r = powf(0.001, 1 / max(mode.t60 * decay * sampleRate, 1))
            a1[i] = 2 * r * cosf(w)
            a2[i] = -r * r
            let s = sinf(w)
            bImp[i] = s * mode.gain
            bCont[i] = s * mode.gain * sqrtf(2 * (1 - r * r))
        }
    }

    @inline(__always) func tick(cont: Float, imp: Float) -> Float {
        var sum: Float = 0
        for i in 0..<count {
            let y = bImp[i] * imp + bCont[i] * cont + a1[i] * y1[i] + a2[i] * y2[i]
            y2[i] = y1[i]
            y1[i] = y
            sum += y
        }
        return sum
    }
}
