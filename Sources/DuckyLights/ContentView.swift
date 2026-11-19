import DuckyKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showHardwareModes = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(EffectKind.allCases, selection: Binding<EffectKind?>(
                get: { model.effect }, set: { if let k = $0 { model.effect = k } })) { kind in
                Label(kind.rawValue, systemImage: icon(kind)).tag(kind)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            VStack(alignment: .leading, spacing: 16) {
                StatusBar(showHardwareModes: $showHardwareModes)
                KeyboardView()
                    // Finite ideal size: an aspect-fit view offered infinite width reports
                    // infinite size, and the window then lays out taller than itself.
                    .frame(maxWidth: 1600)
                ControlsPanel()
                // Nothing vertically greedy in this column (Spacer, a bare vertical Divider):
                // it made the content lay out taller than the window, hiding the top under
                // the title bar.
            }
            .padding(20)
            .background(GeometryReader { g in
                Color.clear.onAppear { LayoutDebug.log("detail", g) }
                    .onChange(of: g.frame(in: .global)) { LayoutDebug.log("detail", g) }
            })
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .sheet(isPresented: $showHardwareModes) { HardwareModesView() }
        .background(GeometryReader { g in
            Color.clear.onAppear { LayoutDebug.log("root", g) }.onChange(of: g.size) { LayoutDebug.log("root", g) }
        })
    }

    private func icon(_ k: EffectKind) -> String {
        switch k {
        case .staticColor: return "square.fill"
        case .custom: return "paintbrush.pointed"
        case .breathing: return "lungs"
        case .colorCycle: return "arrow.triangle.2.circlepath"
        case .wave: return "water.waves"
        case .radar: return "dot.radiowaves.left.and.right"
        case .raindrop: return "cloud.rain"
        case .reactive: return "hand.tap"
        case .ripple: return "circle.circle"
        case .off: return "lightbulb.slash"
        }
    }
}

struct StatusBar: View {
    @Environment(AppModel.self) private var model
    @Binding var showHardwareModes: Bool

    var body: some View {
        HStack {
            switch model.status {
            case .connected(let name):
                Label(name, systemImage: "keyboard").foregroundStyle(.green)
                if model.effect.isAnimated {
                    Text(String(format: "%.0f fps", model.fps)).monospacedDigit().foregroundStyle(.secondary)
                }
                Spacer()
                Button("Release to keyboard") { model.releaseToHardware() }
                    .help("Exit direct mode so the keyboard's own effects and Fn shortcuts work again")
            case .released(let why):
                Label(why, systemImage: "cpu").foregroundStyle(.secondary)
                Spacer()
                Button("Take control") { model.resumeControl() }
            case .disconnected(let why):
                Label(why, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).lineLimit(2)
                Spacer()
                Button("Retry") { model.connect() }
            }
            Button("Hardware modes…") { showHardwareModes = true }
        }
    }
}

struct ControlsPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(alignment: .top, spacing: 0) {
            // Left: what the effects use.
            VStack(alignment: .leading, spacing: 18) {
                titled("Colors") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        colorRow("Primary", \.settings.primary)
                        colorRow("Secondary", \.settings.secondary)
                        colorRow("Background", \.settings.background)
                    }
                }
                titled("Animation") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Speed")
                            Slider(value: $model.settings.speed, in: 0.1...3).frame(width: 180)
                            Text(String(format: "%.1f×", model.settings.speed))
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                        GridRow {
                            Text("Brightness")
                            Slider(value: $model.settings.brightness, in: 0...1).frame(width: 180)
                            Text("\(Int((model.settings.brightness * 100).rounded()))%")
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    if model.effect.needsKeyEvents {
                        Text("Reactive effects need key events, not wired up yet (ROADMAP M3).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 24)

            // Right: painting keys for the Custom effect.
            VStack(alignment: .leading, spacing: 10) {
                titled("Paint") {
                    Group {
                    HStack(spacing: 10) {
                        Picker("Tool", selection: $model.tool) {
                            ForEach(PaintTool.allCases) { t in
                                Image(systemName: t.systemImage).help(t.rawValue).tag(t)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 220)
                        Text(model.tool.rawValue).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Brush")
                        ColorPicker("Brush", selection: rgbBinding(\.brush), supportsOpacity: false).labelsHidden()
                        Spacer().frame(width: 16)
                        Button("Fill all") { model.fillAll(model.brush) }
                        Button("Clear") { model.clearPaint() }
                    }
                    }
                    .disabled(!model.canPaint)
                    // Always enabled: in Custom it picks the brush, otherwise the Primary color
                    // (the Static color, and the main color of most effects).
                    HStack(spacing: 6) {
                        ForEach(AppModel.palette, id: \.self) { c in
                            let picked = model.paletteColor == c
                            Circle().fill(c.color)
                                .overlay(Circle().stroke(picked ? Color.accentColor : .secondary.opacity(0.4),
                                                         lineWidth: picked ? 2.5 : 1))
                                .frame(width: 22, height: 22)
                                .contentShape(Circle())
                                .onTapGesture { model.pickPaletteColor(c) }
                                .help(model.canPaint ? "Brush color" : "Primary color")
                        }
                    }
                    Text(model.canPaint
                         ? "Click or drag over keys. Changes show on the keyboard right away."
                         : "The palette sets the Primary color. Pick Custom (paint keys) to paint single keys.")
                        .font(.caption).foregroundStyle(.secondary)
                        // Not fixedSize: at the narrow widths SwiftUI probes for the window's
                        // minimum size, a fixed-height wrapping text grows very tall.
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 24)
            // As an overlay the divider is only as tall as this column.
            .overlay(alignment: .leading) { Divider() }
        }
    }

    @ViewBuilder
    private func titled<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private func colorRow(_ title: String, _ path: ReferenceWritableKeyPath<AppModel, RGB>) -> some View {
        GridRow {
            Text(title)
            ColorPicker(title, selection: rgbBinding(path), supportsOpacity: false).labelsHidden()
        }
    }

    private func rgbBinding(_ path: ReferenceWritableKeyPath<AppModel, RGB>) -> Binding<Color> {
        Binding(get: { model[keyPath: path].color }, set: { model[keyPath: path] = RGB($0) })
    }
}

/// The keyboard's built-in (firmware) modes. They can't be selected over USB yet, so this
/// sheet documents the Fn shortcuts and lets the user hand control back to the firmware.
struct HardwareModesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let shortcuts: [(String, String)] = [
        ("Fn + F10", "Cycle modes: Wave, Color Cycle, Raindrop, Ripple, Reactive, Breathing, Radar, Full Backlit, Off"),
        ("Hold Fn + F10 (3 s)", "All backlighting off"),
        ("Fn + ← / →", "Effect speed"),
        ("Fn + ↑ / ↓", "Brightness"),
        ("Fn + F5 / F6 / F7", "Adjust red / green / blue (single-color modes)"),
        ("Fn + F8", "Reset color"),
        ("Fn + Space", "Color palette — tap a key to pick its color"),
        ("Fn + F11 / F12", "Custom Mode 1 / 2 (On, Breathing, Off)"),
        ("Hold Fn + PrtSc / Pause (3 s)", "Record CM1 / CM2, save with Caps Lock + ScrLk"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keyboard firmware modes").font(.title2.bold())
            Text("These run on the keyboard itself and persist without the app. Selecting them from the Mac isn't supported yet (protocol not reverse-engineered — see docs/RESEARCH.md). Release control, then use the shortcuts:")
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, verticalSpacing: 6) {
                ForEach(shortcuts, id: \.0) { s in
                    GridRow {
                        Text(s.0).font(.body.monospaced())
                        Text(s.1)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Release to keyboard") { model.releaseToHardware(); dismiss() }
                Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 640)
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Picker("Keyboard layout", selection: $model.layoutVariant) {
                Text("ANSI (US)").tag(LayoutVariant.ansi)
                Text("ISO (EU/UK)").tag(LayoutVariant.iso)
            }
            Toggle("Hand lighting back to the keyboard while the screen is locked", isOn: $model.releaseWhenLocked)
            Toggle("Hand lighting back to the keyboard while Ducky Lights is in the background",
                   isOn: $model.releaseInBackground)
            Text("The app always releases the keyboard on quit and when the Mac sleeps.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 520)
    }
}

/// `DUCKY_DEBUG_LAYOUT=1` prints view and window geometry, for layout bugs we can't screenshot.
enum LayoutDebug {
    static let on = ProcessInfo.processInfo.environment["DUCKY_DEBUG_LAYOUT"] != nil

    @MainActor static func log(_ name: String, _ g: GeometryProxy) {
        guard on else { return }
        print("\(name): frame=\(g.frame(in: .global)) safe=\(g.safeAreaInsets)")
        for w in NSApp.windows where w.isVisible {
            print("  window \(w.title): frame=\(w.frame) content=\(w.contentLayoutRect) contentView=\(w.contentView?.frame ?? .zero) min=\(w.contentMinSize)")
        }
        fflush(stdout)
    }
}
