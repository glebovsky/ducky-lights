import Foundation

/// Parameters shared by all effects. Mirrors what the firmware exposes via Fn shortcuts
/// (color, speed, brightness) plus per-key paint for the Custom effect.
public struct EffectSettings: Codable, Equatable, Sendable {
    public var primary: RGB = RGB(0, 170, 255)
    public var secondary: RGB = RGB(255, 0, 128)
    /// 0.1 ... 3.0, 1 = default
    public var speed: Double = 1
    /// 0 ... 1
    public var brightness: Double = 1
    /// Custom effect: ledIndex -> color. Unpainted keys use `background`.
    public var paint: [Int: RGB] = [:]
    public var background: RGB = .black

    public init() {}
}

/// A key press, for reactive effects (fed by the app from a keyboard event monitor).
public struct KeyPress: Sendable {
    public let ledIndex: Int
    public let time: Double
    public init(ledIndex: Int, time: Double) { self.ledIndex = ledIndex; self.time = time }
}

public struct EffectControls: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let primary = EffectControls(rawValue: 1 << 0)
    public static let background = EffectControls(rawValue: 1 << 1)
    public static let speed = EffectControls(rawValue: 1 << 2)
    public static let brightness = EffectControls(rawValue: 1 << 3)
    public static let paint = EffectControls(rawValue: 1 << 4)
}

/// Software-rendered effects. Named after the firmware modes they imitate, because the
/// firmware's own modes cannot (yet) be selected over USB — see docs/RESEARCH.md.
public enum EffectKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case staticColor = "Static"
    case custom = "Custom (paint keys)"
    case breathing = "Breathing"
    case colorCycle = "Color Cycle"
    case wave = "Rainbow Wave"
    case radar = "Radar"
    case raindrop = "Raindrop"
    case reactive = "Reactive"
    case ripple = "Ripple"
    case heatmap = "Typing Heatmap"
    case off = "Off"

    public var id: String { rawValue }

    /// Needs live key presses (Input Monitoring permission).
    public var needsKeyEvents: Bool { self == .reactive || self == .ripple || self == .heatmap }

    /// The settings this effect reads, so the UI shows only controls that do something.
    /// `EffectControlsTests` checks this against `EffectRenderer`.
    public var controls: EffectControls {
        switch self {
        case .off: return []
        case .staticColor: return [.primary, .brightness]
        case .custom: return [.paint, .background, .brightness]
        case .breathing, .radar: return [.primary, .speed, .brightness]
        case .colorCycle, .wave: return [.speed, .brightness]
        case .raindrop, .reactive, .ripple: return [.primary, .background, .speed, .brightness]
        case .heatmap: return [.background, .speed, .brightness]
        }
    }

    public var isAnimated: Bool {
        switch self {
        case .staticColor, .custom, .off: return false
        default: return true
        }
    }
}

public enum EffectRenderer {
    /// Heatmap memory at speed 1: a key's heat halves roughly every 80 s (time constant 120 s).
    public static let heatTimeConstant = 120.0
    /// Ripple rings live this long (in speed-scaled seconds).
    static let rippleLife = 2.0

    /// Render one frame. `t` is seconds since the effect started; `presses` use the same clock.
    public static func render(_ kind: EffectKind, layout: KeyLayout, settings s: EffectSettings,
                              t: Double, presses: [KeyPress] = []) -> [Int: RGB] {
        let tt = t * s.speed
        var out: [Int: RGB] = [:]
        out.reserveCapacity(layout.keys.count)

        // Per-frame work, so the per-key loop stays cheap with a long press history.
        var lastPress: [Int: Double] = [:]
        var rings: [(x: Double, y: Double, age: Double)] = []
        var heat: [Int: Double] = [:]
        var maxHeat = 0.0
        switch kind {
        case .reactive:
            for p in presses where p.time <= t { lastPress[p.ledIndex] = max(lastPress[p.ledIndex] ?? -.infinity, p.time) }
        case .ripple:
            let centers = Dictionary(uniqueKeysWithValues: layout.keys.map { ($0.ledIndex, $0.center) })
            for p in presses {
                let age = (t - p.time) * s.speed
                guard age >= 0, age < rippleLife, let c = centers[p.ledIndex] else { continue }
                rings.append((c.x, c.y, age))
            }
        case .heatmap:
            let tau = heatTimeConstant / s.speed
            for p in presses where p.time <= t { heat[p.ledIndex, default: 0] += exp(-(t - p.time) / tau) }
            maxHeat = heat.values.max() ?? 0
        default:
            break
        }

        for key in layout.keys {
            let (cx, cy) = key.center
            let c: RGB
            switch kind {
            case .off:
                c = .black
            case .staticColor:
                c = s.primary
            case .custom:
                c = s.paint[key.ledIndex] ?? s.background
            case .breathing:
                c = s.primary.scaled(0.5 - 0.5 * cos(tt * 2))
            case .colorCycle:
                c = RGB.hsv(tt * 0.1, 1, 1)
            case .wave:
                c = RGB.hsv(cx / layout.width - tt * 0.25, 1, 1)
            case .radar:
                let angle = atan2(cy - layout.height / 2, cx - layout.width / 2) / (2 * .pi) + 0.5
                let d = (angle - tt * 0.3).truncatingRemainder(dividingBy: 1)
                let trail = d < 0 ? d + 1 : d
                c = s.primary.scaled(max(0, 1 - trail * 4))
            case .raindrop:
                // Deterministic pseudo-random sparkle per key.
                let seed = sin(Double(key.ledIndex) * 12.9898) * 43758.5453
                let phase = seed - floor(seed)
                let local = (tt * 0.6 + phase).truncatingRemainder(dividingBy: 1)
                c = s.background.mixed(with: s.primary, max(0, 1 - local * 3))
            case .reactive:
                let age = lastPress[key.ledIndex].map { t - $0 } ?? .infinity
                c = s.primary.mixed(with: s.background, min(1, age * s.speed))
            case .ripple:
                var v = 0.0
                for r in rings {
                    let ring = abs(hypot(cx - r.x, cy - r.y) - r.age * 8)
                    v = max(v, max(0, 1 - ring) * (1 - r.age / rippleLife))
                }
                c = s.background.mixed(with: s.primary, v)
            case .heatmap:
                let v = maxHeat > 0 ? (heat[key.ledIndex] ?? 0) / maxHeat : 0
                // Untouched keys stay on the background; anything typed shows at least a cool blue.
                c = v > 0.001 ? s.background.mixed(with: heatColor(v), min(1, 0.35 + v)) : s.background
            }
            out[key.ledIndex] = c.scaled(s.brightness)
        }
        return out
    }

    /// Cold to hot: blue, cyan, green, yellow, red.
    static func heatColor(_ v: Double) -> RGB {
        let stops: [RGB] = [RGB(0, 40, 255), RGB(0, 220, 255), RGB(0, 255, 60), RGB(255, 230, 0), RGB(255, 20, 0)]
        let x = max(0, min(1, v)) * Double(stops.count - 1)
        let i = min(Int(x), stops.count - 2)
        return stops[i].mixed(with: stops[i + 1], x - Double(i))
    }
}
