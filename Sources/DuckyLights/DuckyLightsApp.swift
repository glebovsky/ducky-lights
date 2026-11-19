import AppKit
import DuckyKit
import SwiftUI

/// Read by the uncaught-exception handler, which can't capture context.
nonisolated(unsafe) private var deviceToReleaseOnCrash: DuckyDevice?

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// `DuckyLights --snapshot <dir>` renders previews to PNGs and quits, without touching the keyboard.
    static let snapshotDir: String? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()

    let model = AppModel(hardware: AppDelegate.snapshotDir == nil && AppDelegate.iconPath == nil
                         && AppDelegate.screenshotsDir == nil)
    private var signalSources: [DispatchSourceSignal] = []

    /// `DuckyLights --render-icon <file.png>` writes the 1024×1024 app icon (scripts/make-icon.sh).
    static let iconPath: String? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-icon"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()

    /// `DuckyLights --screenshots <dir>` renders the real window offscreen (README images).
    static let screenshotsDir: String? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--screenshots"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let dir = Self.screenshotsDir {
            Snapshots.windows(to: URL(fileURLWithPath: dir))
            exit(0)
        }
        if let path = Self.iconPath {
            Snapshots.renderIcon(to: URL(fileURLWithPath: path))
            exit(0)
        }
        if let dir = Self.snapshotDir {
            Snapshots.write(to: URL(fileURLWithPath: dir))
            exit(0)
        }
        installReleaseOnExit()
        if model.openWindowAtLaunch {
            // Needed when launched via `swift run` (no .app bundle): show in Dock and take focus.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // Menu bar only: the Window scene is suppressed (see `mainWindow`).
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Never leave the keyboard stuck in direct mode: hand control back to the firmware.
        model.device.shutdown()
    }

    /// The duck in the menu bar keeps the app alive with no window open.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Release on Ctrl-C / kill / uncaught exceptions too. (Hard crashes can't be caught;
    /// `swift run duckyctl release` fixes the board afterwards.)
    private func installReleaseOnExit() {
        let device = model.device
        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { device.shutdown(); exit(0) }
            src.resume()
            signalSources.append(src)
        }
        deviceToReleaseOnCrash = device
        NSSetUncaughtExceptionHandler { _ in deviceToReleaseOnCrash?.shutdown() }
    }
}

@main
struct DuckyLightsApp: App {
    static let mainWindowID = "main"
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    private var window: some Scene {
        Window("Ducky Lights", id: Self.mainWindowID) {
            ContentView()
                .environment(delegate.model)
                .frame(minWidth: 980, minHeight: 600)
                // Dock icon only while the window is open; the menu bar duck stays either way.
                .onAppear { NSApp.setActivationPolicy(.regular) }
                .onDisappear { NSApp.setActivationPolicy(.accessory) }
        }
        .defaultSize(width: 1100, height: 720)
        .windowResizability(.contentMinSize)
    }

    /// With "Open the window when the app starts" off, don't create the window at launch
    /// at all (closing it afterwards flashes it and its Dock icon). Needs macOS 15.
    private var mainWindow: some Scene {
        window.defaultLaunchBehavior(delegate.model.openWindowAtLaunch ? .presented : .suppressed)
    }

    var body: some Scene {
        mainWindow

        MenuBarExtra {
            MenuBarMenu().environment(delegate.model)
        } label: {
            Image(nsImage: DuckIcon.menuBar)
        }

        Settings {
            SettingsView().environment(delegate.model)
        }
    }
}

/// The app icon: a duck lit like the keyboard's Rainbow Wave, on a dark keycap-style tile.
/// Drawn on Apple's 1024 grid (824 pt tile, transparent margin for the shadow).
struct AppIconView: View {
    private var rainbow: some View {
        LinearGradient(colors: [RGB(255, 0, 200), RGB(255, 40, 40), RGB(255, 170, 0), RGB(255, 235, 0),
                                RGB(40, 255, 90), RGB(0, 210, 255), RGB(70, 90, 255)].map(\.color),
                       startPoint: UnitPoint(x: 0.05, y: 0.3), endPoint: UnitPoint(x: 0.95, y: 0.7))
    }

    private var duck: some View {
        Image(nsImage: DuckIcon.image(size: 600)).resizable().frame(width: 600, height: 600)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.21), Color(white: 0.07)], startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 4))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.45), radius: 24, y: 14)
            // Glow behind the duck, like LEDs bleeding onto the plate.
            rainbow.frame(width: 600, height: 600).mask(duck).blur(radius: 46).opacity(0.85)
            rainbow.frame(width: 600, height: 600).mask(duck)
        }
        .frame(width: 1024, height: 1024)
    }
}

/// Offscreen renders for checking the UI without Screen Recording permission.
@MainActor
enum Snapshots {
    /// Real window, real controls, drawn offscreen into PNGs. Works without Screen Recording
    /// permission because it draws our own view hierarchy, not the screen.
    static func windows(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSApp.setActivationPolicy(.accessory)
        let model = AppModel(hardware: false)
        model.pretendConnected()

        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 1100, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Ducky Lights"
        window.alphaValue = 0   // never visible; drawing into a bitmap ignores alpha
        window.contentView = NSHostingView(rootView: ContentView().environment(model))
        window.orderFrontRegardless()

        // Offscreen (not a SwiftUI Window scene) the split view ignores the sidebar's column
        // width; set the divider like the real window has it.
        func splitView(in v: NSView) -> NSSplitView? {
            if let s = v as? NSSplitView { return s }
            for sub in v.subviews { if let s = splitView(in: sub) { return s } }
            return nil
        }
        func shot(_ name: String) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            if let content = window.contentView, let split = splitView(in: content) {
                split.setPosition(210, ofDividerAt: 0)
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            // The frame view (contentView's superview) includes the title bar and traffic lights.
            guard let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { return }
            try? png.write(to: dir.appendingPathComponent(name))
            print(dir.appendingPathComponent(name).path)
        }

        model.settings.speed = 1
        model.settings.brightness = 1
        // Sample profiles so the sidebar shows what they look like.
        model.settings.primary = RGB(255, 140, 0)
        model.previewFrame(.staticColor, at: 0)
        model.saveNewProfile(named: "Focus")
        model.previewFrame(.breathing, at: 0)
        model.settings.primary = RGB(0, 170, 255)
        model.saveNewProfile(named: "Evening")

        model.selectEffect(.wave)
        model.previewFrame(.wave, at: 1.3)
        shot("app-wave.png")

        model.settings.background = RGB(0, 0, 25)
        model.settings.paint = [:]
        let layout = model.layout
        for k in layout.keys where ["W", "A", "S", "D"].contains(k.label) { model.settings.paint[k.ledIndex] = RGB(255, 0, 128) }
        for k in layout.row(of: layout.key(labeled: "F1")!) { model.settings.paint[k.ledIndex] = RGB(0, 170, 255) }
        for k in layout.keys where ["Up", "Down", "Left", "Right"].contains(k.label) { model.settings.paint[k.ledIndex] = RGB(255, 220, 0) }
        model.settings.paint[layout.key(labeled: "Esc")!.ledIndex] = RGB(255, 0, 0)
        model.brush = RGB(255, 0, 128)
        model.previewFrame(.custom, at: 0)
        model.saveNewProfile(named: "Gaming")
        shot("app-custom.png")
        model.settings.paint[layout.key(labeled: "Space")!.ledIndex] = RGB(0, 255, 120)
        model.previewFrame(.custom, at: 0)
        shot("app-profile-edited.png")

        model.selectEffect(.heatmap)

        // Heatmap from a made-up typing session: English text, spread over the last minute.
        model.previewFrame(.heatmap, at: 0)
        model.settings.background = RGB(0, 0, 0)
        let text = "the quick brown fox jumps over the lazy dog while we write some swift code for the keyboard. "
        var presses: [DuckyKit.KeyPress] = []
        for (i, ch) in String(repeating: text, count: 6).enumerated() {
            let label = ch == " " ? "Space" : ch == "." ? "." : String(ch).uppercased()
            if let k = layout.key(labeled: label) { presses.append(DuckyKit.KeyPress(ledIndex: k.ledIndex, time: Double(i) * 0.1)) }
        }
        for i in stride(from: 0, to: presses.count, by: 9) {
            presses.append(DuckyKit.KeyPress(ledIndex: layout.key(labeled: "Backspace")!.ledIndex, time: Double(i) * 0.1))
        }
        model.presses = presses
        model.previewFrame(.heatmap, at: Double(presses.count) * 0.1)
        shot("app-heatmap.png")

        window.close()
    }

    static func renderIcon(to url: URL) {
        let r = ImageRenderer(content: AppIconView())
        r.scale = 1
        guard let img = r.nsImage, let tiff = img.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            print("icon render failed"); exit(1)
        }
        try? png.write(to: url)
        print(url.path)
    }

    static func write(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = AppModel(hardware: false)

        func save(_ name: String, _ view: some View, scale: CGFloat = 2) {
            let r = ImageRenderer(content: view)
            r.scale = scale
            guard let img = r.nsImage, let tiff = img.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                print("failed: \(name)"); return
            }
            try? png.write(to: dir.appendingPathComponent(name))
            print(dir.appendingPathComponent(name).path)
        }
        func board() -> some View {
            KeyboardView().environment(model).frame(width: 1300, height: 480).padding(20).background(Color(white: 0.2))
        }

        // Layout sanity check: the window's content must fit its minimum size.
        func measure(_ name: String, _ v: some View) {
            let hc = NSHostingController(rootView: AnyView(v.environment(model)))
            for size in [CGSize(width: 729, height: 674), CGSize(width: 729, height: CGFloat.infinity),
                         CGSize(width: CGFloat.infinity, height: CGFloat.infinity), CGSize(width: 0, height: 674)] {
                print("\(name) in \(size): \(hc.sizeThatFits(in: size))")
            }
        }
        measure("status", StatusBar(showHardwareModes: .constant(false)))
        measure("keyboard", KeyboardView())
        measure("controls", ControlsPanel())
        measure("controls-fixed", ControlsPanel().fixedSize(horizontal: false, vertical: true))
        measure("content", ContentView())
        let hc = NSHostingController(rootView: AnyView(ContentView().environment(model)))
        print("content ideal (unbounded): \(hc.sizeThatFits(in: CGSize(width: CGFloat.infinity, height: .infinity)))")

        model.previewFrame(.wave, at: 1.3)
        do {
            func once(_ w: CGFloat) {
                let r = ImageRenderer(content: KeyboardView().environment(model).frame(width: w, height: w * 0.38))
                r.scale = 2
                _ = r.cgImage
            }
            once(760)
            let start = Date()
            for i in 0..<30 { model.previewFrame(.wave, at: Double(i) / 60); once(700 + CGFloat(i) * 3) }
            print(String(format: "keyboard draw: %.1f ms/frame", Date().timeIntervalSince(start) / 30 * 1000))
        }
        save("board-wave-ansi.png", board())

        model.layoutVariant = .iso
        model.settings.background = RGB(0, 0, 40)
        for k in model.layout.row(of: model.layout.key(labeled: "Q")!) { model.settings.paint[k.ledIndex] = RGB(255, 0, 128) }
        for k in model.layout.column(of: model.layout.key(labeled: "Enter")!) { model.settings.paint[k.ledIndex] = RGB(0, 255, 120) }
        model.previewFrame(.custom, at: 0)
        save("board-paint-iso.png", board())

        model.previewFrame(.off, at: 0)
        save("board-off.png", board())

        save("duck.png", Image(nsImage: DuckIcon.image(size: 128, template: false)).padding(8).background(.white), scale: 1)
        save("duck-menubar.png", Image(nsImage: DuckIcon.image(size: 18, template: false)).padding(3).background(.white), scale: 4)
    }
}
