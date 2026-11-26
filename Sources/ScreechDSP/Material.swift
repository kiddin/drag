import Foundation

/// One resonant mode of a material's body.
public struct Mode: Sendable {
    public var freq: Float   // Hz
    public var t60: Float    // seconds to decay by 60 dB
    public var gain: Float

    public init(_ freq: Float, _ t60: Float, _ gain: Float) {
        self.freq = freq
        self.t60 = t60
        self.gain = gain
    }
}

/// Describes a resonant body physically; the modes are generated from it.
///
/// Mode frequencies follow a rectangular plate, `f(m,n) ∝ m² + (aspect·n)²`, which gives the
/// dense, inharmonic spectrum of real panels. Higher modes decay faster (`dampingFreq`,
/// `dampingExp`), as in real materials. Two pickups give slightly different mode gains,
/// which makes the body sound wide instead of mono.
public struct BodySpec: Sendable {
    public var fundamental: Float = 200
    public var aspect: Float = 1.2
    public var count: Int = 32
    /// Random detune fraction: 0 = ideal plate, 0.1 = irregular (stone, wood grain).
    public var jitter: Float = 0.02
    /// Decay of the lowest modes, seconds.
    public var t60: Float = 0.3
    public var dampingFreq: Float = 2000
    public var dampingExp: Float = 1
    /// Gain falls as (f0/f)^tilt.
    public var tilt: Float = 0.5
    public var seed: UInt32 = 1

    public init() {}

    public func modes(pickup: Int) -> [Mode] {
        var ratios: [Float] = []
        let a2 = aspect * aspect
        for m in 1...14 {
            for n in 1...14 {
                ratios.append((Float(m * m) + a2 * Float(n * n)) / (1 + a2))
            }
        }
        ratios.sort()
        var unique: [Float] = []
        for r in ratios where unique.last.map({ r / $0 > 1.006 }) ?? true {
            unique.append(r)
        }

        var shape = Rng(seed: seed)                      // shared by both pickups
        var pick = Rng(seed: seed &* 2_654_435_761 &+ UInt32(pickup + 1) &* 40503)
        var modes: [Mode] = []
        for r in unique.prefix(count) {
            var f = fundamental * r * (1 + jitter * shape.bipolar())
            f *= 1 + 0.0015 * pick.bipolar()
            let t = t60 / (1 + powf(f / dampingFreq, dampingExp))
            let g = powf(fundamental / f, tilt) * (0.3 + 0.7 * pick.uniform())
            modes.append(Mode(f, max(t, 0.004), g))
        }
        let norm = 1 / max(modes.reduce(0) { $0 + $1.gain * $1.gain }.squareRoot(), 1e-6)
        return modes.map { Mode($0.freq, $0.t60, $0.gain * norm) }
    }
}

/// A sound theme. Plain data: adding a theme means adding one preset in `Materials`.
public struct Material: Sendable, Identifiable {
    public let id: String
    public let name: String
    /// SF Symbol shown in the menu.
    public let symbol: String
    public let blurb: String

    // Body
    public var body: BodySpec
    /// 0 = dry contact only, 1 = everything through the resonant body.
    public var bodyMix: Float = 0.6
    /// Overall loudness trim.
    public var level: Float = 1
    /// How much of this material goes to the room reverb.
    public var reverbSend: Float = 0.8

    // Drag: sliding friction = surface hiss + a stream of micro-impacts
    /// Micro-impacts per pixel travelled (asperities hitting each other).
    public var impactsPerPixel: Float = 0.5
    /// Pareto exponent of impact sizes: lower = more occasional big bumps.
    public var impactTail: Float = 2.5
    /// Contact stiffness as a lowpass on each micro-impact, Hz.
    public var contactHardness: Float = 4000
    public var contactGain: Float = 1
    /// Level of the continuous surface hiss next to the impacts.
    public var hiss: Float = 0.5
    /// Surface texture samples per pixel travelled. Higher = finer, brighter hiss.
    public var textureDensity: Float = 6
    /// 0 = smooth (energy in the low octaves), 1 = rough (white).
    public var textureRoughness: Float = 0.5
    public var slideLowpassMin: Float = 800    // Hz while crawling
    public var slideLowpassMax: Float = 5000   // Hz at full speed
    public var slideResonance: Float = 0.8
    public var slideHighpass: Float = 80
    /// Hiss loudness grows as speed^curve.
    public var slideCurve: Float = 1.1
    public var slideGain: Float = 0.2
    /// 0...1 stick-slip stutter, strongest at low speed.
    public var chatter: Float = 0.4
    public var chatterRate: Float = 30

    /// Loudness of the recorded drag sound, when the material has one.
    public var sampleGain: Float = 1.6
    /// Loudness of the recorded resize sound, when the material has one.
    public var resizeSampleGain: Float = 1.6

    // Resize: a bowed friction oscillator (stick-slip), plus some of the drag rub
    public var squealMin: Float = 100          // Hz while crawling
    public var squealMax: Float = 400          // Hz at full speed
    public var squealCurve: Float = 0.8
    /// 0...1 normal force. High = raw creak, low = clean squeal.
    public var bowPressure: Float = 0.5
    /// Contact point along the vibrating part, 0...0.5.
    public var bowPosition: Float = 0.127
    /// Slow wobble of pressure and pitch.
    public var squealJitter: Float = 0.2
    /// Grit in the contact (rosin noise).
    public var squealNoise: Float = 0.1
    /// Radiation band-pass on the squeal.
    public var formant: Float = 1000
    /// 0 = fixed formant, 1 = formant follows the 2nd harmonic of the squeal.
    public var formantTrack: Float = 0
    public var formantQ: Float = 1.5
    /// Octaves of pitch bend between shrinking and growing.
    public var growBend: Float = 0.3
    public var stretchGain: Float = 1
    /// How much drag-style rubbing accompanies a resize.
    public var stretchRub: Float = 0.2

    // Impacts: grab, release, direction reversal
    public var impactGain: Float = 0.8
    /// Contact duration of a knock, seconds. Soft materials touch longer and sound duller.
    public var contactTime: Float = 0.0015
    public var impactNoise: Float = 0.3
    public var impactBrightness: Float = 3000

    public init(id: String, name: String, symbol: String, blurb: String, body: BodySpec) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.blurb = blurb
        self.body = body
    }
}
