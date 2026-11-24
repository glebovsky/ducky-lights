import DuckyKit
import ServiceManagement
import SwiftUI

enum SidebarItem: Hashable {
    case effect(EffectKind)
    case profile(UUID)
    case shortcuts
}

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        // The sidebar is always shown: no toggle. (Reopening it stuttered in SwiftUI even with an
        // empty detail column, and there's no reason to hide it.)
        NavigationSplitView(columnVisibility: .constant(.all)) {
            ProfileSidebar()
                .navigationSplitViewColumnWidth(210)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            if model.showingShortcuts {
                ShortcutsPage()
            } else {
                lighting
            }
        }
        .alert("Profiles", isPresented: Binding(get: { model.profileMessage != nil },
                                               set: { if !$0 { model.profileMessage = nil } })) {
            Button("OK") { model.profileMessage = nil }
        } message: {
            Text(model.profileMessage ?? "")
        }
        .background { if LayoutDebug.on { LayoutDebug.probe("root") } }
    }

    private var lighting: some View {
        VStack(alignment: .leading, spacing: 16) {
            StatusBar()
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
        .background { if LayoutDebug.on { LayoutDebug.probe("detail") } }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Pinned to the bottom, in the empty space under the controls, so nothing above
        // it moves when it appears. (In the toolbar it changed the title bar's height.)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.activeProfileEdited { ProfileEditedBar() }
        }
    }

    static func icon(_ k: EffectKind) -> String {
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
        case .heatmap: return "flame"
        case .off: return "lightbulb.slash"
        }
    }
}

struct StatusBar: View {
    @Environment(AppModel.self) private var model

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
        }
    }
}

struct ControlsPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let c = model.effect.controls
        if c.isEmpty {
            Text("All LEDs off.").foregroundStyle(.secondary)
        } else {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 18) {
                    if c.contains(.primary) || c.contains(.background) { colors(c) }
                    if c.contains(.paint) { lighting(c) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 24)

                VStack(alignment: .leading, spacing: 18) {
                    if c.contains(.paint) { PaintSection() } else { lighting(c) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 24)
                // As an overlay the divider is only as tall as this column. A bare vertical
                // Divider in the HStack is greedy and broke the window layout.
                .overlay(alignment: .leading) { Divider() }
            }
        }
    }

    @ViewBuilder
    private func colors(_ c: EffectControls) -> some View {
        @Bindable var model = model
        Titled("Colors") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                if c.contains(.primary) {
                    GridRow {
                        Text("Color")
                        ColorPicker("Color", selection: model.rgbBinding(\.settings.primary), supportsOpacity: false)
                            .labelsHidden()
                    }
                }
                if c.contains(.background) {
                    GridRow {
                        Text("Background")
                        ColorPicker("Background", selection: model.rgbBinding(\.settings.background), supportsOpacity: false)
                            .labelsHidden()
                    }
                }
            }
            if c.contains(.primary) {
                PaletteRow(selection: $model.settings.primary)
            }
        }
    }

    @ViewBuilder
    private func lighting(_ c: EffectControls) -> some View {
        @Bindable var model = model
        Titled(c.contains(.speed) ? "Animation" : "Lighting") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                if c.contains(.speed) {
                    GridRow {
                        Text(model.effect == .heatmap ? "Cool-down" : "Speed")
                        Slider(value: $model.settings.speed, in: 0.1...3).frame(width: 180)
                        Text(String(format: "%.1f×", model.settings.speed))
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                if c.contains(.brightness) {
                    GridRow {
                        Text("Brightness")
                        Slider(value: $model.settings.brightness, in: 0...1).frame(width: 180)
                        Text("\(Int((model.settings.brightness * 100).rounded()))%")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
            if model.effect.needsKeyEvents { KeyAccessView() }
        }
    }
}

/// Permission state for the key-reactive effects.
private struct KeyAccessView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch model.keyAccess {
            case .granted:
                HStack {
                    Label(model.isListeningToKeys ? "Reacting to keys on the Ducky" : "Waiting for the Ducky…",
                          systemImage: "keyboard")
                        .font(.caption).foregroundStyle(.secondary)
                    if model.effect == .heatmap {
                        Button("Reset heatmap") { model.clearPresses() }.controlSize(.small)
                    }
                }
            case .unknown:
                Text("Needs Input Monitoring to see key presses. Only the Ducky is watched, and only while this effect is on.")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(3)
                Button("Allow key access…") { model.requestKeyAccess() }
            case .denied:
                Text("Input Monitoring is off for Ducky Lights. Turn it on in Privacy & Security, then come back here. Already shows as on? It belongs to an older build: remove it there with −, then allow again.")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(4)
                Button("Open Privacy Settings…") { model.requestKeyAccess() }
            }
        }
    }
}

/// Painting tools, only shown for the Custom effect.
private struct PaintSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Titled("Paint") {
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
            PaletteRow(selection: $model.brush)
            HStack {
                Text("Brush")
                ColorPicker("Brush", selection: model.rgbBinding(\.brush), supportsOpacity: false).labelsHidden()
                Spacer().frame(width: 16)
                Button("Fill all") { model.fillAll(model.brush) }
                Button("Clear") { model.clearPaint() }
            }
            Text("Click or drag over keys. Unpainted keys show the background color.")
                .font(.caption).foregroundStyle(.secondary)
                // Not fixedSize: at the narrow widths SwiftUI probes for the window's minimum
                // size, a fixed-height wrapping text grows very tall and breaks the layout.
                .lineLimit(3)
        }
    }
}

/// One-click colors.
private struct PaletteRow: View {
    @Binding var selection: RGB

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppModel.palette, id: \.self) { c in
                let picked = selection == c
                Circle().fill(c.color)
                    .overlay(Circle().stroke(picked ? Color.accentColor : .secondary.opacity(0.4),
                                             lineWidth: picked ? 2.5 : 1))
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
                    .onTapGesture { selection = c }
            }
        }
    }
}

private struct Titled<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content
        }
    }
}

/// The keyboard's built-in (firmware) modes. They can't be selected over USB yet, so this
/// sheet documents the Fn shortcuts and lets the user hand control back to the firmware.
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

            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin },
                                                        set: { model.setLaunchAtLogin($0) }))
                    .disabled(!model.isBundled)
                if !model.isBundled {
                    Text("Works in the installed app only (scripts/build-app.sh --install).")
                        .font(.caption).foregroundStyle(.secondary)
                } else if model.loginItemStatus == .requiresApproval {
                    HStack {
                        Text("macOS needs your OK in Login Items.").font(.caption)
                        Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if let err = model.loginItemError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
                Toggle("Open the window when the app starts", isOn: $model.openWindowAtLaunch)
                Text("Off: the app starts in the menu bar only and puts your last effect back on the keyboard.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { model.refreshLoginItem() }
        .formStyle(.grouped)
        .frame(width: 520)
    }
}

/// `DUCKY_DEBUG_LAYOUT=1` prints view and window geometry, for layout bugs we can't screenshot.
enum LayoutDebug {
    static let on = ProcessInfo.processInfo.environment["DUCKY_DEBUG_LAYOUT"] != nil

    /// A background that logs its frame. Only attached when `on`: a GeometryReader costs a
    /// layout pass on every animation frame.
    @MainActor static func probe(_ name: String) -> some View {
        GeometryReader { g in
            Color.clear.onAppear { log(name, g) }.onChange(of: g.frame(in: .global)) { log(name, g) }
        }
    }

    @MainActor static func log(_ name: String, _ g: GeometryProxy) {
        guard on else { return }
        print("\(name): frame=\(g.frame(in: .global)) safe=\(g.safeAreaInsets)")
        for w in NSApp.windows where w.isVisible {
            print("  window \(w.title): frame=\(w.frame) content=\(w.contentLayoutRect) contentView=\(w.contentView?.frame ?? .zero) min=\(w.contentMinSize)")
        }
        fflush(stdout)
    }
}

/// Effects, then saved profiles. Picking an effect leaves the active profile; picking a
/// profile applies it.
private struct ProfileSidebar: View {
    @Environment(AppModel.self) private var model
    @State private var naming: Naming?
    @State private var nameText = ""

    private enum Naming: Identifiable {
        case new
        case rename(UUID)
        var id: String { if case .rename(let u) = self { return u.uuidString } else { return "new" } }
    }

    var body: some View {
        List(selection: selection) {
            Section("Effects") {
                ForEach(EffectKind.allCases) { kind in
                    Label(kind.rawValue, systemImage: ContentView.icon(kind)).tag(SidebarItem.effect(kind))
                }
            }
            Section("Profiles") {
                if model.profiles.isEmpty {
                    Text("Set up a look, then click + to save it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(model.profiles) { p in
                    HStack {
                        Label(p.name, systemImage: "bookmark")
                        if p.id == model.activeProfileID && model.activeProfileEdited {
                            Spacer()
                            Text("Edited").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .tag(SidebarItem.profile(p.id))
                    .contextMenu { menu(for: p) }
                }
                .onMove { model.moveProfiles(fromOffsets: $0, toOffset: $1) }
            }
            Section("Keyboard") {
                Label("Shortcuts", systemImage: "command").tag(SidebarItem.shortcuts)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 4) {
                Button { startNaming(.new) } label: { Image(systemName: "plus") }
                    .help("Save the current look as a profile")
                Menu {
                    Button("Import Profiles…") { importProfiles() }
                    Button("Export All Profiles…") { export(model.profiles.map(\.id), suggested: "Ducky Lights profiles") }
                        .disabled(model.profiles.isEmpty)
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuIndicator(.hidden)
                    .fixedSize()
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .alert(naming.map { if case .new = $0 { return "Save Profile" } else { return "Rename Profile" } } ?? "",
               isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name", text: $nameText)
            Button("Cancel", role: .cancel) { naming = nil }
            Button(naming.map { if case .new = $0 { return "Save" } else { return "Rename" } } ?? "OK") { finishNaming() }
        } message: {
            if case .new = naming { Text("Saves the current effect, colors and painted keys.") }
        }
    }

    private var selection: Binding<SidebarItem?> {
        Binding(
            get: { model.showingShortcuts ? .shortcuts : lightingItem },
            set: { item in
                guard let item else { return }
                if item == .shortcuts { model.showingShortcuts = true; return }
                model.showingShortcuts = false
                // Coming back from Shortcuts to the current look: don't re-apply it, which
                // would throw away a profile's unsaved tweaks.
                guard item != lightingItem else { return }
                switch item {
                case .effect(let k): model.selectEffect(k)
                case .profile(let id): model.applyProfile(id)
                case .shortcuts: break
                }
            })
    }

    private var lightingItem: SidebarItem {
        model.activeProfileID.map { .profile($0) } ?? .effect(model.effect)
    }

    @ViewBuilder
    private func menu(for p: Profile) -> some View {
        Button("Apply") { model.applyProfile(p.id) }
        if p.id == model.activeProfileID {
            Button("Update with Current Settings") { model.updateActiveProfile() }
                .disabled(!model.activeProfileEdited)
        }
        Button("Rename…") { startNaming(.rename(p.id)) }
        Button("Export…") { export([p.id], suggested: p.name) }
        Divider()
        Button("Delete", role: .destructive) { model.deleteProfile(p.id) }
    }

    private func startNaming(_ n: Naming) {
        switch n {
        case .new: nameText = model.uniqueProfileName(model.effect.rawValue)
        case .rename(let id): nameText = model.profiles.first { $0.id == id }?.name ?? ""
        }
        naming = n
    }

    private func finishNaming() {
        switch naming {
        case .new: model.saveNewProfile(named: nameText)
        case .rename(let id): model.renameProfile(id, to: nameText)
        case nil: break
        }
        naming = nil
    }

    private func export(_ ids: [UUID], suggested: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = suggested + ".json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try model.exportData(ids).write(to: url, options: .atomic) } catch {
            model.profileMessage = "Couldn't export: \(error.localizedDescription)"
        }
    }

    private func importProfiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        model.importProfiles(from: panel.urls)
    }
}

/// Bottom bar while the active profile has unsaved tweaks.
private struct ProfileEditedBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "bookmark.fill").foregroundStyle(.tint)
                Text("\u{201C}\(model.activeProfile?.name ?? "")\u{201D} has unsaved changes")
                Spacer()
                Button("Revert") { model.revertActiveProfile() }
                    .help("Go back to the saved profile")
                Button("Update Profile") { model.updateActiveProfile() }
                    .buttonStyle(.borderedProminent)
                    .help("Save the current settings into this profile")
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
        .background(.bar)
    }
}
