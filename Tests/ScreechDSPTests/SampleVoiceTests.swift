import XCTest
@testable import ScreechDSP

final class SampleVoiceTests: XCTestCase {
    let sr: Float = 48000

    /// A stand-in recording: 3 s of noise, so the tests do not depend on the shipped files.
    func fakeSamples() -> [String: DragSample] {
        var rng = Rng(seed: 7)
        let noise = (0..<Int(sr * 3)).map { _ in rng.bipolar() * 0.3 }
        return Dictionary(uniqueKeysWithValues: Materials.all.map { ($0.id, DragSample(samples: noise, sampleRate: 44100)) })
    }

    func steady(speed: Float, material: Int, samples: [String: DragSample]) -> [Float] {
        let synth = Synth(sampleRate: sr, samples: samples)
        synth.control.material = material
        synth.control.volume = 1
        synth.control.mode = .drag
        synth.control.speed = speed
        let n = Int(sr)
        var l = [Float](repeating: 0, count: n), r = [Float](repeating: 0, count: n)
        l.withUnsafeMutableBufferPointer { lp in
            r.withUnsafeMutableBufferPointer { rp in
                var o = 0
                while o < n { synth.render(left: lp.baseAddress! + o, right: rp.baseAddress! + o, frames: 512); o += 512 }
            }
        }
        return Array(zip(l, r).map { $0 + $1 }.suffix(n / 2))
    }

    func rms(_ x: [Float]) -> Float { (x.reduce(0) { $0 + $1 * $1 } / Float(max(x.count, 1))).squareRoot() }

    func testRecordedDragSilentWhenStill() {
        let s = fakeSamples()
        for i in Materials.all.indices {
            XCTAssertLessThan(rms(steady(speed: 0, material: i, samples: s)), 1e-4)
        }
    }

    func testRecordedDragLouderWithSpeedAndBounded() {
        let s = fakeSamples()
        for (i, m) in Materials.all.enumerated() {
            let slow = steady(speed: 150, material: i, samples: s)
            let fast = steady(speed: 1500, material: i, samples: s)
            XCTAssertGreaterThan(rms(fast), rms(slow) * 1.5, m.id)
            XCTAssertTrue(fast.allSatisfy { $0.isFinite && abs($0) <= 2 }, m.id)
        }
    }

    func testShippedRecordingsLoad() throws {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Samples")
        let loaded = DragSamples.load(from: dir)
        for m in Materials.all {
            let s = try XCTUnwrap(loaded[m.id], "missing \(m.id).wav")
            // Grains need half a second; under about 1.5 s a recording starts to sound repetitive.
            XCTAssertGreaterThan(Float(s.samples.count) / s.sampleRate, 1.5, m.id)
            XCTAssertGreaterThan(rms(steady(speed: 800, material: Materials.index(of: m.id), samples: loaded)), 0.05, m.id)
        }
        // Metal and glass resize with recordings too.
        for id in ["metal", "glass"] {
            let s = try XCTUnwrap(loaded[id + DragSamples.resizeSuffix], "missing \(id)-resize.wav")
            XCTAssertGreaterThan(Float(s.samples.count) / s.sampleRate, 1.5, id)
        }
    }
}
