import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched via `swift run` (no .app bundle): show in Dock and take focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Never leave the keyboard stuck in direct mode: hand control back to the firmware.
        model?.device.release()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct DuckyLightsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Ducky Lights") {
            ContentView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 560)
                .onAppear { delegate.model = model }
        }
        .windowResizability(.contentMinSize)
    }
}
