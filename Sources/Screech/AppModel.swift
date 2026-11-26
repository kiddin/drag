import AppKit
import Observation
import ScreechDSP
import ServiceManagement

@MainActor
@Observable
final class AppModel {
    @ObservationIgnored let control = ControlBlock()
    @ObservationIgnored private let audio: AudioOutput
    @ObservationIgnored private let tracker: WindowTracker
    @ObservationIgnored private let defaults = UserDefaults.standard

    var enabled: Bool { didSet { defaults.set(enabled, forKey: "enabled"); applyEnabled() } }
    var materialID: String { didSet { defaults.set(materialID, forKey: "material"); applySound() } }
    var volume: Double { didSet { defaults.set(volume, forKey: "volume"); applySound() } }
    var reverb: Double { didSet { defaults.set(reverb, forKey: "reverb"); applySound() } }
    var ring: Double { didSet { defaults.set(ring, forKey: "ring"); applySound() } }
    var dragSounds: Bool { didSet { defaults.set(dragSounds, forKey: "drag"); applySound() } }
    var resizeSounds: Bool { didSet { defaults.set(resizeSounds, forKey: "resize"); applySound() } }
    var launchAtLogin: Bool
    var loginItemError: String?

    var statusMode: MotionMode = .idle
    var statusSpeed: Double = 0
    var statusApp = ""

    var material: Material { Materials.all[Materials.index(of: materialID)] }

    init() {
        defaults.register(defaults: ["enabled": true, "material": "wood", "volume": 0.7, "reverb": 0.35, "ring": 1.0, "drag": true, "resize": true])
        enabled = defaults.bool(forKey: "enabled")
        materialID = defaults.string(forKey: "material") ?? "wood"
        volume = defaults.double(forKey: "volume")
        reverb = defaults.double(forKey: "reverb")
        ring = defaults.double(forKey: "ring")
        dragSounds = defaults.bool(forKey: "drag")
        resizeSounds = defaults.bool(forKey: "resize")
        launchAtLogin = SMAppService.mainApp.status == .enabled

        audio = AudioOutput(control: control)
        tracker = WindowTracker(control: control)
        tracker.onPress = { [weak self] in self?.audio.wake() }
        tracker.onRelease = { [weak self] in self?.audio.scheduleSleep() }
        tracker.onStatus = { [weak self] status in
            guard let self else { return }
            statusMode = status.mode
            statusSpeed = status.speed
            statusApp = status.app
        }
        applySound()
        applyEnabled()
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func preview(_ kind: DemoMotion.Kind) {
        audio.wake()
        tracker.playDemo(kind)
    }

    func quit() {
        tracker.stop()
        audio.shutdown()
        NSApp.terminate(nil)
    }

    private func applySound() {
        control.material = Materials.index(of: materialID)
        control.volume = Float(volume)
        control.reverb = Float(reverb)
        control.ring = Float(ring)
        control.dragEnabled = dragSounds
        control.resizeEnabled = resizeSounds
    }

    private func applyEnabled() {
        if enabled { tracker.start() } else { tracker.stop() }
    }
}
