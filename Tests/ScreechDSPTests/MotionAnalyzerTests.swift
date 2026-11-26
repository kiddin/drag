import XCTest
@testable import ScreechDSP

final class MotionAnalyzerTests: XCTestCase {
    /// Feeds frames at 120 Hz, where the window only changes every `every` samples.
    func run(_ start: Rect, steps: Int, every: Int = 2, change: (Int, inout Rect) -> Void) -> [MotionOutput] {
        var a = MotionAnalyzer()
        a.begin(frame: start, time: 0, desktopMinX: 0, desktopWidth: 2000)
        var frame = start
        var outs: [MotionOutput] = []
        for i in 1...steps {
            if i % every == 0 { change(i, &frame) }
            outs.append(a.update(frame: frame, time: Double(i) / 120))
        }
        return outs
    }

    let start = Rect(x: 100, y: 100, width: 800, height: 600)

    func testStillWindowStaysIdle() {
        let outs = run(start, steps: 60) { _, _ in }
        XCTAssertTrue(outs.allSatisfy { $0.mode == .idle && $0.speed == 0 && !$0.engagedNow })
    }

    func testDragIsDetectedWithSteadySpeedDespiteRepeatedFrames() {
        // 10 pt per window-server frame at 60 Hz = 600 pt/s
        let outs = run(start, steps: 60) { _, f in f.x += 10 }
        XCTAssertEqual(outs.filter(\.engagedNow).count, 1)
        XCTAssertTrue(outs.suffix(40).allSatisfy { $0.mode == .drag })
        for o in outs.suffix(30) {
            XCTAssertEqual(o.speed, 600, accuracy: 40, "speed must not flicker on repeated frames")
        }
    }

    func testDragSpeedAtTheAppsSixtyHertzSamplingWithJitter() {
        // The app samples at 60 Hz with a slightly late timer; the window moves 600 pt/s.
        var a = MotionAnalyzer()
        a.begin(frame: start, time: 0, desktopMinX: 0, desktopWidth: 2000)
        var outs: [MotionOutput] = []
        for i in 1...60 {
            let t = Double(i) / 60 + (i % 3 == 0 ? 0.002 : 0)
            let f = Rect(x: start.x + 600 * t, y: start.y, width: start.width, height: start.height)
            outs.append(a.update(frame: f, time: t))
        }
        XCTAssertTrue(outs.suffix(40).allSatisfy { $0.mode == .drag })
        for o in outs.suffix(30) { XCTAssertEqual(o.speed, 600, accuracy: 60) }
    }

    func testResizeFromLeftEdgeIsResize() {
        // Left-edge resize moves the origin and changes the width together.
        let outs = run(start, steps: 40) { _, f in f.x -= 5; f.width += 5 }
        XCTAssertEqual(outs.last?.mode, .resize)
        XCTAssertEqual(outs.last?.grow, 1)
    }

    func testShrinkingResize() {
        let outs = run(start, steps: 40) { _, f in f.width -= 4; f.height -= 3 }
        XCTAssertEqual(outs.last?.mode, .resize)
        XCTAssertEqual(outs.last?.grow, -1)
        XCTAssertEqual(outs.last!.speed, 300, accuracy: 30)
    }

    func testPauseDropsSpeedToZero() {
        let outs = run(start, steps: 80) { i, f in if i < 30 { f.x += 8 } }
        XCTAssertGreaterThan(outs[25].speed, 0)
        XCTAssertEqual(outs.last?.speed, 0)
        XCTAssertEqual(outs.last?.mode, .drag, "mode stays locked for the gesture")
    }

    func testDirectionReversalBumps() {
        let outs = run(start, steps: 80) { i, f in f.x += i < 40 ? 10 : -10 }
        let bumps = outs.filter { $0.bump > 0 }
        XCTAssertEqual(bumps.count, 1)
    }

    func testTeleportIsClamped() {
        let outs = run(start, steps: 10) { i, f in if i == 4 { f.x += 3000 } }
        XCTAssertLessThanOrEqual(outs.map(\.speed).max()!, MotionAnalyzer.maxSpeed)
    }

    func testPanFollowsWindowCentre() {
        var a = MotionAnalyzer()
        a.begin(frame: Rect(x: 0, y: 0, width: 200, height: 200), time: 0, desktopMinX: 0, desktopWidth: 2000)
        let left = a.update(frame: Rect(x: 0, y: 0, width: 200, height: 200), time: 0.01).pan
        let right = a.update(frame: Rect(x: 1800, y: 0, width: 200, height: 200), time: 0.02).pan
        XCTAssertLessThan(left, -0.5)
        XCTAssertGreaterThan(right, 0.5)
    }

    func testDemoMotionDrivesBothModes() {
        for (kind, mode) in [(DemoMotion.Kind.drag, MotionMode.drag), (.resize, .resize)] {
            let frames = DemoMotion.frames(kind)
            var a = MotionAnalyzer()
            a.begin(frame: frames[0].frame, time: 0, desktopMinX: 0, desktopWidth: 2000)
            var maxSpeed = 0.0
            for (t, f) in frames { maxSpeed = max(maxSpeed, a.update(frame: f, time: t).speed) }
            XCTAssertEqual(a.mode, mode)
            XCTAssertGreaterThan(maxSpeed, 1000)
        }
    }
}
