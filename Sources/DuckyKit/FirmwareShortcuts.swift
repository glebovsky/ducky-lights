import Foundation

/// A shortcut the keyboard's firmware handles on its own (Fn layer, macro recording…).
/// The app only shows these. It never sends them. Source: Ducky's One Series manual,
/// transcribed in docs/SHORTCUTS.md (keep the two in sync).
public struct FirmwareShortcut: Identifiable, Hashable, Sendable {
    public enum Group: String, CaseIterable, Identifiable, Sendable {
        case media = "Media keys (while recording a macro)"
        case lighting = "Lighting"
        case custom = "Custom lighting (CM1 / CM2)"
        case macros = "Macros"
        case other = "Other"
        public var id: String { rawValue }
    }

    public var id: String { "\(group.rawValue)|\(keys)" }
    public let group: Group
    /// How to press it, as printed: "Fn + F10", "Hold Fn + Ctrl (3 s)".
    public let keys: String
    public let action: String
    public let note: String?
    /// Key labels (`KeyLayout` labels) to light up in the preview.
    public let highlight: [String]
    /// Checked on the owner's board, not only copied from the manual.
    public let verified: Bool

    public init(_ group: Group, _ keys: String, _ action: String, note: String? = nil,
                highlight: [String], verified: Bool = false) {
        self.group = group; self.keys = keys; self.action = action; self.note = note
        self.highlight = highlight; self.verified = verified
    }
}

public enum FirmwareShortcuts {
    /// The media functions, as picked with Fn + Win + letter while recording a macro.
    public enum MediaFunction: String, CaseIterable, Identifiable, Sendable {
        case playPause = "Play / pause"
        case next = "Next track"
        case previous = "Previous track"
        case volumeUp = "Volume up"
        case volumeDown = "Volume down"
        case mute = "Mute"
        case stop = "Stop"
        public var id: String { rawValue }

        /// The letter pressed with Fn + Win.
        public var letter: String {
            switch self {
            case .mute: return "A"
            case .volumeUp: return "B"
            case .volumeDown: return "C"
            case .playPause: return "D"
            case .stop: return "E"
            case .next: return "F"
            case .previous: return "G"
            }
        }
    }

    /// Plain keys offered as macro triggers in the setup guide. (Fn + F-keys, Fn + PrtSc and
    /// the other firmware combos can't be triggers; plain keys can.)
    public static let triggerKeys = ["F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
                                     "PrtSc", "ScrLk", "Pause", "Insert", "Home", "PgUp", "Delete", "End", "PgDn"]

    public struct Step: Identifiable, Hashable, Sendable {
        public let id: Int
        public let text: String
        public let highlight: [String]
    }

    /// Recording one media key as a macro on profile 2 (manual p. 41–47, example D).
    public static func mediaSetup(_ f: MediaFunction, trigger: String) -> [Step] {
        let steps: [(String, [String])] = [
            ("Press Fn + 2 to switch to profile 2. Profile 1 is the factory profile and can't hold macros.",
             ["Fn", "2"]),
            ("Hold Fn + Ctrl for 3 seconds. Caps Lock starts flashing slowly.", ["Fn", "Right Ctrl"]),
            ("Press \(trigger), the key that will do it. Caps Lock flashes fast.", [trigger]),
            ("Press Fn + Win + \(f.letter) (\(f.rawValue.lowercased())).", ["Fn", "Left Win/Cmd", f.letter]),
            ("Press Fn + Q: run once per press.", ["Fn", "Q"]),
            ("Press Fn + Ctrl to finish, or Fn + Alt to record another key.", ["Fn", "Right Ctrl"]),
        ]
        return steps.enumerated().map { Step(id: $0.offset + 1, text: $0.element.0, highlight: $0.element.1) }
    }

    /// Fn + F10 order on the RGB board (manual p. 32).
    public static let rgbModes = ["Wave", "Alpha", "Tetris", "Color Cycle", "Rain Drop", "Circle Ripple",
                                  "Random Reactive", "Aurora", "Reactive", "Breathe", "Full Backlit", "Off"]

    public static let all: [FirmwareShortcut] = media + lighting + custom + macros + other

    private static let media: [FirmwareShortcut] = MediaFunction.allCases.map { f in
        FirmwareShortcut(.media, "Fn + Win + \(f.letter)", f.rawValue, highlight: ["Fn", "Left Win/Cmd", f.letter])
    } + [
        FirmwareShortcut(.media, "Fn + Win + H … O", "Calculator, My Computer, Browser, Mail, Media player, Search, Back, Forward",
                         note: "Some of these may do nothing on a Mac.",
                         highlight: ["Fn", "Left Win/Cmd", "H", "I", "J", "K", "L", "M", "N", "O"]),
        FirmwareShortcut(.media, "Fn + Win + P … X", "Mouse clicks, cursor moves and scrolling",
                         highlight: ["Fn", "Left Win/Cmd", "P", "Q", "R", "S", "T", "U", "V", "W", "X"]),
    ]

    private static let lighting: [FirmwareShortcut] = [
        FirmwareShortcut(.lighting, "Fn + F10", "Next lighting mode",
                         note: rgbModes.joined(separator: " → "), highlight: ["Fn", "F10"]),
        FirmwareShortcut(.lighting, "Hold Fn + F10 (3 s)", "All backlight off, CM1 and CM2 too", highlight: ["Fn", "F10"]),
        FirmwareShortcut(.lighting, "Fn + ← / →", "Slower / faster", highlight: ["Fn", "Left", "Right"]),
        FirmwareShortcut(.lighting, "Fn + ↑ / ↓", "Brighter / dimmer", highlight: ["Fn", "Up", "Down"], verified: true),
        FirmwareShortcut(.lighting, "Fn + F5 / F6 / F7", "Red / green / blue level (10 steps)",
                         note: "Aurora, Reactive, Breathe and Full Backlit only.", highlight: ["Fn", "F5", "F6", "F7"]),
        FirmwareShortcut(.lighting, "Fn + F8", "Clear red, green and blue",
                         note: "Aurora, Reactive, Breathe and Full Backlit only.", highlight: ["Fn", "F8"]),
        FirmwareShortcut(.lighting, "Fn + Space", "Color palette: press a lit key to take its color",
                         note: "Aurora, Reactive, Breathe and Full Backlit only.", highlight: ["Fn", "Space"]),
        FirmwareShortcut(.lighting, "Hold Fn + Alt + Ctrl (3 s)", "Show off every mode in turn",
                         highlight: ["Fn", "Right Alt/Opt", "Right Ctrl"]),
    ]

    private static let custom: [FirmwareShortcut] = [
        FirmwareShortcut(.custom, "Fn + F11 / F12", "CM1 / CM2 on, press again for off", highlight: ["Fn", "F11", "F12"]),
        FirmwareShortcut(.custom, "Fn + PrtSc / Pause", "Start recording CM1 / CM2",
                         note: "Pick a color, then press the keys that should get it. 30 s without a change ends without saving.",
                         highlight: ["Fn", "PrtSc", "Pause"]),
        FirmwareShortcut(.custom, "Caps Lock + F5 / F6 / F7", "While recording: red / green / blue of the color",
                         highlight: ["Caps Lock", "F5", "F6", "F7"]),
        FirmwareShortcut(.custom, "Caps Lock + F8", "While recording: clear the color", highlight: ["Caps Lock", "F8"]),
        FirmwareShortcut(.custom, "Caps Lock + Space", "While recording: color palette", highlight: ["Caps Lock", "Space"]),
        FirmwareShortcut(.custom, "Caps Lock + ScrLk", "Stop recording and save", highlight: ["Caps Lock", "ScrLk"]),
    ]

    private static let macros: [FirmwareShortcut] = [
        FirmwareShortcut(.macros, "Fn + 1 … 6", "Switch profile (1 is factory, 2–6 hold macros)",
                         highlight: ["Fn", "1", "2", "3", "4", "5", "6"]),
        FirmwareShortcut(.macros, "Hold Fn + Ctrl (3 s)", "Start recording a macro",
                         note: "Then press the trigger key, then what it should send.", highlight: ["Fn", "Right Ctrl"]),
        FirmwareShortcut(.macros, "Fn + Q / W / E", "Run once per press / toggle on and off / while held",
                         highlight: ["Fn", "Q", "W", "E"]),
        FirmwareShortcut(.macros, "Fn + 1 … 6 (recording)", "Fixed delay between presses: 0.02 to 1 s",
                         note: "Without it, your own typing speed is recorded.", highlight: ["Fn", "1", "2", "3", "4", "5", "6"]),
        FirmwareShortcut(.macros, "Fn + Ctrl", "Finish recording", highlight: ["Fn", "Right Ctrl"]),
        FirmwareShortcut(.macros, "Fn + Alt", "Save this key and record another", highlight: ["Fn", "Right Alt/Opt"]),
        FirmwareShortcut(.macros, "Hold Win + Space (3 s)", "Clear every macro in this profile",
                         highlight: ["Left Win/Cmd", "Space"]),
    ]

    private static let other: [FirmwareShortcut] = [
        FirmwareShortcut(.other, "Fn + ScrLk", "Mouse keys on / off", highlight: ["Fn", "ScrLk"]),
        FirmwareShortcut(.other, "Hold Fn + Alt + Win (3 s)", "Win key lock on / off",
                         highlight: ["Fn", "Left Alt/Opt", "Left Win/Cmd"]),
        FirmwareShortcut(.other, "Hold Fn + Esc (3 s)", "Key repeat tuning on / off",
                         note: "Then Fn + F1–F4 sets the repeat delay, Fn + Alt + F1–F4 the repeat rate.",
                         highlight: ["Fn", "Esc", "F1", "F2", "F3", "F4"]),
        FirmwareShortcut(.other, "Hold Left Win + Right Win (3 s)", "Factory reset",
                         highlight: ["Left Win/Cmd", "Right Win/Cmd"]),
        FirmwareShortcut(.other, "Right Alt + Space, plug in", "USB 3.0 power mode (default)",
                         highlight: ["Right Alt/Opt", "Space"]),
        FirmwareShortcut(.other, "Left Alt + Space, plug in", "USB 2.0 power mode", highlight: ["Left Alt/Opt", "Space"]),
    ]
}
