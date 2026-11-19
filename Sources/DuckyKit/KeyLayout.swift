import Foundation

public enum LayoutVariant: String, Codable, Sendable, CaseIterable {
    case both, ansi, iso
}

public enum KeyShape: String, Codable, Sendable {
    case rect
    /// The tall ISO Enter: 1.5u wide on its top row, 1.25u on the row below, flush right.
    /// `x`/`width` describe the lower part; the top part reaches 0.25u further left.
    case isoEnter
}

public struct KeyInfo: Hashable, Identifiable, Sendable {
    public var id: Int { ledIndex }
    /// Position in the 460-byte color stream: bytes [3*ledIndex, 3*ledIndex+2] are R,G,B.
    public let ledIndex: Int
    public let label: String
    /// Top-left corner, width and height, in 1u key units.
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let shape: KeyShape
    public let variant: LayoutVariant

    public init(ledIndex: Int, label: String, x: Double, y: Double, width: Double,
                variant: LayoutVariant, height: Double = 1, shape: KeyShape = .rect) {
        self.ledIndex = ledIndex; self.label = label
        self.x = x; self.y = y; self.width = width; self.height = height
        self.shape = shape; self.variant = variant
    }

    /// Center in key units, handy for spatial effects.
    public var center: (x: Double, y: Double) { (x + width / 2, y + height / 2) }

    /// Hit test in key units.
    public func contains(x px: Double, y py: Double) -> Bool {
        switch shape {
        case .rect:
            return px >= x && px < x + width && py >= y && py < y + height
        case .isoEnter:
            let top = py >= y && py < y + 1 && px >= x - 0.25 && px < x + width
            let bottom = py >= y + 1 && py < y + height && px >= x && px < x + width
            return top || bottom
        }
    }

    func with(width: Double) -> KeyInfo {
        KeyInfo(ledIndex: ledIndex, label: label, x: x, y: y, width: width,
                variant: variant, height: height, shape: shape)
    }
}

public struct KeyLayout: Sendable {
    public let keys: [KeyInfo]
    public let width: Double
    public let height: Double

    public init(keys: [KeyInfo], width: Double, height: Double) {
        self.keys = keys; self.width = width; self.height = height
    }

    /// The generated geometry is ANSI-shaped. For ISO this shortens Left Shift to 1.25u
    /// (making room for the extra `ISO \` key) and turns Enter into the tall ISO shape
    /// (making room for `ISO #`). LED indices don't change.
    public static func one2TKL(_ variant: LayoutVariant = .ansi) -> KeyLayout {
        var keys = DuckyOne2TKL.keys.filter { $0.variant == .both || $0.variant == variant }
        if variant == .iso {
            keys = keys.map { k in
                switch k.label {
                case "Left Shift":
                    return k.with(width: 1.25)
                case "Enter":
                    return KeyInfo(ledIndex: k.ledIndex, label: k.label, x: 13.75, y: 2.25, width: 1.25,
                                   variant: k.variant, height: 2, shape: .isoEnter)
                default:
                    return k
                }
            }
        }
        return KeyLayout(keys: keys, width: DuckyOne2TKL.width, height: DuckyOne2TKL.height)
    }

    public func key(labeled label: String) -> KeyInfo? {
        keys.first { $0.label.caseInsensitiveCompare(label) == .orderedSame }
    }

    /// The key under a point given in key units.
    public func key(atX x: Double, y: Double) -> KeyInfo? {
        keys.first { $0.contains(x: x, y: y) }
    }

    /// Keys in the same physical row (same top edge).
    public func row(of key: KeyInfo) -> [KeyInfo] {
        keys.filter { abs($0.y - key.y) < 0.01 }
    }

    /// Keys in every row whose span covers the horizontal center of `key`.
    public func column(of key: KeyInfo) -> [KeyInfo] {
        let cx = key.center.x
        return keys.filter { cx >= $0.x && cx < $0.x + $0.width }
    }
}
