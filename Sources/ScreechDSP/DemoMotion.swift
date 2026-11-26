import Foundation

/// A scripted, uneven hand gesture: crawl, fling, slow down, pause, jerks, reversal, crawl.
/// Used by the preview renderer and the app's "Try it" buttons.
public enum DemoMotion {
    public enum Kind: Sendable { case drag, resize }

    /// Time at which the scripted hand lets go.
    public static let duration = 3.45
    public static let start = Rect(x: 500, y: 300, width: 900, height: 600)

    /// Speed (pt/s) and direction (+1 / -1) at time `t`.
    static func profile(_ t: Double) -> (speed: Double, dir: Double) {
        func lerp(_ a: Double, _ b: Double, _ x: Double) -> Double { a + (b - a) * min(max(x, 0), 1) }
        let base: (Double, Double)
        switch t {
        case ..<0.25: base = (0, 1)                                      // grabbed, not moving yet
        case ..<1.0: base = (lerp(120, 260, (t - 0.25) / 0.75), 1)       // slow drag
        case ..<1.45:                                                    // fling
            let x = (t - 1.0) / 0.45
            base = (lerp(260, 1600, x * x * (3 - 2 * x)), 1)
        case ..<1.7: base = (lerp(1600, 250, (t - 1.45) / 0.25), 1)      // brake
        case ..<2.0: base = (0, 1)                                       // pause
        case ..<2.45: base = (Int((t - 2.0) / 0.075) % 2 == 0 ? 950 : 90, 1)  // jerky
        case ..<2.95: base = (700, -1)                                   // reverse
        case ..<duration: base = (55, -1)                                // crawl
        default: base = (0, -1)
        }
        let tremor = 1 + 0.22 * sin(2 * .pi * 7.3 * t) + 0.12 * sin(2 * .pi * 13.1 * t + 1)
        return (base.0 * tremor, base.1)
    }

    /// Window frames sampled at `rate` Hz. The frame itself only changes at
    /// `windowServerRate`, like a real window server, so many samples repeat.
    public static func frames(_ kind: Kind, rate: Double = 120, windowServerRate: Double = 60) -> [(time: Double, frame: Rect)] {
        var x = start.x, y = start.y, w = start.width, h = start.height
        var result: [(Double, Rect)] = []
        let fine = 1.0 / 2000
        var t = 0.0
        var nextSample = 0.0
        var shown = start
        var lastServerTick = -1
        while t <= duration {
            let (v, dir) = profile(t)
            switch kind {
            case .drag:
                let angle = 0.25 * sin(1.3 * t)
                x += dir * v * cos(angle) * fine
                y += v * sin(angle) * 0.6 * fine
            case .resize:
                w = max(200, w + dir * v * 0.8 * fine)
                h = max(150, h + dir * v * 0.6 * fine)
            }
            let tick = Int(t * windowServerRate)
            if tick != lastServerTick {
                lastServerTick = tick
                shown = Rect(x: x.rounded(), y: y.rounded(), width: w.rounded(), height: h.rounded())
            }
            if t >= nextSample {
                result.append((t, shown))
                nextSample += 1 / rate
            }
            t += fine
        }
        return result
    }
}
