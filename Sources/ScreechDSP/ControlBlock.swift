import Foundation
import Synchronization

public enum MotionMode: Int, Sendable {
    case idle = 0, drag = 1, resize = 2
}

/// Lock-free parameters shared between the tracker / UI and the audio thread.
/// Writers store plain values; one-shot events are counters the synth compares.
public final class ControlBlock: @unchecked Sendable {
    private let _mode = Atomic<Int>(0)
    private let _speed = Atomic<UInt32>(0)
    private let _pan = Atomic<UInt32>(0)
    private let _grow = Atomic<UInt32>(0)
    private let _sizeScale = Atomic<UInt32>(Float(1).bitPattern)
    private let _material = Atomic<Int>(0)
    private let _volume = Atomic<UInt32>(Float(0.7).bitPattern)
    private let _reverb = Atomic<UInt32>(Float(0.35).bitPattern)
    private let _ring = Atomic<UInt32>(Float(1).bitPattern)
    private let _dragEnabled = Atomic<Bool>(true)
    private let _resizeEnabled = Atomic<Bool>(true)
    private let _grab = Atomic<Int>(0)
    private let _release = Atomic<Int>(0)
    private let _releaseStrength = Atomic<UInt32>(0)
    private let _bump = Atomic<Int>(0)
    private let _bumpStrength = Atomic<UInt32>(0)

    public init() {}

    public var mode: MotionMode {
        get { MotionMode(rawValue: _mode.load(ordering: .relaxed)) ?? .idle }
        set { _mode.store(newValue.rawValue, ordering: .relaxed) }
    }

    /// Window speed in points per second (drag) or size change rate (resize).
    public var speed: Float {
        get { Float(bitPattern: _speed.load(ordering: .relaxed)) }
        set { _speed.store(newValue.bitPattern, ordering: .relaxed) }
    }

    /// -1 (left) ... 1 (right).
    public var pan: Float {
        get { Float(bitPattern: _pan.load(ordering: .relaxed)) }
        set { _pan.store(newValue.bitPattern, ordering: .relaxed) }
    }

    /// -1 shrinking, 1 growing.
    public var grow: Float {
        get { Float(bitPattern: _grow.load(ordering: .relaxed)) }
        set { _grow.store(newValue.bitPattern, ordering: .relaxed) }
    }

    /// Body pitch scale: bigger windows sound lower.
    public var sizeScale: Float {
        get { Float(bitPattern: _sizeScale.load(ordering: .relaxed)) }
        set { _sizeScale.store(newValue.bitPattern, ordering: .relaxed) }
    }

    /// Index into `Materials.all`.
    public var material: Int {
        get { _material.load(ordering: .relaxed) }
        set { _material.store(newValue, ordering: .relaxed) }
    }

    /// 0...1. Zero mutes.
    public var volume: Float {
        get { Float(bitPattern: _volume.load(ordering: .relaxed)) }
        set { _volume.store(newValue.bitPattern, ordering: .relaxed) }
    }

    /// 0...1 room reverb amount.
    public var reverb: Float {
        get { Float(bitPattern: _reverb.load(ordering: .relaxed)) }
        set { _reverb.store(newValue.bitPattern, ordering: .relaxed) }
    }

    /// 0...1 how much the material's body resonates: 0 = mostly dry scrape, 1 = as designed.
    public var ring: Float {
        get { Float(bitPattern: _ring.load(ordering: .relaxed)) }
        set { _ring.store(newValue.bitPattern, ordering: .relaxed) }
    }

    public var dragEnabled: Bool {
        get { _dragEnabled.load(ordering: .relaxed) }
        set { _dragEnabled.store(newValue, ordering: .relaxed) }
    }

    public var resizeEnabled: Bool {
        get { _resizeEnabled.load(ordering: .relaxed) }
        set { _resizeEnabled.store(newValue, ordering: .relaxed) }
    }

    public func triggerGrab() {
        _grab.wrappingAdd(1, ordering: .releasing)
    }

    public func triggerRelease(strength: Float) {
        _releaseStrength.store(strength.bitPattern, ordering: .relaxed)
        _release.wrappingAdd(1, ordering: .releasing)
    }

    public func triggerBump(strength: Float) {
        _bumpStrength.store(strength.bitPattern, ordering: .relaxed)
        _bump.wrappingAdd(1, ordering: .releasing)
    }

    var grabCount: Int { _grab.load(ordering: .acquiring) }
    var releaseCount: Int { _release.load(ordering: .acquiring) }
    var releaseStrength: Float { Float(bitPattern: _releaseStrength.load(ordering: .relaxed)) }
    var bumpCount: Int { _bump.load(ordering: .acquiring) }
    var bumpStrength: Float { Float(bitPattern: _bumpStrength.load(ordering: .relaxed)) }
}
