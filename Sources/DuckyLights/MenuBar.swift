import AppKit
import DuckyKit
import SwiftUI

/// A small rubber-duck silhouette, drawn in code so there's no asset to ship.
/// Template image: macOS tints it for light/dark menu bars.
enum DuckIcon {
    static let menuBar: NSImage = image(size: 18)

    static func image(size: CGFloat, template: Bool = true) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let k = rect.width / 18   // design grid is 18×18, origin bottom-left
            func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * k, y: y * k) }
            NSColor.black.setFill()

            // Body: a wide, flat-bottomed oval with the tail swept up at the back.
            let body = NSBezierPath()
            body.move(to: pt(3.2, 6.6))
            body.curve(to: pt(9.5, 1.6), controlPoint1: pt(3.0, 3.2), controlPoint2: pt(6.0, 1.6))
            body.curve(to: pt(16.4, 6.2), controlPoint1: pt(13.4, 1.6), controlPoint2: pt(16.0, 3.0))
            body.line(to: pt(17.4, 10.6))   // tail tip
            body.curve(to: pt(12.6, 8.4), controlPoint1: pt(15.6, 9.6), controlPoint2: pt(14.0, 8.6))
            body.curve(to: pt(8.4, 8.6), controlPoint1: pt(11.2, 8.2), controlPoint2: pt(9.6, 8.2))
            body.close()
            body.fill()

            // Head and neck.
            NSBezierPath(ovalIn: NSRect(x: 3.0 * k, y: 7.4 * k, width: 7.6 * k, height: 7.6 * k)).fill()

            // Beak, pointing left.
            let beak = NSBezierPath()
            beak.move(to: pt(3.8, 12.4))
            beak.curve(to: pt(0.4, 10.6), controlPoint1: pt(2.2, 12.4), controlPoint2: pt(0.6, 11.6))
            beak.curve(to: pt(4.2, 9.6), controlPoint1: pt(1.4, 9.6), controlPoint2: pt(3.0, 9.4))
            beak.close()
            beak.fill()

            // Cut-outs: eye, and a wing line on the body.
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: NSRect(x: 5.2 * k, y: 11.4 * k, width: 1.5 * k, height: 1.5 * k)).fill()
            let wing = NSBezierPath()
            wing.move(to: pt(8.6, 5.8))
            wing.curve(to: pt(13.8, 5.4), controlPoint1: pt(10.2, 3.6), controlPoint2: pt(12.6, 3.6))
            wing.lineWidth = 1.1 * k
            wing.lineCapStyle = .round
            wing.stroke()
            return true
        }
        img.isTemplate = template
        return img
    }
}

/// The menu under the duck: open the window, switch effects, hand control back, quit.
struct MenuBarMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        Text(statusLine)
        Button("Open Ducky Lights") {
            openWindow(id: DuckyLightsApp.mainWindowID)
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("o")
        Divider()
        Picker("Effect", selection: Binding(get: { model.activeProfileID == nil ? model.effect : nil },
                                            set: { if let k = $0 { model.selectEffect(k) } })) {
            ForEach(EffectKind.allCases) { Text($0.rawValue).tag(Optional($0)) }
        }
        .pickerStyle(.inline)
        if !model.profiles.isEmpty {
            Divider()
            Picker("Profiles", selection: Binding(get: { model.activeProfileID },
                                                  set: { if let id = $0 { model.applyProfile(id) } })) {
                ForEach(model.profiles) { Text($0.name).tag(Optional($0.id)) }
            }
            .pickerStyle(.inline)
        }
        Divider()
        if model.isReleased {
            Button("Take control") { model.resumeControl() }
        } else {
            Button("Release to keyboard") { model.releaseToHardware() }
                .disabled(!model.isConnected)
        }
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Ducky Lights") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusLine: String {
        switch model.status {
        case .connected(let name): return "● \(name)"
        case .released(let why): return why
        case .disconnected(let why): return why
        }
    }
}
