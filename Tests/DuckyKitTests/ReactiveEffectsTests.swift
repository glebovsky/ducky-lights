import XCTest
@testable import DuckyKit

final class ReactiveEffectsTests: XCTestCase {
    private let layout = KeyLayout.one2TKL()
    private var settings: EffectSettings {
        var s = EffectSettings()
        s.primary = RGB(255, 255, 255); s.background = .black; s.speed = 1; s.brightness = 1
        return s
    }
    private func led(_ label: String) -> Int { layout.key(labeled: label)!.ledIndex }

    func testHeatmapHotterForMorePresses() {
        let e = led("E"), q = led("Q"), z = led("Z")
        let presses = (0..<20).map { KeyPress(ledIndex: e, time: Double($0) * 0.1) }
            + [KeyPress(ledIndex: q, time: 1)]
        let f = EffectRenderer.render(.heatmap, layout: layout, settings: settings, t: 3, presses: presses)
        XCTAssertEqual(f[e], EffectRenderer.heatColor(1), "most-typed key is the hottest color")
        XCTAssertGreaterThan(f[q]!.b, f[q]!.r, "rarely typed key is cool (blue-ish)")
        XCTAssertEqual(f[z], .black, "untouched key shows the background")
    }

    func testReactiveFadesBackToBackground() {
        let a = led("A")
        let p = [KeyPress(ledIndex: a, time: 1)]
        let fresh = EffectRenderer.render(.reactive, layout: layout, settings: settings, t: 1, presses: p)
        let later = EffectRenderer.render(.reactive, layout: layout, settings: settings, t: 3, presses: p)
        XCTAssertEqual(fresh[a], .white)
        XCTAssertEqual(later[a], .black)
    }

    func testLongHistoryStaysFast() {
        let keys = layout.keys.map(\.ledIndex)
        let presses = (0..<20_000).map { KeyPress(ledIndex: keys[$0 % keys.count], time: Double($0) * 0.05) }
        for kind in [EffectKind.heatmap, .ripple, .reactive] {
            let start = Date()
            _ = EffectRenderer.render(kind, layout: layout, settings: settings, t: 1000, presses: presses)
            // One 60 fps frame is 16 ms; leave most of it for everything else (debug build).
            XCTAssertLessThan(Date().timeIntervalSince(start), 0.010, "\(kind.rawValue) too slow")
        }
    }
}
