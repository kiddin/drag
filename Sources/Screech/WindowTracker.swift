import AppKit
import ScreechDSP

/// Notices mouse presses system-wide and samples the frame of the window under the cursor
/// while the button is held. Needs no Accessibility or Screen Recording permission:
/// mouse-press monitors are allowed, and window *bounds* are public in CGWindowList.
///
/// It stays out of the way of the event stream and the window server, which tablet drivers
/// (Wacom) share:
/// - it listens for presses only; the release is read from the button state while sampling;
/// - the monitor's handler only records where the press was and hands off to a background queue;
/// - a press in a window's content (drawing, selecting) is sampled 10 times a second, not 60,
///   and only speeds up once the window really moves or resizes;
/// - audio starts only for presses that look like a drag, or once the window moves.
final class WindowTracker: @unchecked Sendable {
    struct Status: Sendable {
        var mode: MotionMode
        var speed: Double
        var app: String
    }

    let control: ControlBlock
    var onPress: (@MainActor () -> Void)?
    var onRelease: (@MainActor () -> Void)?
    var onStatus: (@MainActor (Status) -> Void)?

    private var monitor: Any?   // main thread
    private let queue = DispatchQueue(label: "screech.tracker", qos: .userInteractive)

    // Confined to `queue`
    private var timer: DispatchSourceTimer?
    private var analyzer = MotionAnalyzer()
    private var windowID: CGWindowID = 0
    private var appName = ""
    private var lastStatus: Double = 0
    private var fast = false
    private var lastFrame = CGRect.null
    private var lastChange: Double = 0
    private var woke = false
    private var demoFrames: [(time: Double, frame: ScreechDSP.Rect)] = []
    private var demoIndex = 0
    private var demoStart: Double = 0

    /// While a window is moving. The window server redraws at 60 Hz on most displays.
    static let fastRate = 60.0
    /// While the press is not moving anything: just enough to notice it start.
    static let slowRate = 10.0
    /// Seconds without movement before sampling slows down again.
    static let settle = 1.0
    /// The scripted preview gesture.
    static let demoRate = 120.0
    /// Height of the title bar and toolbar band, and the width of the resize edges, in points.
    static let titleBand: CGFloat = 90
    static let edge: CGFloat = 8

    init(control: ControlBlock) {
        self.control = control
    }

    @MainActor func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            // Keep this tiny: note where the press was and leave.
            guard let self, let point = event.cgEvent?.location ?? CGEvent(source: nil)?.location else { return }
            self.queue.async { self.press(at: point) }
        }
    }

    @MainActor func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        queue.async { self.end(released: false) }
    }

    // MARK: Press (on `queue`)

    private static var buttonDown: Bool { CGEventSource.buttonState(.combinedSessionState, button: .left) }

    /// `point` is global, top-left origin, like window bounds.
    private func press(at point: CGPoint) {
        guard Self.buttonDown, let hit = Self.window(at: point) else { return }
        end(released: false)
        windowID = hit.id
        appName = hit.app
        let now = CACurrentMediaTime()
        let desktop = Self.desktop()
        analyzer.begin(frame: Self.rect(hit.frame), time: now, desktopMinX: desktop.minX, desktopWidth: desktop.width)
        control.sizeScale = Float(analyzer.sizeScale)
        lastFrame = hit.frame
        lastChange = now
        fast = Self.isGrip(point, in: hit.frame)
        woke = false
        if fast { wake() }
        startTimer(rate: fast ? Self.fastRate : Self.slowRate) { [weak self] in self?.sample() }
    }

    /// The title bar and toolbar band, or an edge: where windows are moved and resized.
    static func isGrip(_ p: CGPoint, in f: CGRect) -> Bool {
        p.y < f.minY + titleBand || p.y > f.maxY - edge || p.x < f.minX + edge || p.x > f.maxX - edge
    }

    private func wake() {
        guard !woke else { return }
        woke = true
        DispatchQueue.main.async { MainActor.assumeIsolated { self.onPress?() } }
    }

    /// Union of all displays, in the same coordinates as window bounds.
    private static func desktop() -> CGRect {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.prefix(Int(count)).reduce(CGRect.null) { $0.union(CGDisplayBounds($1)) }
    }

    // MARK: Sampling (on `queue`)

    private func sample() {
        guard Self.buttonDown else {
            end(released: true)
            return
        }
        guard let frame = Self.frame(of: windowID) else {
            end(released: false)  // window closed under us
            return
        }
        let now = CACurrentMediaTime()
        if frame != lastFrame {
            lastFrame = frame
            lastChange = now
            if !fast { setRate(fast: true) }
        } else if fast, now - lastChange > Self.settle {
            setRate(fast: false)
        }
        let out = analyzer.update(frame: Self.rect(frame), time: now)
        if out.mode != .idle { wake() }
        control.apply(out)
        publishStatus(out, now: now)
    }

    private func setRate(fast: Bool) {
        self.fast = fast
        let interval = 1 / (fast ? Self.fastRate : Self.slowRate)
        timer?.schedule(deadline: .now() + (fast ? 0 : interval), repeating: interval, leeway: .milliseconds(fast ? 1 : 20))
    }

    private func end(released: Bool) {
        guard timer != nil else { return }
        timer?.cancel()
        timer = nil
        demoFrames = []
        control.endGesture(analyzer, released: released)
        analyzer = MotionAnalyzer()
        let status = Status(mode: .idle, speed: 0, app: "")
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.onStatus?(status)
                self.onRelease?()
            }
        }
    }

    private func startTimer(rate: Double, _ handler: @escaping () -> Void) {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 1 / rate, leeway: .milliseconds(1))
        t.setEventHandler(handler: handler)
        timer = t
        t.resume()
    }

    private func publishStatus(_ out: MotionOutput, now: Double) {
        guard now - lastStatus > 1.0 / 15 else { return }
        lastStatus = now
        let status = Status(mode: out.mode, speed: out.speed, app: appName)
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.onStatus?(status) }
        }
    }

    // MARK: Demo

    /// Plays the scripted gesture through the same path as a real window.
    func playDemo(_ kind: DemoMotion.Kind) {
        queue.async {
            self.end(released: false)
            self.demoFrames = DemoMotion.frames(kind, rate: Self.demoRate)
            self.demoIndex = 0
            self.demoStart = CACurrentMediaTime()
            self.appName = "Preview"
            self.analyzer.begin(frame: DemoMotion.start, time: 0, desktopMinX: 0, desktopWidth: 2000)
            self.control.sizeScale = Float(self.analyzer.sizeScale)
            self.startTimer(rate: Self.demoRate) { self.demoStep() }  // cycle broken when the timer is cancelled
        }
    }

    private func demoStep() {
        let elapsed = CACurrentMediaTime() - demoStart
        while demoIndex < demoFrames.count, demoFrames[demoIndex].time <= elapsed {
            let (t, f) = demoFrames[demoIndex]
            let out = analyzer.update(frame: f, time: t)
            control.apply(out)
            publishStatus(out, now: CACurrentMediaTime())
            demoIndex += 1
        }
        if demoIndex >= demoFrames.count { end(released: true) }
    }

    // MARK: Window list

    private static func rect(_ r: CGRect) -> ScreechDSP.Rect {
        ScreechDSP.Rect(x: r.origin.x, y: r.origin.y, width: r.width, height: r.height)
    }

    /// Front-most normal window under `point` (global, top-left origin), excluding our own.
    static func window(at point: CGPoint) -> (id: CGWindowID, frame: CGRect, app: String)? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return nil }
        let me = ProcessInfo.processInfo.processIdentifier
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != me,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let frame = bounds(info),
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.01
            else { continue }
            // Resize handles sit a few points outside the frame.
            if frame.insetBy(dx: -6, dy: -6).contains(point) {
                return (id, frame, info[kCGWindowOwnerName as String] as? String ?? "")
            }
        }
        return nil
    }

    static func frame(of id: CGWindowID) -> CGRect? {
        // The cheapest window-server query for a single window.
        guard let list = CGWindowListCreateDescriptionFromArray([NSNumber(value: id)] as CFArray) as? [[String: Any]],
              let info = list.first else { return nil }
        return bounds(info)
    }

    private static func bounds(_ info: [String: Any]) -> CGRect? {
        guard let dict = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: dict)
    }
}
