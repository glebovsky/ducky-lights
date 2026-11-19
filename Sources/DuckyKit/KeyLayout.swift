import Foundation

public enum LayoutVariant: String, Codable, Sendable {
    case both, ansi, iso
}

public struct KeyInfo: Hashable, Identifiable, Sendable {
    public var id: Int { ledIndex }
    /// Position in the 460-byte color stream: bytes [3*ledIndex, 3*ledIndex+2] are R,G,B.
    public let ledIndex: Int
    public let label: String
    /// Top-left corner and width, in 1u key units.
    public let x: Double
    public let y: Double
    public let width: Double
    public let variant: LayoutVariant

    public init(ledIndex: Int, label: String, x: Double, y: Double, width: Double, variant: LayoutVariant) {
        self.ledIndex = ledIndex; self.label = label
        self.x = x; self.y = y; self.width = width; self.variant = variant
    }

    /// Center in key units, handy for spatial effects.
    public var center: (x: Double, y: Double) { (x + width / 2, y + 0.5) }
}

public struct KeyLayout: Sendable {
    public let keys: [KeyInfo]
    public let width: Double
    public let height: Double

    /// TODO(ISO): in ISO, Left Shift is 1.25u and Enter is the tall ISO shape. Only the
    /// key set is filtered here; geometry tweaks are left for the app (see docs/ROADMAP.md).
    public static func one2TKL(_ variant: LayoutVariant = .ansi) -> KeyLayout {
        let keys = DuckyOne2TKL.keys.filter { $0.variant == .both || $0.variant == variant }
        return KeyLayout(keys: keys, width: DuckyOne2TKL.width, height: DuckyOne2TKL.height)
    }

    public func key(labeled label: String) -> KeyInfo? {
        keys.first { $0.label.caseInsensitiveCompare(label) == .orderedSame }
    }
}
