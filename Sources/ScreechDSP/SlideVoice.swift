import Foundation

/// Sliding friction for window drags.
///
/// Real scraping is two things at once:
/// - a stream of micro-impacts as surface bumps catch on each other. Their rate follows
///   the speed, their sizes are heavy-tailed (mostly tiny, now and then a big catch), and
///   each one is a short contact pulse that rings the material's body;
/// - a continuous hiss from the surface texture, read like a stylus at the window's speed.
/// Hand pressure wobbles, jerks catch more bumps, and at low speed stick-slip chops the
/// sound into stutters.
struct SlideVoice {
    private let sampleRate: Float
    private var texture: UnsafeMutablePointer<Float>
    private var pos: Double = 0
    private var prevHeight: Float = 0

    private var hissLowpass = SVF()
    private var hissHighpass = SVF()
    private var contactLowpass = SVF()
    private var contactHighpass = SVF()
    private var contactNorm: Float = 1
    private var amp: Float = 0
    private var ampTarget: Float = 0
    private var bumpAmp: Float = 0
    private var bumpAmpTarget: Float = 0
    private var chatAmp: Float = 0
    private var chatterIntensity: Float = 0
    private var chatterCountdown: Float = 0
    private var chatterEnv: Float = 0
    private var chatterDecay: Float = 0.99
    private var pressure: Float = 1
    private var pressureTarget: Float = 1
    private var pressureCountdown = 0
    private var s: Float = 0
    private var jerk: Float = 0
    private var rng = Rng(seed: 0x1357_9BDF)

    // Material parameters
    private var density: Float = 6
    private var lpMin: Float = 800
    private var lpMax: Float = 5000
    private var lpQ: Float = 0.8
    private var curve: Float = 1
    private var gain: Float = 1
    private var hiss: Float = 0.5
    private var impactsPerPixel: Float = 0.5
    private var invTail: Float = 0.4
    private var hardness: Float = 4000
    private var contactGain: Float = 1
    private var chatter: Float = 0
    private var chatterRate: Float = 30

    init(sampleRate: Float, texture: UnsafeMutablePointer<Float>) {
        self.sampleRate = sampleRate
        self.texture = texture
        chatterDecay = expf(-1 / (0.008 * sampleRate))
    }

    mutating func configure(_ m: Material, texture: UnsafeMutablePointer<Float>) {
        self.texture = texture
        density = m.textureDensity
        lpMin = m.slideLowpassMin
        lpMax = m.slideLowpassMax
        lpQ = m.slideResonance
        curve = m.slideCurve
        gain = m.slideGain
        hiss = m.hiss
        impactsPerPixel = m.impactsPerPixel
        invTail = 1 / max(m.impactTail, 1.1)
        hardness = m.contactHardness
        contactGain = m.contactGain
        chatter = m.chatter
        chatterRate = m.chatterRate
        hissHighpass.set(cutoff: m.slideHighpass, q: 0.707, sampleRate: sampleRate)
        contactHighpass.set(cutoff: max(m.slideHighpass, 40), q: 0.707, sampleRate: sampleRate)
        control(s: s, jerk: jerk)
    }

    /// Called every control block. `s` is normalised speed 0...1.
    mutating func control(s: Float, jerk: Float) {
        self.s = s
        self.jerk = jerk
        hissLowpass.set(cutoff: lpMin + (lpMax - lpMin) * powf(s, 0.8), q: lpQ, sampleRate: sampleRate)
        // Faster contact = harder, shorter pulses = brighter.
        let fc = hardness * (0.6 + 0.4 * s)
        contactLowpass.set(cutoff: fc, q: 0.6, sampleRate: sampleRate)
        contactNorm = 1 / max(tanf(Float.pi * min(fc, sampleRate * 0.45) / sampleRate), 1e-3)
        ampTarget = s < 1e-4 ? 0 : gain * powf(s, curve)
        bumpAmpTarget = s < 1e-4 ? 0 : gain * contactGain * (0.25 + 0.75 * s)
        chatAmp = gain * sqrtf(s)
        chatterIntensity = chatter * expf(-s * 5) * min(s / 0.02, 1)
    }

    /// One bump size: Pareto distributed, mostly small with occasional big catches.
    @inline(__always) private mutating func bumpSize() -> Float {
        let u = max(rng.uniform(), 1e-3)
        return min(powf(u, -invTail), 10) * 0.3
    }

    @inline(__always) mutating func tick(pxPerSample: Float) -> Excitation {
        amp += (ampTarget - amp) * 0.02
        bumpAmp += (bumpAmpTarget - bumpAmp) * 0.02
        if ampTarget == 0 && amp < 1e-6 && bumpAmp < 1e-6 && chatterEnv < 1e-5 { return .zero }

        // Hand pressure drifts a little all the time.
        pressureCountdown -= 1
        if pressureCountdown <= 0 {
            pressureTarget = 1 + 0.3 * rng.bipolar()
            pressureCountdown = Int(sampleRate * (0.04 + 0.12 * rng.uniform()))
        }
        pressure += (pressureTarget - pressure) * 0.0008

        // Continuous hiss: stylus over the surface texture.
        let step = pxPerSample * density
        pos += Double(step)
        if pos >= Double(SurfaceTexture.size) { pos -= Double(SurfaceTexture.size) }
        let i = Int(pos)
        let frac = Float(pos - Double(i))
        let a = texture[i]
        let b = texture[(i + 1) & SurfaceTexture.mask]
        let height = a + (b - a) * frac
        let slope = clamp((height - prevHeight) / min(max(step, 0.002), 1), -4, 4)
        prevHeight = height

        // Micro-impacts: expected count this sample follows distance travelled.
        let expected = impactsPerPixel * pxPerSample * (1 + 3 * jerk) * pressure
        var kick: Float = 0
        if expected >= 1 {
            kick = bumpSize() * expected.squareRoot()
        } else if rng.uniform() < expected {
            kick = bumpSize()
        }

        // Stick-slip chatter at low speed
        var slip: Float = 0
        if chatterIntensity > 0.002 {
            chatterCountdown -= 1
            if chatterCountdown <= 0 {
                let rate = chatterRate * (0.5 + 2 * s)
                chatterCountdown = sampleRate / rate * (0.5 + rng.uniform())
                chatterEnv = 1
                slip = chatterIntensity * (0.4 + 0.6 * rng.uniform())
            }
        }
        chatterEnv *= chatterDecay
        let stutter = 1 - chatterIntensity + chatterIntensity * (0.15 + 1.6 * chatterEnv)

        let hissY = hissHighpass.tick(hissLowpass.tick(slope).low).high * amp * stutter * pressure * hiss
        let pulse = contactLowpass.tick(kick * contactNorm).low
        let contactY = contactHighpass.tick(pulse).high * bumpAmp

        return Excitation(direct: hissY + contactY * 0.5, cont: hissY * 0.5 + contactY, imp: slip * chatAmp)
    }
}
