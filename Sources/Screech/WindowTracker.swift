import AppKit
import ScreechDSP

/// Watches mouse presses system-wide and samples the frame of the window under the cursor
/// while the button is held. Needs no Accessibility or Screen Recording permission:
/// mouse-button monitors are allowed, and window *bounds* are public in CGWindowList.
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

    private var monitors: [Any] = []
    private let queue = DispatchQueue(label: "screech.tracker", qos: .userInteractive)

    // Confined to `queue`
    private var timer: DispatchSourceTimer?
    private var analyzer = MotionAnalyzer()
    private var windowID: CGWindowID = 0
    private var appName = ""
    private var lastStatus: Double = 0
    private var demoFrames: [(time: Double, frame: ScreechDSP.Rect)] = []
    private var demoIndex = 0
    private var demoStart: Double = 0

    static let sampleRate = 120.0

    init(control: ControlBlock) {
        self.control = control
    }

    @MainActor func start() {
        guard monitors.isEmpty else { return }
        let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated {
                if event.type == .leftMouseDown { self?.mouseDown() } else { self?.mouseUp() }
            }
        }
        if let monitor { monitors.append(monitor) }
    }

    @MainActor func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        queue.async { self.end(released: false) }
    }

    // MARK: Mouse

    @MainActor private func mouseDown() {
        guard let primary = NSScreen.screens.first else { return }
        let p = NSEvent.mouseLocation
        // CGWindowList uses a top-left origin on the primary display.
        let point = CGPoint(x: p.x, y: primary.frame.maxY - p.y)
        guard let hit = Self.window(at: point) else { return }
        let desktop = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        onPress?()
        queue.async { self.begin(hit.id, frame: hit.frame, app: hit.app, desktop: desktop) }
    }

    @MainActor private func mouseUp() {
        queue.async { self.end(released: true) }
    }

    // MARK: Sampling (on `queue`)

    private func begin(_ id: CGWindowID, frame: CGRect, app: String, desktop: CGRect) {
        end(released: false)
        windowID = id
        appName = app
        analyzer.begin(frame: Self.rect(frame), time: CACurrentMediaTime(),
                       desktopMinX: desktop.minX, desktopWidth: desktop.width)
        control.sizeScale = Float(analyzer.sizeScale)
        startTimer { [weak self] in self?.sample() }
    }

    private func sample() {
        // Safety net in case the mouse-up event was missed.
        guard CGEventSource.buttonState(.combinedSessionState, button: .left) else {
            end(released: true)
            return
        }
        guard let frame = Self.frame(of: windowID) else {
            end(released: false)  // window closed under us
            return
        }
        let now = CACurrentMediaTime()
        let out = analyzer.update(frame: Self.rect(frame), time: now)
        control.apply(out)
        publishStatus(out, now: now)
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

    private func startTimer(_ handler: @escaping () -> Void) {
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        t.schedule(deadline: .now(), repeating: 1 / Self.sampleRate, leeway: .microseconds(500))
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
            self.demoFrames = DemoMotion.frames(kind, rate: Self.sampleRate)
            self.demoIndex = 0
            self.demoStart = CACurrentMediaTime()
            self.appName = "Preview"
            self.analyzer.begin(frame: DemoMotion.start, time: 0, desktopMinX: 0, desktopWidth: 2000)
            self.control.sizeScale = Float(self.analyzer.sizeScale)
            self.startTimer { self.demoStep() }  // cycle broken when the timer is cancelled
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
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
              let info = list.first else { return nil }
        return bounds(info)
    }

    private static func bounds(_ info: [String: Any]) -> CGRect? {
        guard let dict = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: dict)
    }
}
