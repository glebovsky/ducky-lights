import DuckyKit
import SwiftUI

/// The keyboard's own shortcuts (firmware, not the app): a list on the right, a guide for
/// recording media keys on the left, and the board on top showing which keys to press.
struct ShortcutsPage: View {
    @Environment(AppModel.self) private var model
    /// Row or guide step under the mouse; wins over the selected row.
    @State private var hovered: String?
    @State private var function: FirmwareShortcuts.MediaFunction = .playPause
    @State private var trigger = "F8"

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            StatusBar()
            note
            KeyboardView(highlight: highlight)
                .frame(maxWidth: 1600, maxHeight: 240)
                .frame(maxWidth: .infinity)
            HStack(alignment: .top, spacing: 20) {
                MediaSetupGuide(function: $function, trigger: $trigger, hovered: $hovered)
                    .frame(width: 300)
                ShortcutList(selection: $model.shortcutSelection, hovered: $hovered)
                    // No white box: the list sits on the window background, set off from the
                    // guide by a divider (an overlay, not a bare Divider in the HStack — see CLAUDE.md).
                    .scrollContentBackground(.hidden)
                    .overlay(alignment: .leading) { Divider().offset(x: -10) }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: function) { _, f in trigger = Self.suggestedTrigger(f) }
    }

    private var note: some View {
        Group {
            if case .connected = model.status {
                Label("Ducky Lights is in control, so the keyboard ignores these. Click Release to keyboard first.",
                      systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange)
            } else {
                Label("The keyboard handles these itself. None of them needs the app.", systemImage: "keyboard")
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(2)
    }

    private var highlight: Set<Int> {
        let id = hovered ?? model.shortcutSelection
        let labels: [String]
        if let id, id.hasPrefix("step-"), let n = Int(id.dropFirst(5)) {
            labels = FirmwareShortcuts.mediaSetup(function, trigger: trigger).first { $0.id == n }?.highlight ?? []
        } else {
            labels = FirmwareShortcuts.all.first { $0.id == id }?.highlight ?? []
        }
        return Set(labels.compactMap { model.layout.key(labeled: $0)?.ledIndex })
    }

    /// Where a Mac keyboard has the same function (F7 ⏮, F8 ⏯, F9 ⏭, F10 mute, F11/F12 volume).
    static func suggestedTrigger(_ f: FirmwareShortcuts.MediaFunction) -> String {
        switch f {
        case .previous: return "F7"
        case .playPause: return "F8"
        case .next: return "F9"
        case .mute: return "F10"
        case .volumeDown: return "F11"
        case .volumeUp: return "F12"
        case .stop: return "Pause"
        }
    }
}

/// Step-by-step recording of one media key: the One 2 has none out of the box.
private struct MediaSetupGuide: View {
    @Binding var function: FirmwareShortcuts.MediaFunction
    @Binding var trigger: String
    @Binding var hovered: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Set up a media key").font(.headline)
                Text("The keyboard has no media keys until you record them. Hover a step to see its keys.")
                    .font(.callout).foregroundStyle(.secondary)
                    .lineLimit(3)
                Grid(alignment: .leading, verticalSpacing: 6) {
                    GridRow {
                        Text("Function")
                        Picker("Function", selection: $function) {
                            ForEach(FirmwareShortcuts.MediaFunction.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                    }
                    GridRow {
                        Text("Key")
                        Picker("Key", selection: $trigger) {
                            ForEach(FirmwareShortcuts.triggerKeys, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                    }
                }
                ForEach(FirmwareShortcuts.mediaSetup(function, trigger: trigger)) { step in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(step.id)").monospacedDigit().foregroundStyle(.secondary)
                        Text(step.text).lineLimit(3)
                    }
                    .padding(.vertical, 3).padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(hovered == "step-\(step.id)" ? Color.accentColor.opacity(0.15) : .clear,
                                in: RoundedRectangle(cornerRadius: 5))
                    .onHover { inside in
                        if inside { hovered = "step-\(step.id)" } else if hovered == "step-\(step.id)" { hovered = nil }
                    }
                }
                Text("In profile 2, \(trigger) then sends \(function.rawValue.lowercased()) instead. Fn + 1 goes back to the factory profile.")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }
}

private struct ShortcutList: View {
    @Binding var selection: String?
    @Binding var hovered: String?

    var body: some View {
        List(selection: $selection) {
            // Group titles are plain (untagged, so unselectable) rows rather than Section headers:
            // pinned section headers get their own opaque background strip.
            ForEach(FirmwareShortcut.Group.allCases) { group in
                Text(group.rawValue)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.top, group == FirmwareShortcut.Group.allCases.first ? 0 : 10)
                    .listRowSeparator(.hidden)
                ForEach(FirmwareShortcuts.all.filter { $0.group == group }) { s in
                    row(s).tag(s.id)
                        .onHover { inside in
                            if inside { hovered = s.id } else if hovered == s.id { hovered = nil }
                        }
                }
            }
        }
    }

    private func row(_ s: FirmwareShortcut) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(s.keys).font(.body.monospaced()).frame(width: 230, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.action)
                if let note = s.note {
                    Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            Spacer(minLength: 0)
            if s.verified {
                Image(systemName: "checkmark.seal").foregroundStyle(.secondary)
                    .help("Checked on a real One 2 RGB TKL")
            }
        }
        .padding(.vertical, 2)
    }
}
