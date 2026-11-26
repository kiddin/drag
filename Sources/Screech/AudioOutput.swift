import AVFoundation
import ScreechDSP

/// Owns the AVAudioEngine. Runs only around gestures so the app costs nothing while idle.
@MainActor
final class AudioOutput {
    let control: ControlBlock
    private var engine: AVAudioEngine?
    private var sleepTimer: Timer?
    private var configObserver: NSObjectProtocol?
    /// Recorded drag sounds shipped in Contents/Resources/Samples.
    private let samples: [String: DragSample]

    init(control: ControlBlock) {
        self.control = control
        let dir = Bundle.main.resourceURL?.appendingPathComponent("Samples")
        samples = dir.map { DragSamples.load(from: $0) } ?? [:]
    }

    /// Start (or keep) the engine running.
    func wake() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        if engine == nil { build() }
        guard let engine, !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            NSLog("Screech: audio engine failed to start: \(error)")
        }
    }

    /// Pause the engine after a quiet period (long enough for metal to ring out).
    func scheduleSleep(after seconds: TimeInterval = 20) {
        sleepTimer?.invalidate()
        sleepTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.engine?.pause() }
        }
    }

    func shutdown() {
        sleepTimer?.invalidate()
        engine?.stop()
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        engine = nil
    }

    private func build() {
        let engine = AVAudioEngine()
        let hardware = engine.outputNode.outputFormat(forBus: 0)
        let sampleRate = hardware.sampleRate > 0 ? hardware.sampleRate : 48000
        let synth = Synth(sampleRate: Float(sampleRate), control: control, samples: samples)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }

        let source = AVAudioSourceNode(format: format) { isSilence, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard buffers.count >= 2,
                  let l = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let r = buffers[1].mData?.assumingMemoryBound(to: Float.self)
            else { return noErr }
            if !synth.render(left: l, right: r, frames: Int(frameCount)) {
                isSilence.pointee = true
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.prepare()

        // Output device or sample rate changed: rebuild on the next wake.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let wasRunning = self.engine?.isRunning ?? false
                self.shutdown()
                if wasRunning { self.wake() }
            }
        }
        self.engine = engine
    }
}
