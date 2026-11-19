import AppKit
import DuckyKit
import Observation
import SwiftUI

enum PaintTool: String, CaseIterable, Identifiable, Codable {
    case brush = "Brush"
    case eraser = "Eraser"
    case eyedropper = "Eyedropper"
    case fillRow = "Fill row"
    case fillColumn = "Fill column"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .brush: return "paintbrush.pointed"
        case .eraser: return "eraser"
        case .eyedropper: return "eyedropper"
        case .fillRow: return "arrow.left.and.right"
        case .fillColumn: return "arrow.up.and.down"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    enum Status: Equatable {
        case disconnected(String)
        case connected(String)
        case released(String)
    }

    /// Why the app is currently not driving the keyboard. Control resumes when none are left.
    enum Hold: Hashable {
        case user, sleep, lock, background

        var reason: String {
            switch self {
            case .user: return "Keyboard firmware in control"
            case .sleep: return "Released while the Mac sleeps"
            case .lock: return "Released while the screen is locked"
            case .background: return "Released while the app is in the background"
            }
        }
    }

    var layoutVariant: LayoutVariant = .ansi {
        didSet { layout = KeyLayout.one2TKL(layoutVariant); needsSend = true; persist() }
    }
    private(set) var layout = KeyLayout.one2TKL(.ansi)
    var effect: EffectKind = .wave { didSet { restartClock(); needsSend = true; persist() } }
    var settings = EffectSettings() { didSet { needsSend = true; persist() } }
    var releaseWhenLocked = true {
        didSet { if !restoring && !releaseWhenLocked { setHold(.lock, false) }; persist() }
    }
    var releaseInBackground = false {
        didSet {
            if !restoring { setHold(.background, releaseInBackground && !NSApplication.shared.isActive) }
            persist()
        }
    }

    /// Color used by the brush in Custom mode.
    var brush: RGB = RGB(255, 0, 128)
    var tool: PaintTool = .brush
    /// Last rendered frame, drawn by KeyboardView (works even with no keyboard attached).
    private(set) var preview: [Int: RGB] = [:]
    private(set) var status: Status = .disconnected("Looking for the keyboard…")
    private(set) var fps: Double = 0
    var presses: [DuckyKit.KeyPress] = []

    @ObservationIgnored let device = DuckyDevice()
    @ObservationIgnored private let hardware: Bool
    @ObservationIgnored private let hidQueue = DispatchQueue(label: "ducky.frames", qos: .userInteractive)
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var start = Date()
    @ObservationIgnored private var needsSend = true
    @ObservationIgnored private var sending = false
    @ObservationIgnored private var frameCount = 0
    @ObservationIgnored private var fpsWindowStart = Date()
    @ObservationIgnored private var holds: Set<Hold> = []
    @ObservationIgnored private var restoring = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    static let palette: [RGB] = [
        RGB(255, 0, 0), RGB(255, 128, 0), RGB(255, 220, 0), RGB(0, 255, 0),
        RGB(0, 255, 200), RGB(0, 170, 255), RGB(0, 0, 255), RGB(140, 0, 255),
        RGB(255, 0, 200), RGB(255, 255, 255), RGB(0, 0, 0),
    ]

    /// `hardware: false` renders previews only and never touches the keyboard (snapshots).
    init(hardware: Bool = true) {
        self.hardware = hardware
        restore()
        tick()
        guard hardware else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        device.watchHotPlug { [weak self] event in
            MainActor.assumeIsolated { self?.hotPlug(event) }
        }
        observeSystem()
    }

    // MARK: - Control

    var isConnected: Bool { if case .connected = status { return true } else { return false } }
    var isReleased: Bool { if case .released = status { return true } else { return false } }

    func connect() {
        guard hardware else { return }
        if let hold = holds.first { status = .released(hold.reason); return }
        do {
            try device.beginDirectMode()
            status = .connected(device.selected.map { DuckyProtocol.knownProducts[$0.productID] ?? $0.product } ?? "Ducky")
            needsSend = true
        } catch {
            status = .disconnected("\(error)")
        }
    }

    /// Give lighting back to the keyboard firmware (Fn shortcuts work again).
    func releaseToHardware() { setHold(.user, true) }

    func resumeControl() { setHold(.user, false) }

    private func setHold(_ hold: Hold, _ on: Bool) {
        guard hardware else { return }
        let wasHeld = !holds.isEmpty
        if on { holds.insert(hold) } else { holds.remove(hold) }
        if holds.isEmpty {
            if wasHeld { connect() }
        } else if !wasHeld {
            // Synchronous so it lands before the Mac sleeps. Frames queued behind it are
            // dropped by DuckyDevice because it is no longer in direct mode.
            device.release()
            status = .released(hold.reason)
        } else if case .released = status {
            status = .released(holds.contains(.user) ? Hold.user.reason : (holds.first?.reason ?? ""))
        }
    }

    private func hotPlug(_ event: DuckyDevice.ConnectionEvent) {
        switch event {
        case .appeared:
            if holds.isEmpty && !isConnected { connect() }
        case .disappeared:
            if isConnected { status = .disconnected("Keyboard unplugged. Plug it back in to continue.") }
        }
    }

    // MARK: - Painting

    /// Painting only works in the Custom effect; other effects ignore clicks on the board.
    var canPaint: Bool { effect == .custom }

    /// Apply the current tool to `key`. `dragging` is true for keys reached by dragging,
    /// where only brush and eraser keep working.
    func apply(to key: KeyInfo, dragging: Bool) {
        guard canPaint else { return }
        switch tool {
        case .brush:
            editPaint { $0[key.ledIndex] = brush }
        case .eraser:
            editPaint { $0[key.ledIndex] = nil }
        case .eyedropper:
            guard !dragging else { return }
            brush = preview[key.ledIndex] ?? .black
            tool = .brush
        case .fillRow:
            guard !dragging else { return }
            let keys = layout.row(of: key)
            editPaint { p in for k in keys { p[k.ledIndex] = brush } }
        case .fillColumn:
            guard !dragging else { return }
            let keys = layout.column(of: key)
            editPaint { p in for k in keys { p[k.ledIndex] = brush } }
        }
    }

    private func editPaint(_ change: (inout [Int: RGB]) -> Void) {
        guard canPaint else { return }
        change(&settings.paint)
    }

    /// Keys the current tool would change if `key` were clicked (for hover highlighting).
    func targets(for key: KeyInfo) -> Set<Int> {
        switch tool {
        case .fillRow: return Set(layout.row(of: key).map(\.ledIndex))
        case .fillColumn: return Set(layout.column(of: key).map(\.ledIndex))
        default: return [key.ledIndex]
        }
    }

    func rgbBinding(_ path: ReferenceWritableKeyPath<AppModel, RGB>) -> Binding<Color> {
        Binding(get: { self[keyPath: path].color }, set: { self[keyPath: path] = RGB($0) })
    }

    func fillAll(_ c: RGB) {
        let keys = layout.keys
        editPaint { p in for k in keys { p[k.ledIndex] = c } }
    }

    func clearPaint() { editPaint { $0 = [:] } }

    // MARK: - Frame loop

    private func restartClock() { start = Date() }

    private func tick() {
        let t = Date().timeIntervalSince(start)
        presses.removeAll { t - $0.time > 3 }
        let frame = EffectRenderer.render(effect, layout: layout, settings: settings, t: t, presses: presses)
        preview = frame

        guard isConnected, effect.isAnimated || needsSend, !sending else { return }
        needsSend = false
        sending = true
        hidQueue.async { [device, weak self] in
            let ok = (try? device.show(frame)) != nil
            Task { @MainActor in
                guard let self else { return }
                self.sending = false
                if !ok, self.isConnected {
                    self.status = .disconnected("Lost the keyboard. Plug it back in to continue.")
                }
                self.countFrame()
            }
        }
    }

    private func countFrame() {
        frameCount += 1
        let dt = Date().timeIntervalSince(fpsWindowStart)
        if dt >= 1 { fps = Double(frameCount) / dt; frameCount = 0; fpsWindowStart = Date() }
    }

    // MARK: - Sleep, lock, background

    private func observeSystem() {
        let ws = NSWorkspace.shared.notificationCenter
        let dnc = DistributedNotificationCenter.default()
        let nc = NotificationCenter.default
        func on(_ center: NotificationCenter, _ name: Notification.Name, _ body: @escaping @MainActor (AppModel) -> Void) {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self { body(self) } }
            })
        }
        on(ws, NSWorkspace.willSleepNotification) { $0.setHold(.sleep, true) }
        on(ws, NSWorkspace.didWakeNotification) { $0.setHold(.sleep, false) }
        on(dnc, Notification.Name("com.apple.screenIsLocked")) { if $0.releaseWhenLocked { $0.setHold(.lock, true) } }
        on(dnc, Notification.Name("com.apple.screenIsUnlocked")) { $0.setHold(.lock, false) }
        on(nc, NSApplication.didResignActiveNotification) { if $0.releaseInBackground { $0.setHold(.background, true) } }
        on(nc, NSApplication.didBecomeActiveNotification) { $0.setHold(.background, false) }
    }

    // MARK: - Persistence (UserDefaults, last state only; named profiles are M4)

    private struct Saved: Codable {
        var effect: EffectKind
        var settings: EffectSettings
        var layoutVariant: LayoutVariant?
        var releaseWhenLocked: Bool?
        var releaseInBackground: Bool?
    }

    private func persist() {
        guard hardware, !restoring else { return }
        let saved = Saved(effect: effect, settings: settings, layoutVariant: layoutVariant,
                          releaseWhenLocked: releaseWhenLocked, releaseInBackground: releaseInBackground)
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: "state")
        }
    }

    private func restore() {
        guard hardware, let data = UserDefaults.standard.data(forKey: "state"),
              let s = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        restoring = true
        defer { restoring = false }
        effect = s.effect
        settings = s.settings
        layoutVariant = s.layoutVariant ?? .ansi
        releaseWhenLocked = s.releaseWhenLocked ?? true
        releaseInBackground = s.releaseInBackground ?? false
    }

    /// For snapshots: show a given effect at a given time without touching hardware.
    func previewFrame(_ kind: EffectKind, at t: Double) {
        effect = kind
        preview = EffectRenderer.render(kind, layout: layout, settings: settings, t: t, presses: presses)
    }
}

extension RGB {
    var color: Color { Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(UInt8(clamping: Int(ns.redComponent * 255)),
                  UInt8(clamping: Int(ns.greenComponent * 255)),
                  UInt8(clamping: Int(ns.blueComponent * 255)))
    }
}
