import AppKit
import DuckyKit
import Observation
import os
import ServiceManagement
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
    var effect: EffectKind = .wave {
        didSet {
            // Re-selecting the current effect must not wipe the heatmap or restart animations.
            guard effect != oldValue else { return }
            restartClock()
            presses = []   // their times are on the old effect's clock
            needsSend = true
            persist()
            updateKeyListening()
        }
    }
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

    /// Show the main window when the app starts. Off = start quietly in the menu bar
    /// (nice with launch at login).
    var openWindowAtLaunch = true { didSet { persist() } }

    /// Launch at login only works from the installed .app (SMAppService needs a bundle).
    let isBundled = Bundle.main.bundleIdentifier != nil
    private(set) var loginItemStatus: SMAppService.Status = .notRegistered
    private(set) var loginItemError: String?
    var launchAtLogin: Bool { loginItemStatus == .enabled }

    func setLaunchAtLogin(_ on: Bool) {
        guard isBundled else { return }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        refreshLoginItem()
    }

    func refreshLoginItem() {
        guard isBundled else { return }
        loginItemStatus = SMAppService.mainApp.status
    }

    // MARK: Profiles state

    private(set) var profileStore: ProfileStore
    /// The profile last applied. Stays set while you tweak it (then it shows as edited);
    /// cleared when you pick a plain effect.
    private(set) var activeProfileID: UUID? { didSet { persist() } }
    /// Shown as an alert: failed saves, unreadable files, import results.
    var profileMessage: String?

    /// Color used by the brush in Custom mode.
    var brush: RGB = RGB(255, 0, 128)
    var tool: PaintTool = .brush
    /// Last rendered frame, drawn by KeyboardView (works even with no keyboard attached).
    private(set) var preview: [Int: RGB] = [:]
    private(set) var status: Status = .disconnected("Looking for the keyboard…")
    private(set) var fps: Double = 0
    var presses: [DuckyKit.KeyPress] = []
    /// Input Monitoring status, for the key-reactive effects.
    private(set) var keyAccess: KeyEventSource.Access = KeyEventSource.access
    private(set) var isListeningToKeys = false
    @ObservationIgnored private let keySource = KeyEventSource()
    /// History kept for the heatmap (Reactive and Ripple only look at the last seconds).
    static let pressHistory: (seconds: Double, count: Int) = (20 * 60, 20_000)

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
        profileStore = ProfileStore(url: hardware ? ProfileStore.defaultURL : nil)
        loadProfiles()
        restore()
        tick()
        guard hardware else { return }
        refreshLoginItem()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        device.watchHotPlug { [weak self] event in
            MainActor.assumeIsolated { self?.hotPlug(event) }
        }
        observeSystem()
        updateKeyListening()
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

    // MARK: - Profiles

    var profiles: [Profile] { profileStore.profiles }
    var activeProfile: Profile? { activeProfileID.flatMap { profileStore.profile($0) } }
    var activeProfileEdited: Bool { activeProfile?.differs(effect: effect, settings: settings) ?? false }

    func selectEffect(_ kind: EffectKind) {
        activeProfileID = nil
        effect = kind
    }

    func applyProfile(_ id: UUID) {
        guard let p = profileStore.profile(id) else { return }
        effect = p.effect
        settings = p.settings
        activeProfileID = id
    }

    /// Save what's on the keyboard now as a new profile, and make it the active one.
    func saveNewProfile(named name: String) {
        let p = profileStore.add(name: name, effect: effect, settings: settings)
        activeProfileID = p.id
        saveProfiles()
    }

    func updateActiveProfile() {
        guard let id = activeProfileID else { return }
        profileStore.update(id, effect: effect, settings: settings)
        saveProfiles()
    }

    func revertActiveProfile() {
        if let id = activeProfileID { applyProfile(id) }
    }

    func renameProfile(_ id: UUID, to name: String) {
        profileStore.rename(id, to: name)
        saveProfiles()
    }

    func deleteProfile(_ id: UUID) {
        profileStore.delete(id)
        if activeProfileID == id { activeProfileID = nil }
        saveProfiles()
    }

    func moveProfiles(fromOffsets source: IndexSet, toOffset destination: Int) {
        profileStore.move(fromOffsets: source, toOffset: destination)
        saveProfiles()
    }

    func uniqueProfileName(_ base: String) -> String { profileStore.uniqueName(base) }

    func exportData(_ ids: [UUID]) -> Data {
        ProfileFile.encode(ids.compactMap { profileStore.profile($0) })
    }

    func importProfiles(from urls: [URL]) {
        var added: [Profile] = []
        var problems: [String] = []
        for url in urls {
            do {
                let d = try ProfileFile.decode(Data(contentsOf: url))
                added += profileStore.importProfiles(d.profiles)
                problems += d.skipped.map { "\(url.lastPathComponent): skipped \($0)" }
            } catch {
                problems.append("\(url.lastPathComponent): \(error)")
            }
        }
        if !added.isEmpty { saveProfiles() }
        var msg = added.isEmpty ? "No profiles imported." :
            "Imported \(added.count) profile\(added.count == 1 ? "" : "s"): \(added.map(\.name).joined(separator: ", "))."
        if !problems.isEmpty { msg += "\n\n" + problems.joined(separator: "\n") }
        profileMessage = msg
    }

    private func saveProfiles() {
        do { try profileStore.save() } catch { profileMessage = "Couldn't save profiles: \(error.localizedDescription)" }
    }

    /// A broken profiles.json is moved aside (never overwritten) and the app starts empty.
    private func loadProfiles() {
        do {
            try profileStore.load()
        } catch {
            guard let url = profileStore.url else { return }
            let aside = url.deletingLastPathComponent()
                .appendingPathComponent("profiles.unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            profileMessage = "Couldn't read your profiles (\(error)). The file was kept as \(aside.lastPathComponent)."
        }
    }

    // MARK: - Key presses

    /// `log show --last 10m --predicate 'subsystem == "com.glebovsky.DuckyLights"'`
    @ObservationIgnored private let keyLog = Logger(subsystem: "com.glebovsky.DuckyLights", category: "keys")

    /// Listen to the Ducky's keys only while an effect needs them, and only with permission.
    func updateKeyListening() {
        guard hardware else { return }
        keyAccess = KeyEventSource.access
        keyLog.notice("update: effect=\(self.effect.rawValue, privacy: .public) needsKeys=\(self.effect.needsKeyEvents) access=\(String(describing: self.keyAccess), privacy: .public) running=\(self.keySource.isRunning)")
        if effect.needsKeyEvents && keyAccess == .granted {
            guard !keySource.isRunning else { isListeningToKeys = true; return }
            do {
                try keySource.start { [weak self] led in
                    MainActor.assumeIsolated { self?.keyDown(led) }
                }
                keyLog.notice("key listener started")
            } catch {
                keyLog.error("key listener failed: \(String(describing: error), privacy: .public)")
                keyAccess = .denied
            }
        } else {
            keySource.stop()
        }
        isListeningToKeys = keySource.isRunning
    }

    /// Ask for Input Monitoring: the system prompt the first time, the Settings pane after a "no".
    func requestKeyAccess() {
        keyLog.notice("request: access before=\(String(describing: KeyEventSource.access), privacy: .public)")
        if KeyEventSource.access == .denied {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
        } else {
            let ok = KeyEventSource.requestAccess()
            keyLog.notice("IOHIDRequestAccess returned \(ok)")
        }
        updateKeyListening()
    }

    func clearPresses() { presses = [] }

    private func keyDown(_ led: Int) {
        if presses.isEmpty { keyLog.notice("first key press: led \(led)") }
        presses.append(KeyPress(ledIndex: led, time: Date().timeIntervalSince(start)))
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
        if let first = presses.first, t - first.time > Self.pressHistory.seconds {
            presses.removeAll { t - $0.time > Self.pressHistory.seconds }
        }
        if presses.count > Self.pressHistory.count { presses.removeFirst(presses.count - Self.pressHistory.count) }
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
        on(nc, NSApplication.didBecomeActiveNotification) {
            $0.setHold(.background, false)
            $0.updateKeyListening()   // the user may have just granted Input Monitoring
        }
    }

    // MARK: - Persistence (UserDefaults, last state only; named profiles are M4)

    private struct Saved: Codable {
        var effect: EffectKind
        var settings: EffectSettings
        var layoutVariant: LayoutVariant?
        var releaseWhenLocked: Bool?
        var releaseInBackground: Bool?
        var openWindowAtLaunch: Bool?
        var activeProfileID: UUID?
    }

    private func persist() {
        guard hardware, !restoring else { return }
        let saved = Saved(effect: effect, settings: settings, layoutVariant: layoutVariant,
                          releaseWhenLocked: releaseWhenLocked, releaseInBackground: releaseInBackground,
                          openWindowAtLaunch: openWindowAtLaunch, activeProfileID: activeProfileID)
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: "state")
        }
    }

    private func restore() {
        // `swift run` builds have no bundle ID, so they saved under the process name.
        // The installed app picks that up on its first launch.
        let data = UserDefaults.standard.data(forKey: "state")
            ?? UserDefaults(suiteName: "DuckyLights")?.data(forKey: "state")
        guard hardware, let data,
              let s = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        restoring = true
        defer { restoring = false }
        effect = s.effect
        settings = s.settings
        layoutVariant = s.layoutVariant ?? .ansi
        releaseWhenLocked = s.releaseWhenLocked ?? true
        releaseInBackground = s.releaseInBackground ?? false
        openWindowAtLaunch = s.openWindowAtLaunch ?? true
        activeProfileID = s.activeProfileID.flatMap { profileStore.profile($0) != nil ? $0 : nil }
    }

    /// For README screenshots: look connected without touching hardware.
    func pretendConnected(fps: Double = 60) {
        guard !hardware else { return }
        status = .connected("Ducky One 2 RGB TKL")
        self.fps = fps
        keyAccess = .granted
        isListeningToKeys = true
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
