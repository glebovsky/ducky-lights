import DuckyKit
import SwiftUI

/// The board drawn like the real thing: dark case, plate lit by the LEDs bleeding between
/// keys, sculpted black caps with shine-through legends. Click or drag to paint.
struct KeyboardView: View {
    @Environment(AppModel.self) private var model
    @State private var hovered: KeyInfo?
    @State private var lastPainted: Int?

    /// Case border around the keys, in key units.
    static let casePadding = 0.42

    var body: some View {
        let layout = model.layout
        // Drawn off the main thread, so resizing (e.g. the sidebar animation) stays smooth.
        Canvas(rendersAsynchronously: true) { ctx, size in
            let m = Metrics(size: size, layout: layout)
            drawCase(&ctx, m)
            drawGlow(&ctx, m, layout)
            let targets = model.canPaint ? (hovered.map { model.targets(for: $0) } ?? []) : []
            for key in layout.keys {
                drawKey(&ctx, m, key, led: model.preview[key.ledIndex] ?? .black,
                        highlighted: targets.contains(key.ledIndex))
            }
        }
        .aspectRatio((layout.width + 2 * Self.casePadding) / (layout.height + 2 * Self.casePadding),
                     contentMode: .fit)
        .overlay {
            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                        guard let key = key(at: v.location, size: geo.size) else { return }
                        guard key.ledIndex != lastPainted else { return }
                        model.apply(to: key, dragging: lastPainted != nil)
                        lastPainted = key.ledIndex
                    }.onEnded { _ in lastPainted = nil })
                    .onContinuousHover { phase in
                        if case .active(let p) = phase { hovered = key(at: p, size: geo.size) } else { hovered = nil }
                    }
            }
            // Outside Custom the board is display-only, so a stray click can't switch effects.
            .allowsHitTesting(model.canPaint)
        }
    }

    private func key(at p: CGPoint, size: CGSize) -> KeyInfo? {
        let m = Metrics(size: size, layout: model.layout)
        return model.layout.key(atX: (p.x - m.origin.x) / m.unit, y: (p.y - m.origin.y) / m.unit)
    }

    // MARK: - Drawing

    private struct Metrics {
        let unit: CGFloat
        /// Top-left of key (0, 0).
        let origin: CGPoint
        let caseRect: CGRect

        init(size: CGSize, layout: KeyLayout) {
            let pad = KeyboardView.casePadding
            let w = layout.width + 2 * pad, h = layout.height + 2 * pad
            unit = min(size.width / w, size.height / h)
            let caseSize = CGSize(width: w * unit, height: h * unit)
            let corner = CGPoint(x: (size.width - caseSize.width) / 2, y: (size.height - caseSize.height) / 2)
            caseRect = CGRect(origin: corner, size: caseSize)
            origin = CGPoint(x: corner.x + pad * unit, y: corner.y + pad * unit)
        }

        func rect(x: Double, y: Double, w: Double, h: Double) -> CGRect {
            CGRect(x: origin.x + x * unit, y: origin.y + y * unit, width: w * unit, height: h * unit)
        }
    }

    private func drawCase(_ ctx: inout GraphicsContext, _ m: Metrics) {
        let shell = Path(roundedRect: m.caseRect, cornerRadius: m.unit * 0.32)
        ctx.fill(shell, with: .linearGradient(
            Gradient(colors: [Color(white: 0.13), Color(white: 0.07)]),
            startPoint: CGPoint(x: m.caseRect.midX, y: m.caseRect.minY),
            endPoint: CGPoint(x: m.caseRect.midX, y: m.caseRect.maxY)))
        ctx.stroke(shell, with: .color(.white.opacity(0.07)), lineWidth: 1)
        // Plate: a slightly recessed darker area under the keys.
        let plate = m.caseRect.insetBy(dx: m.unit * 0.3, dy: m.unit * 0.3)
        ctx.fill(Path(roundedRect: plate, cornerRadius: m.unit * 0.1), with: .color(Color(white: 0.035)))
    }

    /// LED light bleeding onto the plate between and around the caps (the switches have clear housings).
    private func drawGlow(_ ctx: inout GraphicsContext, _ m: Metrics, _ layout: KeyLayout) {
        ctx.drawLayer { glow in
            glow.addFilter(.blur(radius: m.unit * 0.2))
            for key in layout.keys {
                guard let led = model.preview[key.ledIndex], led != .black else { continue }
                glow.fill(capPath(key, m, inset: 0.02), with: .color(led.color.opacity(0.85)))
            }
        }
    }

    private func drawKey(_ ctx: inout GraphicsContext, _ m: Metrics, _ key: KeyInfo, led: RGB, highlighted: Bool) {
        let skirt = capPath(key, m, inset: 0.055)
        let b = skirt.boundingRect
        ctx.fill(skirt, with: .linearGradient(
            Gradient(colors: [Color(white: 0.15), Color(white: 0.085)]),
            startPoint: CGPoint(x: b.midX, y: b.minY), endPoint: CGPoint(x: b.midX, y: b.maxY)))
        // Top face: smaller, set back from the front edge, a touch lighter.
        let top = capPath(key, m, inset: 0.13, front: 0.2, back: 0.07)
        let t = top.boundingRect
        ctx.fill(top, with: .linearGradient(
            Gradient(colors: [Color(white: 0.19), Color(white: 0.145)]),
            startPoint: CGPoint(x: t.midX, y: t.minY), endPoint: CGPoint(x: t.midX, y: t.maxY)))
        if highlighted {
            ctx.stroke(skirt, with: .color(.white.opacity(0.75)), lineWidth: max(1, m.unit * 0.03))
        }
        drawLegend(&ctx, m, key, in: t, led: led)
    }

    private func drawLegend(_ ctx: inout GraphicsContext, _ m: Metrics, _ key: KeyInfo, in face: CGRect, led: RGB) {
        let legend = KeyLegend.for(key.label)
        guard !legend.isEmpty else { return }
        let lit = led.luminance > 0.04
        // Shine-through legends show the LED color, lifted toward white like real PBT does.
        let ink: Color = lit ? led.mixed(with: .white, 0.3).color : Color(white: 0.32)
        let pad = m.unit * 0.09
        ctx.drawLayer { l in
            if lit { l.addFilter(.shadow(color: led.color.opacity(0.9), radius: m.unit * 0.06)) }
            switch legend {
            case .single(let s):
                let size = s.count == 1 ? m.unit * 0.27 : m.unit * 0.17
                l.draw(Text(s).font(.system(size: size, weight: .medium)).foregroundStyle(ink),
                       at: CGPoint(x: face.minX + pad, y: face.minY + pad * 0.6), anchor: .topLeading)
            case .centered(let s):
                l.draw(Text(s).font(.system(size: m.unit * 0.28, weight: .medium)).foregroundStyle(ink),
                       at: CGPoint(x: face.midX, y: face.midY), anchor: .center)
            case .stacked(let upper, let lower):
                let font = Font.system(size: m.unit * 0.23, weight: .medium)
                l.draw(Text(upper).font(font).foregroundStyle(ink),
                       at: CGPoint(x: face.minX + pad, y: face.minY + pad * 0.4), anchor: .topLeading)
                l.draw(Text(lower).font(font).foregroundStyle(ink),
                       at: CGPoint(x: face.minX + pad, y: face.maxY - pad * 0.4), anchor: .bottomLeading)
            case .none:
                break
            }
        }
    }

    /// Outline of a key, shrunk by `inset` on every side; `front`/`back` override the bottom/top insets.
    private func capPath(_ key: KeyInfo, _ m: Metrics, inset: Double, front: Double? = nil, back: Double? = nil) -> Path {
        let f = front ?? inset, bk = back ?? inset
        let radius = m.unit * max(0.04, 0.12 - inset * 0.4)
        switch key.shape {
        case .rect:
            let r = m.rect(x: key.x + inset, y: key.y + bk, w: key.width - 2 * inset, h: key.height - bk - f)
            return Path(roundedRect: r, cornerRadius: radius)
        case .isoEnter:
            // Union of the 1.5u top part and the 1.25u lower part, both flush right.
            var p = Path()
            p.addRoundedRect(in: m.rect(x: key.x - 0.25 + inset, y: key.y + bk,
                                        w: key.width + 0.25 - 2 * inset, h: 1 - bk - inset),
                             cornerSize: CGSize(width: radius, height: radius))
            p.addRoundedRect(in: m.rect(x: key.x + inset, y: key.y + bk,
                                        w: key.width - 2 * inset, h: key.height - bk - f),
                             cornerSize: CGSize(width: radius, height: radius))
            return p
        }
    }
}

/// What's printed on each cap of the One 2 TKL (US ANSI legends, plus the two ISO extras).
enum KeyLegend: Equatable {
    case none
    case single(String)
    case centered(String)
    case stacked(String, String)

    var isEmpty: Bool { self == .none }

    static func `for`(_ label: String) -> KeyLegend {
        if let pair = shifted[label] { return .stacked(pair.0, pair.1) }
        switch label {
        case "Space": return .none
        case "Up": return .centered("↑")
        case "Down": return .centered("↓")
        case "Left": return .centered("←")
        case "Right": return .centered("→")
        case "Left Shift", "Right Shift": return .single("Shift")
        case "Left Ctrl", "Right Ctrl": return .single("Ctrl")
        case "Left Win/Cmd", "Right Win/Cmd": return .single("Win")
        case "Left Alt/Opt", "Right Alt/Opt": return .single("Alt")
        case "Insert": return .single("Ins")
        case "Delete": return .single("Del")
        default: return .single(label)
        }
    }

    private static let shifted: [String: (String, String)] = [
        "`": ("~", "`"), "1": ("!", "1"), "2": ("@", "2"), "3": ("#", "3"), "4": ("$", "4"),
        "5": ("%", "5"), "6": ("^", "6"), "7": ("&", "7"), "8": ("*", "8"), "9": ("(", "9"),
        "0": (")", "0"), "-": ("_", "-"), "=": ("+", "="), "[": ("{", "["), "]": ("}", "]"),
        "\\": ("|", "\\"), ";": (":", ";"), "'": ("\"", "'"), ",": ("<", ","), ".": (">", "."),
        "/": ("?", "/"), "ISO #": ("~", "#"), "ISO \\": ("|", "\\"),
    ]
}

extension RGB {
    /// Rough perceived brightness, 0...1.
    var luminance: Double { (0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)) / 255 }
}
