import Foundation

public struct RGB: Hashable, Codable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.r = r; self.g = g; self.b = b
    }

    public static let black = RGB(0, 0, 0)
    public static let white = RGB(255, 255, 255)

    /// "ff0080" or "#ff0080"
    public init?(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF))
    }

    public var hex: String { String(format: "%02x%02x%02x", r, g, b) }

    /// h, s, v in 0...1
    public static func hsv(_ h: Double, _ s: Double, _ v: Double) -> RGB {
        let h6 = (h - floor(h)) * 6
        let i = Int(h6) % 6
        let f = h6 - floor(h6)
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        let (r, g, b): (Double, Double, Double)
        switch i {
        case 0: (r, g, b) = (v, t, p)
        case 1: (r, g, b) = (q, v, p)
        case 2: (r, g, b) = (p, v, t)
        case 3: (r, g, b) = (p, q, v)
        case 4: (r, g, b) = (t, p, v)
        default: (r, g, b) = (v, p, q)
        }
        return RGB(UInt8(clamping: Int(r * 255)), UInt8(clamping: Int(g * 255)), UInt8(clamping: Int(b * 255)))
    }

    public func scaled(_ k: Double) -> RGB {
        let k = max(0, min(1, k))
        return RGB(UInt8(Double(r) * k), UInt8(Double(g) * k), UInt8(Double(b) * k))
    }

    public func mixed(with o: RGB, _ t: Double) -> RGB {
        let t = max(0, min(1, t))
        func m(_ a: UInt8, _ b: UInt8) -> UInt8 { UInt8(Double(a) + (Double(b) - Double(a)) * t) }
        return RGB(m(r, o.r), m(g, o.g), m(b, o.b))
    }
}
