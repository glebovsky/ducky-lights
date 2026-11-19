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
                ControlsPanel()
            }
            .padding(20)
        }
        .sheet(isPresented: $showHardwareModes) { HardwareModesView() }
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

private struct StatusBar: View {
    @Environment(AppModel.self) private var model
    @Binding var showHardwareModes: Bool

    var body: some View {
        HStack {
            switch model.status {
            case .connected(let name):
                Label(name, systemImage: "keyboard").foregroundStyle(.green)
                Text(String(format: "%.0f fps", model.fps)).monospacedDigit().foregroundStyle(.secondary)
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

private struct ControlsPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Colors").font(.headline)
                ColorPicker("Primary", selection: rgbBinding(\.settings.primary), supportsOpacity: false)
                ColorPicker("Secondary", selection: rgbBinding(\.settings.secondary), supportsOpacity: false)
                ColorPicker("Background", selection: rgbBinding(\.settings.background), supportsOpacity: false)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Paint").font(.headline)
                Picker("Tool", selection: $model.tool) {
                    ForEach(PaintTool.allCases) { t in
                        Image(systemName: t.systemImage).help(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
                HStack(spacing: 6) {
                    ForEach(AppModel.palette, id: \.self) { c in
                        Circle().fill(c.color)
                            .overlay(Circle().stroke(.white.opacity(model.brush == c ? 0.9 : 0.2), lineWidth: 2))
                            .frame(width: 22, height: 22)
                            .onTapGesture { model.brush = c; model.settings.primary = c }
                    }
                }
                ColorPicker("Brush (click or drag over keys)", selection: rgbBinding(\.brush), supportsOpacity: false)
                HStack {
                    Button("Fill all with brush") { model.fillAll(model.brush) }
                    Button("Clear paint") { model.clearPaint() }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Animation").font(.headline)
                LabeledContent("Speed") { Slider(value: $model.settings.speed, in: 0.1...3).frame(width: 180) }
                LabeledContent("Brightness") { Slider(value: $model.settings.brightness, in: 0...1).frame(width: 180) }
                if model.effect.needsKeyEvents {
                    Text("Reactive effects need key events — not wired up yet (see ROADMAP M3).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
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
