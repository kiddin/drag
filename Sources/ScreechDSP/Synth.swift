import Foundation

/// Real-time kernel. `render` runs on the audio thread: no locks, no allocation.
public final class Synth {
    public let control: ControlBlock
    public let sampleRate: Float
    public let materials: [Material]

    private let textures: [UnsafeMutablePointer<Float>]
    private let modesLeft: [[Mode]]
    private let modesRight: [[Mode]]
    private var materialIndex = -1
    private var baseBodyMix: Float = 0.5
    private var bodyMix: Float = 0.5
    private var ring: Float = 1
    private var level: Float = 1
    private var reverbSend: Float = 0.8
    private var rub: Float = 0.2

    private var slide: SlideVoice
    private var sampleVoice: SampleVoice
    private var resizeVoice: SampleVoice
    /// Recorded drag sound per material (nil = synthesized scrape).
    private let sampleBuffers: [(pointer: UnsafeMutablePointer<Float>, count: Int, rate: Float)?]
    /// Recorded resize sound per material (nil = synthesized squeal).
    private let resizeBuffers: [(pointer: UnsafeMutablePointer<Float>, count: Int, rate: Float)?]
    private var stretch: StretchVoice
    private var impact: Impact
    private var thud: Thud
    private let bankL = ModalBank()
    private let bankR = ModalBank()
    private let reverb: Reverb

    // Targets read from the control block once per buffer
    private var targetSpeed: Float = 0
    private var dragTarget: Float = 0
    private var resizeTarget: Float = 0
    private var panTarget: Float = 0
    private var volumeTarget: Float = 0.7
    private var reverbTarget: Float = 0.35
    private var grow: Float = 0
    private var sizeScale: Float = 1
    private var lastMode: MotionMode = .idle

    // Smoothed per sample
    private var speed: Float = 0
    private var dragGate: Float = 0
    private var resizeGate: Float = 0
    private var pan: Float = 0
    private var volume: Float = 0.7
    private var reverbAmount: Float = 0.35
    private var gainL: Float = 1
    private var gainR: Float = 1
    private var jerk: Float = 0
    private var lastNorm: Float = 0
    private var envelope: Float = 0
    private var compGain: Float = 1
    private let compAttack: Float
    private let compRelease: Float
    static let compThreshold: Float = 0.35
    static let compRatio: Float = 4

    private var seenGrab: Int
    private var seenRelease: Int
    private var seenBump: Int

    private var blockCounter = 0
    private var quietSamples = 0
    private var idle = true

    private let attack: Float
    private let release: Float
    private let gateCoef: Float
    private let slowCoef: Float

    static let blockSize = 32
    /// Speed (pt/s) that maps to ~63% of full intensity.
    static let speedScale: Float = 900

    public init(sampleRate: Float, control: ControlBlock = ControlBlock(), materials: [Material] = Materials.all,
                samples: [String: DragSample] = [:]) {
        precondition(!materials.isEmpty)
        self.sampleRate = sampleRate
        self.control = control
        self.materials = materials
        var seed: UInt32 = 0xA5A5_1234
        textures = materials.map { m in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return SurfaceTexture.make(roughness: m.textureRoughness, seed: seed)
        }
        modesLeft = materials.map { $0.body.modes(pickup: 0) }
        modesRight = materials.map { $0.body.modes(pickup: 1) }
        slide = SlideVoice(sampleRate: sampleRate, texture: textures[0])
        sampleVoice = SampleVoice(sampleRate: sampleRate)
        resizeVoice = SampleVoice(sampleRate: sampleRate)
        func buffer(_ key: String) -> (pointer: UnsafeMutablePointer<Float>, count: Int, rate: Float)? {
            guard let s = samples[key], !s.samples.isEmpty else { return nil }
            let p = UnsafeMutablePointer<Float>.allocate(capacity: s.samples.count + 1)
            p.initialize(from: s.samples, count: s.samples.count)
            p[s.samples.count] = 0
            return (p, s.samples.count, s.sampleRate)
        }
        sampleBuffers = materials.map { buffer($0.id) }
        resizeBuffers = materials.map { buffer($0.id + DragSamples.resizeSuffix) }
        stretch = StretchVoice(sampleRate: sampleRate)
        impact = Impact(sampleRate: sampleRate)
        thud = Thud(sampleRate: sampleRate)
        reverb = Reverb(sampleRate: sampleRate)
        attack = smoothingCoef(seconds: 0.012, sampleRate: sampleRate)
        release = smoothingCoef(seconds: 0.035, sampleRate: sampleRate)
        gateCoef = smoothingCoef(seconds: 0.008, sampleRate: sampleRate)
        slowCoef = smoothingCoef(seconds: 0.05, sampleRate: sampleRate)
        compAttack = smoothingCoef(seconds: 0.002, sampleRate: sampleRate)
        compRelease = smoothingCoef(seconds: 0.15, sampleRate: sampleRate)
        seenGrab = control.grabCount
        seenRelease = control.releaseCount
        seenBump = control.bumpCount
        volume = control.volume
        reverbAmount = control.reverb
        ring = clamp(control.ring, 0, 1)
        selectMaterial(control.material)
    }

    deinit {
        for t in textures { t.deallocate() }
        for b in sampleBuffers + resizeBuffers { b?.pointer.deallocate() }
    }

    /// True once every voice and the reverb tail have died away and nothing is asked for.
    public var isIdle: Bool { idle }

    private var currentIndex: Int { min(max(materialIndex, 0), materials.count - 1) }

    private func selectMaterial(_ index: Int) {
        materialIndex = index
        let i = currentIndex
        let m = materials[i]
        baseBodyMix = m.bodyMix
        bodyMix = bodyMixTarget
        level = m.level
        reverbSend = m.reverbSend
        rub = m.stretchRub
        slide.configure(m, texture: textures[i])
        let b = sampleBuffers[i]
        sampleVoice.configure(buffer: b.map { UnsafePointer($0.pointer) }, count: b?.count ?? 0,
                              sourceRate: b?.rate ?? sampleRate, gain: m.sampleGain)
        let rb = resizeBuffers[i]
        resizeVoice.configure(buffer: rb.map { UnsafePointer($0.pointer) }, count: rb?.count ?? 0,
                              sourceRate: rb?.rate ?? sampleRate, gain: m.resizeSampleGain)
        stretch.configure(m)
        impact.configure(m)
        configureBanks()
    }

    private func configureBanks() {
        let decay = 0.3 + 0.7 * ring
        bankL.configure(modes: modesLeft[currentIndex], scale: sizeScale, decay: decay, sampleRate: sampleRate)
        bankR.configure(modes: modesRight[currentIndex], scale: sizeScale, decay: decay, sampleRate: sampleRate)
    }

    /// Ring 0 keeps a fifth of the body and 30% of its decay: dry, but still the material.
    private var bodyMixTarget: Float { baseBodyMix * (0.2 + 0.8 * ring) }

    private func readControls() {
        let c = control
        if c.material != materialIndex { selectMaterial(c.material) }

        let mode = c.mode
        if mode != .idle { lastMode = mode }
        let dragOn = c.dragEnabled
        let resizeOn = c.resizeEnabled
        dragTarget = (mode == .drag && dragOn) ? 1 : 0
        resizeTarget = (mode == .resize && resizeOn) ? 1 : 0
        targetSpeed = (dragTarget + resizeTarget) > 0 ? max(c.speed, 0) : 0
        panTarget = clamp(c.pan, -1, 1)
        grow = clamp(c.grow, -1, 1)
        volumeTarget = clamp(c.volume, 0, 1)
        reverbTarget = clamp(c.reverb, 0, 1)

        let scale = clamp(c.sizeScale, 0.5, 2)
        let newRing = clamp(c.ring, 0, 1)
        if abs(scale - sizeScale) > 0.005 || abs(newRing - ring) > 0.005 {
            sizeScale = scale
            ring = newRing
            configureBanks()
        }

        let enabled = (lastMode == .drag && dragOn) || (lastMode == .resize && resizeOn)
        let g = c.grabCount
        if g != seenGrab {
            seenGrab = g
            if enabled { impact.trigger(0.3); idle = false }
        }
        let r = c.releaseCount
        if r != seenRelease {
            seenRelease = r
            if enabled { impact.trigger(c.releaseStrength * (lastMode == .resize ? 0.6 : 1)); idle = false }
        }
        let b = c.bumpCount
        if b != seenBump {
            seenBump = b
            if enabled { impact.trigger(c.bumpStrength * 0.5); idle = false }
        }
        if dragTarget > 0 || resizeTarget > 0 { idle = false }
    }

    private func controlTick() {
        let norm = 1 - expf(-speed / Self.speedScale)
        jerk = max(jerk * 0.92, min(1, (norm - lastNorm) * 30))
        lastNorm = norm
        if sampleVoice.hasSample {
            sampleVoice.control(s: norm * (dragGate + resizeGate * rub), jerk: jerk)
        } else {
            slide.control(s: norm * (dragGate + resizeGate * rub), jerk: jerk)
        }
        if resizeVoice.hasSample {
            // A recorded squeak or groan replaces the synthesized squeal.
            resizeVoice.control(s: norm * resizeGate, jerk: jerk)
            stretch.control(s: 0, grow: grow)
        } else {
            stretch.control(s: norm * resizeGate, grow: grow)
        }
        // Equal-power balance of the stereo body, unity in the centre.
        let angle = (pan + 1) * 0.25 * Float.pi
        gainL = min(cosf(angle) * 1.41421356, 1.3)
        gainR = min(sinf(angle) * 1.41421356, 1.3)
    }

    /// Fills both channels. Returns false when the output is silent (idle).
    @discardableResult
    public func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) -> Bool {
        readControls()
        if idle {
            left.update(repeating: 0, count: frames)
            right.update(repeating: 0, count: frames)
            return false
        }

        var loud = false
        for i in 0..<frames {
            if blockCounter == 0 {
                controlTick()
                blockCounter = Self.blockSize
            }
            blockCounter -= 1

            speed += (targetSpeed - speed) * (targetSpeed > speed ? attack : release)
            dragGate += (dragTarget - dragGate) * gateCoef
            resizeGate += (resizeTarget - resizeGate) * gateCoef
            volume += (volumeTarget - volume) * slowCoef
            reverbAmount += (reverbTarget - reverbAmount) * slowCoef
            pan += (panTarget - pan) * slowCoef
            bodyMix += (bodyMixTarget - bodyMix) * slowCoef

            let recorded = sampleVoice.hasSample
            let s = recorded ? .zero : slide.tick(pxPerSample: speed * (dragGate + resizeGate * rub) / sampleRate)
            let drag = recorded ? sampleVoice.tick() : 0
            let r = stretch.tick()
            let resized = resizeVoice.hasSample ? resizeVoice.tick() : 0
            let k = impact.tick()
            let cont = s.cont + r.cont
            // With a recording, grab and release are a muffled thud: ringing the modelled body would
            // sound like a different object from the one in the recording.
            let knock = recorded ? thud.tick(force: k.imp, noise: k.direct, scale: sizeScale) : 0
            let imp = s.imp + r.imp + (recorded ? 0 : k.imp)
            let dry = (s.direct + r.direct + (recorded ? 0 : k.direct)) * (1 - bodyMix) + knock
            // A recording already contains its material's body, so it bypasses the resonators.
            var l = (dry + drag + resized + bankL.tick(cont: cont, imp: imp) * bodyMix) * level * gainL
            var rr = (dry + drag + resized + bankR.tick(cont: cont, imp: imp) * bodyMix) * level * gainR

            let wet = reverb.tick((l + rr) * 0.5 * reverbSend * reverbAmount)
            l += wet.left
            rr += wet.right

            // Gentle compressor: tames resonant build-ups and keeps knocks and scrapes even.
            let peak = max(abs(l), abs(rr))
            envelope += (peak - envelope) * (peak > envelope ? compAttack : compRelease)
            let target = envelope > Self.compThreshold
                ? (Self.compThreshold + (envelope - Self.compThreshold) / Self.compRatio) / envelope : 1
            compGain += (target - compGain) * compAttack
            l = softClip(l * compGain) * volume
            rr = softClip(rr * compGain) * volume

            left[i] = l
            right[i] = rr
            if abs(l) > 1e-4 || abs(rr) > 1e-4 { loud = true; quietSamples = 0 } else { quietSamples += 1 }
        }

        if !loud && dragTarget == 0 && resizeTarget == 0 && quietSamples > Int(sampleRate * 0.5) {
            idle = true
        }
        return true
    }
}

/// A muffled knock: a heavy object picked up or set down. A low, quickly damped resonance plus a
/// low-passed contact noise, with no ring. Bigger windows thud lower.
struct Thud {
    private let sampleRate: Float
    private var scale: Float = 0
    private var a1: Float = 0
    private var a2: Float = 0
    private var b: Float = 0
    private var y1: Float = 0
    private var y2: Float = 0
    private var lowpass = SVF()

    init(sampleRate: Float) {
        self.sampleRate = sampleRate
        lowpass.set(cutoff: 600, q: 0.6, sampleRate: sampleRate)
        setScale(1)
    }

    private mutating func setScale(_ scale: Float) {
        self.scale = scale
        let w = 2 * Float.pi * 105 * scale / sampleRate
        let r = powf(0.001, 1 / (0.07 * sampleRate))   // 70 ms decay
        a1 = 2 * r * cosf(w)
        a2 = -r * r
        b = sinf(w)
    }

    /// `force` is the knock's contact pulse, `noise` its contact noise.
    @inline(__always) mutating func tick(force: Float, noise: Float, scale: Float) -> Float {
        if scale != self.scale { setScale(scale) }
        if force == 0 && noise == 0 && abs(y1) < 1e-6 && abs(y2) < 1e-6 { return 0 }
        let y = b * force + a1 * y1 + a2 * y2
        y2 = y1
        y1 = y
        return y * 0.25 + lowpass.tick(noise).low * 0.4
    }
}
