import Foundation

/// A window frame in screen points (any origin convention, as long as it is consistent).
public struct Rect: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct MotionOutput: Sendable, Equatable {
    public var mode: MotionMode = .idle
    /// Points per second: window travel for drags, size change for resizes.
    public var speed: Double = 0
    /// -1 shrinking, 0 unknown, 1 growing.
    public var grow: Double = 0
    /// -1 left ... 1 right.
    public var pan: Double = 0
    /// > 0 on the sample where the drag direction reversed (strength 0...1).
    public var bump: Double = 0
    /// True on the first sample that showed motion in this gesture.
    public var engagedNow = false
}

/// Turns a stream of sampled window frames into gesture mode and speed.
///
/// Window servers and apps update frames at their own (uneven) rate, so samples often repeat.
/// Speed is measured between *changes*, held across repeats, and dropped to zero only after
/// the window has been still for a short while.
public struct MotionAnalyzer: Sendable {
    public private(set) var mode: MotionMode = .idle
    public private(set) var speed: Double = 0
    /// Recent peak speed, decaying over ~150 ms. Sets the strength of the release thud.
    public private(set) var recentPeak: Double = 0
    public private(set) var sizeScale: Double = 1

    private var last = Rect(x: 0, y: 0, width: 0, height: 0)
    private var lastChange: Double = 0
    private var lastTime: Double = 0
    private var vx: Double = 0
    private var vy: Double = 0
    private var grow: Double = 0
    private var lastBump: Double = -1
    private var desktopMinX: Double = 0
    private var desktopWidth: Double = 1

    public static let maxSpeed = 4000.0
    public static let stillAfterDrag = 0.05
    public static let stillAfterResize = 0.09

    public init() {}

    public mutating func begin(frame: Rect, time: Double, desktopMinX: Double, desktopWidth: Double) {
        mode = .idle
        speed = 0
        recentPeak = 0
        last = frame
        lastChange = time
        lastTime = time
        vx = 0
        vy = 0
        grow = 0
        lastBump = -1
        self.desktopMinX = desktopMinX
        self.desktopWidth = max(desktopWidth, 1)
        let area = max(frame.width * frame.height, 1)
        sizeScale = min(max(pow(area / (900 * 600), -0.12), 0.8), 1.25)
    }

    public mutating func update(frame: Rect, time: Double) -> MotionOutput {
        var out = MotionOutput()
        let dx = frame.x - last.x
        let dy = frame.y - last.y
        let dw = frame.width - last.width
        let dh = frame.height - last.height
        let resized = abs(dw) >= 1 || abs(dh) >= 1
        let moved = abs(dx) >= 1 || abs(dy) >= 1

        if resized || moved {
            // Time since the previous change. Capped so the first step after a pause
            // is not spread over the whole pause.
            let dt = min(max(time - lastChange, 1.0 / 240), 1.0 / 30)
            if mode == .idle {
                // A gesture cannot switch between drag and resize, so lock it in.
                mode = resized ? .resize : .drag
                out.engagedNow = true
            }
            var raw = speed
            switch mode {
            case .resize:
                if resized {
                    raw = (dw * dw + dh * dh).squareRoot() / dt
                    grow = (dw + dh) >= 0 ? 1 : -1
                }
            case .drag:
                if resized {
                    // Tiling / snapping while dragging: a knock, not a speed spike.
                    out.bump = 0.5
                } else {
                    let nvx = dx / dt
                    let nvy = dy / dt
                    let a = (nvx * nvx + nvy * nvy).squareRoot()
                    let b = (vx * vx + vy * vy).squareRoot()
                    let dot = nvx * vx + nvy * vy
                    if a > 150, b > 150, dot < -0.2 * a * b, time - lastBump > 0.15 {
                        out.bump = min(1, 0.2 + (a + b) / 3000)
                        lastBump = time
                    }
                    vx = vx * 0.5 + nvx * 0.5
                    vy = vy * 0.5 + nvy * 0.5
                    raw = a
                }
            case .idle:
                break
            }
            speed = speed * 0.3 + min(raw, Self.maxSpeed) * 0.7
            lastChange = time
            last = frame
        } else {
            let still = mode == .resize ? Self.stillAfterResize : Self.stillAfterDrag
            if time - lastChange > still {
                speed = 0
                vx = 0
                vy = 0
            }
        }

        recentPeak = max(speed, recentPeak * exp(-(time - lastTime) / 0.15))
        lastTime = time

        let centre = frame.x + frame.width / 2
        out.mode = mode
        out.speed = speed
        out.grow = grow
        out.pan = min(max(((centre - desktopMinX) / desktopWidth * 2 - 1) * 0.8, -1), 1)
        return out
    }
}

extension ControlBlock {
    /// Publishes one analyzer step to the audio thread.
    public func apply(_ o: MotionOutput) {
        pan = Float(o.pan)
        grow = Float(o.grow)
        speed = Float(o.speed)
        mode = o.mode
        if o.engagedNow { triggerGrab() }
        if o.bump > 0 { triggerBump(strength: Float(o.bump)) }
    }

    /// Ends a gesture. A release thud plays only if the window actually moved.
    public func endGesture(_ analyzer: MotionAnalyzer, released: Bool) {
        if released && analyzer.mode != .idle {
            triggerRelease(strength: Float(0.25 + 0.75 * (1 - exp(-analyzer.recentPeak / 700))))
        }
        mode = .idle
        speed = 0
    }
}
