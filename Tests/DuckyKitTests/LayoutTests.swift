import XCTest
@testable import DuckyKit

final class LayoutTests: XCTestCase {
    private let ansi = KeyLayout.one2TKL(.ansi)
    private let iso = KeyLayout.one2TKL(.iso)

    private func labels(_ keys: [KeyInfo]) -> Set<String> { Set(keys.map(\.label)) }

    func testISOGeometry() throws {
        let shift = try XCTUnwrap(iso.key(labeled: "Left Shift"))
        XCTAssertEqual(shift.width, 1.25)
        let enter = try XCTUnwrap(iso.key(labeled: "Enter"))
        XCTAssertEqual(enter.shape, .isoEnter)
        XCTAssertEqual(enter.height, 2)
        XCTAssertNotNil(iso.key(labeled: "ISO #"))
        XCTAssertNotNil(iso.key(labeled: "ISO \\"))
        XCTAssertNil(iso.key(labeled: "\\"))
        // ANSI keeps the generated shapes.
        XCTAssertEqual(ansi.key(labeled: "Left Shift")?.width, 2.25)
        XCTAssertEqual(ansi.key(labeled: "Enter")?.shape, .rect)
    }

    func testNoKeysOverlap() {
        for layout in [ansi, iso] {
            // Sample every key on a fine grid: each point must belong to at most one key.
            var x = 0.05
            while x < layout.width {
                var y = 0.05
                while y < layout.height {
                    let hits = layout.keys.filter { $0.contains(x: x, y: y) }
                    XCTAssertLessThanOrEqual(hits.count, 1, "overlap at (\(x), \(y)): \(hits.map(\.label))")
                    y += 0.1
                }
                x += 0.1
            }
        }
    }

    func testHitTesting() {
        XCTAssertEqual(ansi.key(atX: 0.5, y: 0.5)?.label, "Esc")
        XCTAssertEqual(ansi.key(atX: 8, y: 5.75)?.label, "Space")
        XCTAssertNil(ansi.key(atX: 1.5, y: 0.5)) // gap between Esc and F1
        // ISO Enter: top part reaches 13.5..15 on the QWERTY row, bottom part 13.75..15.
        XCTAssertEqual(iso.key(atX: 13.6, y: 2.5)?.label, "Enter")
        XCTAssertEqual(iso.key(atX: 14.5, y: 3.5)?.label, "Enter")
        XCTAssertEqual(iso.key(atX: 13.6, y: 3.5)?.label, "ISO #")
    }

    func testRowAndColumn() throws {
        let q = try XCTUnwrap(ansi.key(labeled: "Q"))
        let row = labels(ansi.row(of: q))
        XCTAssertTrue(row.isSuperset(of: ["Tab", "Q", "P", "\\", "PgDn"]))
        XCTAssertFalse(row.contains("A"))

        let esc = try XCTUnwrap(ansi.key(labeled: "Esc"))
        XCTAssertEqual(labels(ansi.column(of: esc)), ["Esc", "`", "Tab", "Caps Lock", "Left Shift", "Left Ctrl"])

        let up = try XCTUnwrap(ansi.key(labeled: "Up"))
        XCTAssertEqual(labels(ansi.column(of: up)), ["ScrLk", "Home", "End", "Up", "Down"])
    }
}
