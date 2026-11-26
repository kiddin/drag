import Foundation

/// Renders a scripted gesture through the full pipeline (analyzer -> control -> synth).
public enum OfflineRender {
    public static func gesture(_ kind: DemoMotion.Kind, material: Int, style: DemoMotion.Style = .uneven, volume: Float = 1,
                               ring: Float = 1, samples: [String: DragSample] = [:], sampleRate: Float = 48000, tail: Double = 0.9)
        -> (left: [Float], right: [Float])
    {
        let control = ControlBlock()
        control.ring = ring
        let synth = Synth(sampleRate: sampleRate, control: control, samples: samples)
        control.material = material
        control.volume = volume
        let frames = DemoMotion.frames(kind, style: style)
        var analyzer = MotionAnalyzer()
        analyzer.begin(frame: frames[0].frame, time: 0, desktopMinX: 0, desktopWidth: 2000)
        control.sizeScale = Float(analyzer.sizeScale)

        var left: [Float] = []
        var right: [Float] = []
        let block = Int(sampleRate / 120)
        var l = [Float](repeating: 0, count: block)
        var r = [Float](repeating: 0, count: block)

        func renderBlock() {
            l.withUnsafeMutableBufferPointer { lp in
                r.withUnsafeMutableBufferPointer { rp in
                    _ = synth.render(left: lp.baseAddress!, right: rp.baseAddress!, frames: block)
                }
            }
            left += l
            right += r
        }

        for (t, f) in frames {
            control.apply(analyzer.update(frame: f, time: t))
            renderBlock()
        }
        control.endGesture(analyzer, released: true)
        for _ in 0..<Int(tail * 120) { renderBlock() }
        return (left, right)
    }

    /// 16-bit stereo PCM WAV.
    public static func wav(left: [Float], right: [Float], sampleRate: Int) -> Data {
        let frames = min(left.count, right.count)
        var data = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(frames * 4)
        data.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(2)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 4)); u16(4); u16(16)
        data.append(contentsOf: Array("data".utf8)); u32(bytes)
        for i in 0..<frames {
            u16(UInt16(bitPattern: Int16(max(-1, min(1, left[i])) * 32767)))
            u16(UInt16(bitPattern: Int16(max(-1, min(1, right[i])) * 32767)))
        }
        return data
    }
}
