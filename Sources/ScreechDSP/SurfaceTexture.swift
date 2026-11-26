import Foundation

/// A looped 1-D height map of a surface. The drag voice reads it like a stylus:
/// the read speed follows the window speed, so slow drags crackle and fast drags hiss.
enum SurfaceTexture {
    static let size = 1 << 16
    static let mask = size - 1

    /// Fractal value noise. The per-sample slope is normalised to unit RMS.
    static func make(roughness: Float, seed: UInt32) -> UnsafeMutablePointer<Float> {
        let table = UnsafeMutablePointer<Float>.allocate(capacity: size)
        table.initialize(repeating: 0, count: size)
        var rng = Rng(seed: seed)

        for octave in 0..<14 {
            let period = 1 << octave
            let points = size / period
            let amplitude = powf(Float(period), 1 - roughness)
            var values = [Float](repeating: 0, count: points)
            for j in 0..<points { values[j] = rng.bipolar() }
            for i in 0..<size {
                let p = i / period
                let f = Float(i % period) / Float(period)
                let w = f * f * (3 - 2 * f)
                let a = values[p]
                let b = values[(p + 1) % points]
                table[i] += (a + (b - a) * w) * amplitude
            }
        }

        var sumSquares: Double = 0
        for i in 0..<size {
            let d = Double(table[(i + 1) & mask] - table[i])
            sumSquares += d * d
        }
        let scale = Float(1 / max(sqrt(sumSquares / Double(size)), 1e-9))
        for i in 0..<size { table[i] *= scale }
        return table
    }
}
