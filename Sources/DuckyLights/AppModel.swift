import AppKit
import DuckyKit
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    enum Status: Equatable {
        case disconnected(String)
        case connected(String)
        case released
    }

    var layout = KeyLayout.one2TKL(.ansi)
    var effect: EffectKind = .wave { didSet { restartClock(); needsSend = true; persist() } }
    var settings = EffectSettings() { didSet { needsSend = true; persist() } }
    /// Color used by the paint brush in Custom mode.
    var brush: RGB = RGB(255, 0, 128)
    /// Last rendered frame, drawn by KeyboardView (works even with no keyboard attached).
    private(set) var preview: [Int: RGB] = [:]
    private(set) var status: Status = .disconnected("Not connected")
    private(set) var fps: Double = 0
    var presses: [DuckyKit.KeyPress] = []

    @ObservationIgnored let device = DuckyDevice()
    @ObservationIgnored private let hidQueue = DispatchQueue(label: "ducky.frames", qos: .userInteractive)
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var start = Date()
    @ObservationIgnored private var needsSend = true
    @ObservationIgnored private var sending = false
    @ObservationIgnored private var frameCount = 0
    @ObservationIgnored private var fpsWindowStart = Date()
    /// True while we released control because the Mac went to sleep; resume on wake.
    @ObservationIgnored private var releasedForSleep = false

    static let palette: [RGB] = [
        RGB(255, 0, 0), RGB(255, 128, 0), RGB(255, 220, 0), RGB(0, 255, 0),
        RGB(0, 255, 200), RGB(0, 170, 255), RGB(0, 0, 255), RGB(140, 0, 255),
        RGB(255, 0, 200), RGB(255, 255, 255), RGB(0, 0, 0),
    ]

    init() {
        restore()
        connect()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        observeSleep()
    }

    func connect() {
        do {
            try device.connect()
            status = .connected(device.selected.map { DuckyProtocol.knownProducts[$0.productID] ?? $0.product } ?? "Ducky")
            needsSend = true
        } catch {
            status = .disconnected("\(error)")
        }
    }

    /// Give lighting back to the keyboard firmware (Fn shortcuts work again).
    func releaseToHardware() {
        hidQueue.async { [device] in device.release() }
        status = .released
    }

    func resumeControl() { connect() }

    func paint(_ key: KeyInfo) {
        settings.paint[key.ledIndex] = brush
        if effect != .custom { effect = .custom }
    }

    func fillAll(_ c: RGB) {
        for k in layout.keys { settings.paint[k.ledIndex] = c }
    }

    func clearPaint() { settings.paint = [:] }

    // MARK: - Frame loop

    private func restartClock() { start = Date() }

    private func tick() {
        let t = Date().timeIntervalSince(start)
        presses.removeAll { t - $0.time > 3 }
        let frame = EffectRenderer.render(effect, layout: layout, settings: settings, t: t, presses: presses)
        preview = frame

        guard case .connected = status else { return }
        guard effect.isAnimated || needsSend, !sending else { return }
        needsSend = false
        sending = true
        hidQueue.async { [device, weak self] in
            let ok = (try? device.show(frame)) != nil
            Task { @MainActor in
                guard let self else { return }
                self.sending = false
                if !ok { self.status = .disconnected("Write failed — keyboard unplugged?") }
                self.countFrame()
            }
        }
    }

    private func countFrame() {
        frameCount += 1
        let dt = Date().timeIntervalSince(fpsWindowStart)
        if dt >= 1 { fps = Double(frameCount) / dt; frameCount = 0; fpsWindowStart = Date() }
    }

    // MARK: - Sleep / wake

    private func observeSleep() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, case .connected = self.status else { return }
                self.releasedForSleep = true
                self.releaseToHardware()
            }
        }
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.releasedForSleep else { return }
                self.releasedForSleep = false
                self.connect()
            }
        }
    }

    // MARK: - Persistence (UserDefaults, last state only — profiles are a roadmap item)

    private struct Saved: Codable { var effect: EffectKind; var settings: EffectSettings }

    private func persist() {
        if let data = try? JSONEncoder().encode(Saved(effect: effect, settings: settings)) {
            UserDefaults.standard.set(data, forKey: "state")
        }
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: "state"),
              let s = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        effect = s.effect
        settings = s.settings
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
