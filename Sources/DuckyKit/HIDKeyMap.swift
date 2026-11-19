import Foundation

/// USB HID keyboard usages (usage page 0x07) to the key labels in `DuckyOne2TKL`.
/// These are physical key positions, so the macOS input layout doesn't matter.
/// Fn has no usage: the keyboard handles it internally and never reports it.
public enum HIDKeyMap {
    public static let keyboardUsagePage = 0x07

    public static let labels: [Int: String] = {
        var m: [Int: String] = [:]
        for (i, c) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() { m[0x04 + i] = String(c) }
        for (i, c) in "1234567890".enumerated() { m[0x1E + i] = String(c) }
        for i in 1...12 { m[0x39 + i] = "F\(i)" }
        let rest: [Int: String] = [
            0x28: "Enter", 0x29: "Esc", 0x2A: "Backspace", 0x2B: "Tab", 0x2C: "Space",
            0x2D: "-", 0x2E: "=", 0x2F: "[", 0x30: "]", 0x31: "\\", 0x32: "ISO #",
            0x33: ";", 0x34: "'", 0x35: "`", 0x36: ",", 0x37: ".", 0x38: "/",
            0x39: "Caps Lock",
            0x46: "PrtSc", 0x47: "ScrLk", 0x48: "Pause",
            0x49: "Insert", 0x4A: "Home", 0x4B: "PgUp", 0x4C: "Delete", 0x4D: "End", 0x4E: "PgDn",
            0x4F: "Right", 0x50: "Left", 0x51: "Down", 0x52: "Up",
            0x64: "ISO \\",
            0xE0: "Left Ctrl", 0xE1: "Left Shift", 0xE2: "Left Alt/Opt", 0xE3: "Left Win/Cmd",
            0xE4: "Right Ctrl", 0xE5: "Right Shift", 0xE6: "Right Alt/Opt", 0xE7: "Right Win/Cmd",
        ]
        m.merge(rest) { a, _ in a }
        return m
    }()

    /// LED index for a HID usage, or nil for usages this board doesn't have.
    public static func ledIndex(usage: Int) -> Int? {
        guard let label = labels[usage] else { return nil }
        return byLabel[label]
    }

    private static let byLabel: [String: Int] =
        Dictionary(uniqueKeysWithValues: DuckyOne2TKL.keys.map { ($0.label, $0.ledIndex) })
}
