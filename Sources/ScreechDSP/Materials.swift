import Foundation

public enum Materials {
    public static let all: [Material] = [wood, rubber, metal, glass, stone]

    public static func index(of id: String) -> Int {
        all.firstIndex { $0.id == id } ?? 0
    }

    public static let wood: Material = {
        var b = BodySpec()
        b.fundamental = 150; b.aspect = 0.55; b.count = 40; b.jitter = 0.04
        b.t60 = 0.3; b.dampingFreq = 1200; b.dampingExp = 1.3; b.tilt = 0.5; b.seed = 11
        var m = Material(id: "wood", name: "Wood", symbol: "tree.fill",
                         blurb: "Furniture dragged over a floor, hollow knocks, creaking stretch.", body: b)
        m.bodyMix = 0.7; m.reverbSend = 0.8
        m.impactsPerPixel = 0.6; m.impactTail = 2.2; m.contactHardness = 3500; m.contactGain = 1
        m.hiss = 0.5; m.textureDensity = 6; m.textureRoughness = 0.55
        m.slideLowpassMin = 900; m.slideLowpassMax = 5200; m.slideResonance = 0.8; m.slideHighpass = 80
        m.slideCurve = 1.1; m.slideGain = 0.33; m.chatter = 0.5; m.chatterRate = 28
        m.squealMin = 14; m.squealMax = 85; m.squealCurve = 0.8; m.bowPressure = 0.9; m.bowPosition = 0.13
        m.squealJitter = 0.35; m.squealNoise = 0.4; m.formant = 900; m.formantQ = 1.2; m.formantTrack = 0
        m.growBend = 0.3; m.stretchGain = 0.085; m.stretchRub = 0.3
        m.impactGain = 0.8; m.contactTime = 0.0015; m.impactNoise = 0.3; m.impactBrightness = 3000
        return m
    }()

    public static let rubber: Material = {
        var b = BodySpec()
        b.fundamental = 120; b.aspect = 1.0; b.count = 10; b.jitter = 0.08
        b.t60 = 0.06; b.dampingFreq = 500; b.dampingExp = 1.5; b.tilt = 1.0; b.seed = 22
        var m = Material(id: "rubber", name: "Rubber", symbol: "balloon.fill",
                         blurb: "A box squeaking along on rubber feet, balloon screech when stretched.", body: b)
        m.bodyMix = 0.45; m.reverbSend = 0.6
        m.impactsPerPixel = 0.15; m.impactTail = 3; m.contactHardness = 900; m.contactGain = 1
        m.hiss = 0.35; m.textureDensity = 3; m.textureRoughness = 0.25
        m.slideLowpassMin = 400; m.slideLowpassMax = 2600; m.slideResonance = 1.6; m.slideHighpass = 60
        m.slideCurve = 1.2; m.slideGain = 0.35; m.chatter = 0.8; m.chatterRate = 45
        m.squealMin = 320; m.squealMax = 1150; m.squealCurve = 0.7; m.bowPressure = 0.5; m.bowPosition = 0.11
        m.squealJitter = 0.12; m.squealNoise = 0.15; m.formant = 1400; m.formantQ = 2.5; m.formantTrack = 0.7
        m.growBend = 0.5; m.stretchGain = 0.84; m.stretchRub = 0.15
        m.impactGain = 0.7; m.contactTime = 0.005; m.impactNoise = 0.1; m.impactBrightness = 900
        return m
    }()

    public static let metal: Material = {
        var b = BodySpec()
        b.fundamental = 260; b.aspect = 1.37; b.count = 40; b.jitter = 0.01
        b.t60 = 2.4; b.dampingFreq = 6000; b.dampingExp = 0.8; b.tilt = 0.4; b.seed = 33
        var m = Material(id: "metal", name: "Metal", symbol: "gearshape.fill",
                         blurb: "A heavy metal pipe dragged over concrete, groaning squeal.", body: b)
        m.bodyMix = 0.7; m.reverbSend = 1.0
        m.impactsPerPixel = 0.8; m.impactTail = 2.5; m.contactHardness = 9000; m.contactGain = 1
        m.hiss = 0.4; m.textureDensity = 10; m.textureRoughness = 0.75
        m.slideLowpassMin = 1800; m.slideLowpassMax = 9000; m.slideResonance = 0.9; m.slideHighpass = 200
        m.slideCurve = 1.0; m.slideGain = 0.7; m.chatter = 0.3; m.chatterRate = 60
        m.squealMin = 330; m.squealMax = 950; m.squealCurve = 0.8; m.bowPressure = 0.35; m.bowPosition = 0.127
        m.squealJitter = 0.08; m.squealNoise = 0.05; m.formant = 2400; m.formantQ = 3; m.formantTrack = 0.3
        m.growBend = 0.4; m.stretchGain = 1.4; m.stretchRub = 0.2
        m.impactGain = 0.9; m.contactTime = 0.0006; m.impactNoise = 0.3; m.impactBrightness = 7000
        m.sampleGain = 2.6   // the pipe recording is quieter than the others
        return m
    }()

    public static let glass: Material = {
        var b = BodySpec()
        b.fundamental = 900; b.aspect = 1.15; b.count = 30; b.jitter = 0.005
        b.t60 = 1.3; b.dampingFreq = 7000; b.dampingExp = 0.9; b.tilt = 0.5; b.seed = 44
        var m = Material(id: "glass", name: "Glass", symbol: "wineglass.fill",
                         blurb: "Glass grinding on glass, wet-finger squeak on stretch.", body: b)
        m.bodyMix = 0.6; m.reverbSend = 1.0
        m.impactsPerPixel = 0.25; m.impactTail = 3; m.contactHardness = 8000; m.contactGain = 0.8
        m.hiss = 0.7; m.textureDensity = 4; m.textureRoughness = 0.15
        m.slideLowpassMin = 1200; m.slideLowpassMax = 7000; m.slideResonance = 0.7; m.slideHighpass = 400
        m.slideCurve = 1.3; m.slideGain = 0.68; m.chatter = 0.3; m.chatterRate = 35
        m.squealMin = 900; m.squealMax = 1700; m.squealCurve = 0.6; m.bowPressure = 0.25; m.bowPosition = 0.18
        m.squealJitter = 0.04; m.squealNoise = 0.03; m.formant = 2200; m.formantQ = 4; m.formantTrack = 0.85
        m.growBend = 0.35; m.stretchGain = 1.4; m.stretchRub = 0.1
        m.impactGain = 0.6; m.contactTime = 0.0004; m.impactNoise = 0.2; m.impactBrightness = 9000
        m.sampleGain = 1.95   // the bottles recording is a little quieter than the others
        return m
    }()

    public static let stone: Material = {
        var b = BodySpec()
        b.fundamental = 85; b.aspect = 0.8; b.count = 36; b.jitter = 0.12
        b.t60 = 0.12; b.dampingFreq = 900; b.dampingExp = 1.2; b.tilt = 0.6; b.seed = 55
        var m = Material(id: "stone", name: "Stone", symbol: "mountain.2.fill",
                         blurb: "A heavy stone slab grinding like a dungeon door, heavy thuds, rumbling stretch.", body: b)
        m.bodyMix = 0.6; m.reverbSend = 0.9
        m.impactsPerPixel = 1.5; m.impactTail = 1.8; m.contactHardness = 4500; m.contactGain = 1.2
        m.hiss = 0.5; m.textureDensity = 14; m.textureRoughness = 0.85
        m.slideLowpassMin = 700; m.slideLowpassMax = 6000; m.slideResonance = 0.7; m.slideHighpass = 50
        m.slideCurve = 1.25; m.slideGain = 0.31; m.chatter = 0.15; m.chatterRate = 22
        m.squealMin = 22; m.squealMax = 110; m.squealCurve = 0.9; m.bowPressure = 1.0; m.bowPosition = 0.15
        m.squealJitter = 0.6; m.squealNoise = 0.6; m.formant = 600; m.formantQ = 0.8; m.formantTrack = 0
        m.growBend = 0.2; m.stretchGain = 0.08; m.stretchRub = 0.5
        m.impactGain = 1.0; m.contactTime = 0.001; m.impactNoise = 0.5; m.impactBrightness = 2200
        return m
    }()
}
