import XCTest
@testable import DuckyKit

final class FirmwareShortcutsTests: XCTestCase {
    private let layouts = [KeyLayout.one2TKL(.ansi), KeyLayout.one2TKL(.iso)]

    func testEveryHighlightedKeyExists() {
        for layout in layouts {
            for s in FirmwareShortcuts.all {
                for label in s.highlight {
                    XCTAssertNotNil(layout.key(labeled: label), "\(s.keys): no key \"\(label)\"")
                }
            }
            for f in FirmwareShortcuts.MediaFunction.allCases {
                for t in FirmwareShortcuts.triggerKeys {
                    for step in FirmwareShortcuts.mediaSetup(f, trigger: t) {
                        for label in step.highlight {
                            XCTAssertNotNil(layout.key(labeled: label), "step \(step.id): no key \"\(label)\"")
                        }
                    }
                }
            }
        }
    }

    func testIDsAreUnique() {
        XCTAssertEqual(Set(FirmwareShortcuts.all.map(\.id)).count, FirmwareShortcuts.all.count)
    }

    func testMediaLettersMatchManual() {
        let letters = Dictionary(uniqueKeysWithValues: FirmwareShortcuts.MediaFunction.allCases.map { ($0.letter, $0) })
        XCTAssertEqual(letters["A"], .mute)
        XCTAssertEqual(letters["D"], .playPause)
        XCTAssertEqual(letters["G"], .previous)
        XCTAssertEqual(letters.count, 7)
    }

    func testSetupStepsNameTriggerAndLetter() {
        let steps = FirmwareShortcuts.mediaSetup(.playPause, trigger: "PgUp")
        XCTAssertTrue(steps.contains { $0.text.contains("PgUp") && $0.highlight == ["PgUp"] })
        XCTAssertTrue(steps.contains { $0.text.contains("Fn + Win + D") })
        XCTAssertEqual(steps.map(\.id), Array(1...steps.count))
    }
}
