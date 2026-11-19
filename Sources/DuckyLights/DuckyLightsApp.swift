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

    let model = AppModel(hardware: AppDelegate.snapshotDir == nil)
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let dir = Self.snapshotDir {
            Snapshots.write(to: URL(fileURLWithPath: dir))
            exit(0)
        }
        // Needed when launched via `swift run` (no .app bundle): show in Dock and take focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        installReleaseOnExit()
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

    var body: some Scene {
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

/// Offscreen renders for checking the UI without Screen Recording permission.
@MainActor
enum Snapshots {
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
                         CGSize(width: CGFloat.infinity, height: CGFloat.infinity)] {
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
