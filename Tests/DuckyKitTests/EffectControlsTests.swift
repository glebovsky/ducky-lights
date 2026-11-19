import XCTest
@testable import DuckyKit

/// `EffectKind.controls` must list exactly the settings `EffectRenderer` reads:
/// changing a listed setting changes some frame, changing an unlisted one changes none.
final class EffectControlsTests: XCTestCase {
    private let layout = KeyLayout.one2TKL()
    /// Reactive/Ripple only draw around presses; feed a few so their colors show.
    private let presses = [KeyPress(ledIndex: 41, time: 0.2), KeyPress(ledIndex: 0, time: 0.6)]
    private let times = [0.3, 0.7, 1.1, 2.9]

    private func frames(_ kind: EffectKind, _ s: EffectSettings) -> [[Int: RGB]] {
        times.map { EffectRenderer.render(kind, layout: layout, settings: s, t: $0, presses: presses) }
    }

    private var base: EffectSettings {
        var s = EffectSettings()
        s.primary = RGB(200, 40, 10); s.background = RGB(0, 0, 30)
        s.speed = 1; s.brightness = 0.8
        s.paint = [0: RGB(1, 2, 3)]
        return s
    }

    private let tweaks: [(EffectControls, (inout EffectSettings) -> Void)] = [
        (.primary, { $0.primary = RGB(10, 220, 90) }),
        (.background, { $0.background = RGB(90, 0, 0) }),
        (.speed, { $0.speed = 2.3 }),
        (.brightness, { $0.brightness = 0.3 }),
        (.paint, { $0.paint = [0: RGB(250, 250, 0), 41: RGB(0, 250, 250)] }),
    ]

    func testControlsMatchRenderer() {
        for kind in EffectKind.allCases {
            let before = frames(kind, base)
            for (control, tweak) in tweaks {
                var s = base
                tweak(&s)
                let changed = frames(kind, s) != before
                XCTAssertEqual(changed, kind.controls.contains(control),
                               "\(kind.rawValue): \(control.rawValue) \(changed ? "changes output but isn't listed" : "is listed but changes nothing")")
            }
            var s = base
            s.secondary = RGB(1, 1, 1)
            XCTAssertEqual(frames(kind, s), before, "\(kind.rawValue) reads secondary; add it to EffectControls")
        }
    }
}
