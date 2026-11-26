import Foundation

/// Bowed friction oscillator for window resizes: rubber screech, wood creak, metal squeal.
///
/// A waveguide (two delay lines with lossy reflections) is driven by a stick-slip friction
/// curve, the classic bowed-string model. The surface sticks and slips on its own, so the
/// waveform's irregularities, onsets and the raw "creak" at high pressure come from the
/// physics instead of being scripted. Resize speed sets the rubbing velocity and the
/// tension (pitch); growing bends the pitch up, shrinking down.
struct StretchVoice {
    private let sampleRate: Float
    private let neck: DelayLine
    private let bridge: DelayLine
    private var stringFilter: Float = 0
    private var loss: Float = 0.95
    private var pole: Float = 0.6
    private var slope: Float = 3
    private var beta: Float = 0.127

    private var freq: Float = 100
    private var freqTarget: Float = 100
    private var bowVelocity: Float = 0
    private var bowTarget: Float = 0
    private var wobble: Float = 0
    private var wobbleTarget: Float = 0
    private var wobbleCountdown = 0
    private var formantFilter = SVF()
    private var dcBlock = SVF()
    private var amp: Float = 0
    private var ampTarget: Float = 0
    private var s: Float = 0
    private var grow: Float = 0
    private var rng = Rng(seed: 0x0BAD_C0DE)

    // Material parameters
    private var minHz: Float = 100
    private var maxHz: Float = 400
    private var curve: Float = 0.8
    private var jitter: Float = 0.2
    private var noise: Float = 0.1
    private var formant: Float = 1000
    private var formantTrack: Float = 0
    private var formantQ: Float = 1.5
    private var bend: Float = 0.3
    private var gain: Float = 1

    static let lowestHz: Float = 10

    init(sampleRate: Float) {
        self.sampleRate = sampleRate
        let maxDelay = Int(sampleRate / Self.lowestHz) + 8
        neck = DelayLine(capacity: maxDelay)
        bridge = DelayLine(capacity: maxDelay)
        pole = 0.75 - 0.2 * 22050 / sampleRate
        dcBlock.set(cutoff: 30, q: 0.707, sampleRate: sampleRate)
    }

    mutating func configure(_ m: Material) {
        minHz = max(m.squealMin, Self.lowestHz)
        maxHz = m.squealMax
        curve = m.squealCurve
        jitter = m.squealJitter
        noise = m.squealNoise
        formant = m.formant
        formantTrack = m.formantTrack
        formantQ = m.formantQ
        bend = m.growBend
        gain = m.stretchGain
        slope = 5 - 4 * clamp(m.bowPressure, 0, 1)
        beta = clamp(m.bowPosition, 0.02, 0.5)
        control(s: s, grow: grow)
        freq = freqTarget
    }

    /// Called every control block. `s` is normalised resize speed 0...1, `grow` is -1...1.
    mutating func control(s: Float, grow: Float) {
        self.s = s
        self.grow = grow
        let base = minHz + (maxHz - minHz) * powf(s, curve)
        freqTarget = base * exp2f(grow * bend * min(s * 3, 1))
        let centre = formant * (1 - formantTrack) + freqTarget * 2 * formantTrack
        formantFilter.set(cutoff: centre, q: formantQ, sampleRate: sampleRate)
        let on = s >= 0.002
        bowTarget = on ? 0.03 + 0.2 * s : 0
        ampTarget = on ? gain * min(s / 0.03, 1) * (0.4 + 0.6 * s) : 0
    }

    /// Friction curve: sticks (≈1) for small relative velocity, slips beyond.
    @inline(__always) private func bowTable(_ dv: Float) -> Float {
        let x = abs(dv * slope) + 0.75
        let x2 = x * x
        return clamp(1 / (x2 * x2), 0.01, 0.98)
    }

    @inline(__always) mutating func tick() -> Excitation {
        amp += (ampTarget - amp) * 0.01
        bowVelocity += (bowTarget - bowVelocity) * 0.003
        if ampTarget == 0 && amp < 1e-6 { return .zero }

        freq += (freqTarget - freq) * 0.002
        wobbleCountdown -= 1
        if wobbleCountdown <= 0 {
            wobbleTarget = rng.bipolar() * jitter
            wobbleCountdown = Int(sampleRate * (0.02 + 0.05 * rng.uniform()))
        }
        wobble += (wobbleTarget - wobble) * 0.0015

        // Waveguide lengths for the current pitch (with a slow tension wobble).
        let f = clamp(freq * (1 + wobble * 0.06), Self.lowestHz, sampleRate * 0.2)
        let total = max(sampleRate / f - 4, 4)
        // Strings lose energy fast once nothing rubs them.
        let damping: Float = bowTarget > 0 ? 0.95 : 0.7

        let bow = bowVelocity * (1 + wobble * 0.5) + noise * 0.02 * rng.bipolar() * min(bowVelocity * 10, 1)
        stringFilter = (1 - pole) * damping * bridge.lastOut + pole * stringFilter
        let bridgeReflection = -stringFilter
        let nutReflection = -neck.lastOut
        let stringVelocity = bridgeReflection + nutReflection
        let dv = bow - stringVelocity
        let newVelocity = dv * bowTable(dv)
        // Keep both waveguide sections a few samples long, even at high pitch.
        let bridgeDelay = min(max(total * beta, 2.5), total * 0.5)
        _ = neck.tick(bridgeReflection + newVelocity, delay: total - bridgeDelay)
        let out = bridge.tick(nutReflection + newVelocity, delay: bridgeDelay)

        let v = dcBlock.tick(out).high
        let radiated = formantFilter.tick(v).band * formantFilter.k
        let y = (radiated * 0.6 + v * 0.4) * amp * 4
        // A tonal squeal sitting on a long-ringing mode builds up hugely, so feed the body gently.
        return Excitation(direct: y, cont: y * 0.3, imp: 0)
    }
}

/// A knock: a smooth contact pulse into the body plus a little surface noise.
/// Soft materials touch longer, which filters out the high modes, like a real thud.
struct Impact {
    private let sampleRate: Float
    private var pulseAmp: Float = 0
    private var pulseLength: Float = 1
    private var pulsePos: Float = 1
    private var noiseEnv: Float = 0
    private var noiseDecay: Float = 0.99
    private var lowpass = SVF()
    private var gain: Float = 1
    private var noiseAmount: Float = 0.3
    private var contactTime: Float = 0.0015
    private var rng = Rng(seed: 0x00C0_FFEE)

    init(sampleRate: Float) {
        self.sampleRate = sampleRate
    }

    mutating func configure(_ m: Material) {
        lowpass.set(cutoff: m.impactBrightness, q: 0.7, sampleRate: sampleRate)
        gain = m.impactGain
        noiseAmount = m.impactNoise
        contactTime = m.contactTime
        noiseDecay = expf(-1 / max(0.003 * sampleRate, 1))
    }

    mutating func trigger(_ strength: Float) {
        let a = clamp(strength, 0, 1)
        guard a > 0 else { return }
        // Harder hits are shorter.
        pulseLength = max(contactTime * sampleRate * (1.3 - 0.5 * a), 2)
        pulsePos = 0
        pulseAmp = max(pulseAmp * 0.5, a)
        noiseEnv = max(noiseEnv, a * noiseAmount)
    }

    @inline(__always) mutating func tick() -> Excitation {
        var p: Float = 0
        if pulsePos < pulseLength {
            p = pulseAmp * sinf(Float.pi * pulsePos / pulseLength)
            pulsePos += 1
        }
        if p == 0 && noiseEnv < 1e-5 { return .zero }
        let n = lowpass.tick(rng.bipolar() * noiseEnv).low
        noiseEnv *= noiseDecay
        // Pulse area normalised so the body rings with amplitude ≈ strength.
        let force = p * Float.pi / (2 * pulseLength)
        return Excitation(direct: (n + p * 0.15) * gain, cont: 0, imp: force * gain * 2)
    }
}
