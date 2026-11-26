import XCTest
@testable import ScreechDSP

final class SynthTests: XCTestCase {
    let sr: Float = 48000

    /// Renders `seconds` of a steady gesture and returns the mono signal of the last half.
    func steady(_ mode: MotionMode, speed: Float, material: Int, grow: Float = 1, seconds: Double = 1) -> [Float] {
        let synth = Synth(sampleRate: sr)
        synth.control.material = material
        synth.control.volume = 1
        synth.control.mode = mode
        synth.control.speed = speed
        synth.control.grow = grow
        let n = Int(Double(sr) * seconds)
        var l = [Float](repeating: 0, count: n)
        var r = [Float](repeating: 0, count: n)
        l.withUnsafeMutableBufferPointer { lp in
            r.withUnsafeMutableBufferPointer { rp in
                var off = 0
                while off < n {
                    let k = min(512, n - off)
                    synth.render(left: lp.baseAddress! + off, right: rp.baseAddress! + off, frames: k)
                    off += k
                }
            }
        }
        return Array(zip(l, r).map { $0 + $1 }.suffix(n / 2))
    }

    func rms(_ x: [Float]) -> Float {
        (x.reduce(0) { $0 + $1 * $1 } / Float(max(x.count, 1))).squareRoot()
    }

    /// Zero crossings per second: a cheap brightness / pitch proxy.
    func zcr(_ x: [Float]) -> Float {
        var c = 0
        for i in 1..<x.count where (x[i - 1] < 0) != (x[i] < 0) { c += 1 }
        return Float(c) / (Float(x.count) / sr)
    }

    func testRingControlsRingOut() {
        let metal = Materials.index(of: "metal")
        func tail(_ ring: Float) -> Float {
            let (l, r) = OfflineRender.gesture(.drag, material: metal, ring: ring)
            let start = Int(Double(sr) * (DemoMotion.duration + 0.1))
            return rms(Array(zip(l, r).map { $0 + $1 }[start...]))
        }
        let dry = tail(0), full = tail(1)
        XCTAssertTrue(dry.isFinite && full.isFinite)
        XCTAssertLessThan(dry, full * 0.6, "ring 0 should ring out much less than ring 1")
    }

    func testSilentWhenIdle() {
        for i in Materials.all.indices {
            let x = steady(.idle, speed: 0, material: i)
            XCTAssertEqual(rms(x), 0, "material \(i)")
        }
    }

    func testSilentWhenStill() {
        for i in Materials.all.indices {
            let x = steady(.drag, speed: 0, material: i)
            XCTAssertLessThan(rms(x), 1e-4, Materials.all[i].id)
        }
    }

    func testDragGetsLouderAndBrighterWithSpeed() {
        for (i, m) in Materials.all.enumerated() {
            let slow = steady(.drag, speed: 150, material: i)
            let medium = steady(.drag, speed: 400, material: i)
            let fast = steady(.drag, speed: 1500, material: i)
            XCTAssertGreaterThan(rms(slow), 1e-4, "\(m.id) slow drag should be audible")
            XCTAssertGreaterThan(rms(fast), rms(slow) * 1.5, "\(m.id) louder when faster")
            // Brightness from a medium pace: at a crawl, stick-slip chatter rings the body instead.
            XCTAssertGreaterThan(zcr(fast), zcr(medium), "\(m.id) brighter when faster")
        }
    }

    func testResizeGetsLouderWithSpeed() {
        for (i, m) in Materials.all.enumerated() {
            let slow = steady(.resize, speed: 100, material: i)
            let fast = steady(.resize, speed: 1500, material: i)
            XCTAssertGreaterThan(rms(slow), 1e-4, "\(m.id) slow resize should be audible")
            XCTAssertGreaterThan(rms(fast), rms(slow), "\(m.id) louder when faster")
        }
    }

    func testRubberSquealPitchFollowsSpeedAndDirection() {
        let i = Materials.index(of: "rubber")
        let slow = zcr(steady(.resize, speed: 150, material: i))
        let fast = zcr(steady(.resize, speed: 2000, material: i))
        XCTAssertGreaterThan(fast, slow * 1.3)
        let growing = zcr(steady(.resize, speed: 800, material: i, grow: 1))
        let shrinking = zcr(steady(.resize, speed: 800, material: i, grow: -1))
        XCTAssertGreaterThan(growing, shrinking)
    }

    func testOutputFiniteAndBoundedUnderChaos() {
        var rng = Rng(seed: 42)
        for i in Materials.all.indices {
            let synth = Synth(sampleRate: sr)
            synth.control.material = i
            synth.control.volume = 1
            var l = [Float](repeating: 0, count: 256)
            var r = [Float](repeating: 0, count: 256)
            for step in 0..<600 {
                if step % 7 == 0 {
                    synth.control.mode = MotionMode(rawValue: Int(rng.next() % 3))!
                    synth.control.speed = rng.uniform() * 6000
                    synth.control.grow = rng.bipolar()
                    synth.control.pan = rng.bipolar() * 2
                    synth.control.sizeScale = 0.5 + rng.uniform() * 1.5
                }
                if step % 23 == 0 { synth.control.triggerRelease(strength: rng.uniform() * 2) }
                if step % 31 == 0 { synth.control.triggerBump(strength: 1) }
                if step % 97 == 0 { synth.control.material = Int(rng.next() % 5) }
                l.withUnsafeMutableBufferPointer { lp in
                    r.withUnsafeMutableBufferPointer { rp in
                        synth.render(left: lp.baseAddress!, right: rp.baseAddress!, frames: 256)
                    }
                }
                for v in l + r {
                    XCTAssertTrue(v.isFinite)
                    XCTAssertLessThanOrEqual(abs(v), 1.0)
                }
            }
        }
    }

    func testMaterialsSoundDifferent() {
        let features = Materials.all.indices.map { i -> [Float] in
            let d = steady(.drag, speed: 800, material: i)
            let r = steady(.resize, speed: 800, material: i)
            return [zcr(d), rms(d), zcr(r), rms(r)]
        }
        for a in features.indices {
            for b in features.indices where b > a {
                let differs = zip(features[a], features[b]).contains { x, y in
                    abs(x - y) / max(abs(x), abs(y), 1e-6) > 0.15
                }
                XCTAssertTrue(differs, "\(Materials.all[a].id) vs \(Materials.all[b].id) too similar")
            }
        }
    }

    func testReverbIsStableAndDecays() {
        let reverb = Reverb(sampleRate: sr)
        var early: Float = 0
        var late: Float = 0
        for n in 0..<Int(sr * 4) {
            let (l, r) = reverb.tick(n == 0 ? 1 : 0)
            XCTAssertTrue(l.isFinite && r.isFinite)
            let e = l * l + r * r
            if n < Int(sr * 0.3) { early += e } else if n > Int(sr * 3) { late += e }
        }
        XCTAssertGreaterThan(early, 0)
        XCTAssertLessThan(late, early * 1e-4)
    }

    func testReverbAddsATail() {
        func tailEnergy(reverb: Float) -> Float {
            let synth = Synth(sampleRate: sr)
            synth.control.material = Materials.index(of: "rubber")
            synth.control.reverb = reverb
            synth.control.mode = .drag
            synth.control.speed = 1200
            var l = [Float](repeating: 0, count: 512)
            var r = [Float](repeating: 0, count: 512)
            var energy: Float = 0
            for block in 0..<150 {
                if block == 50 { synth.control.mode = .idle }
                l.withUnsafeMutableBufferPointer { lp in
                    r.withUnsafeMutableBufferPointer { rp in
                        synth.render(left: lp.baseAddress!, right: rp.baseAddress!, frames: 512)
                    }
                }
                if block > 60 { energy += l.reduce(0) { $0 + $1 * $1 } }
            }
            return energy
        }
        XCTAssertGreaterThan(tailEnergy(reverb: 1), tailEnergy(reverb: 0) * 3)
    }

    func testGoesIdleAfterRelease() {
        let synth = Synth(sampleRate: sr)
        synth.control.material = Materials.index(of: "wood")
        synth.control.mode = .drag
        synth.control.speed = 800
        var l = [Float](repeating: 0, count: 512)
        var r = [Float](repeating: 0, count: 512)
        func run(_ blocks: Int) {
            for _ in 0..<blocks {
                l.withUnsafeMutableBufferPointer { lp in
                    r.withUnsafeMutableBufferPointer { rp in
                        synth.render(left: lp.baseAddress!, right: rp.baseAddress!, frames: 512)
                    }
                }
            }
        }
        run(40)
        XCTAssertFalse(synth.isIdle)
        synth.control.mode = .idle
        synth.control.triggerRelease(strength: 1)
        run(200)
        XCTAssertTrue(synth.isIdle)
    }
}
