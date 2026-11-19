import XCTest
@testable import DuckyKit

final class ProtocolTests: XCTestCase {
    private func hex(_ p: [UInt8]) -> String { p.map { String(format: "%02x", $0) }.joined() }

    func testModePackets() {
        XCTAssertEqual(hex(DuckyProtocol.enterDirectMode()), GoldenVectors.enterDirect)
        XCTAssertEqual(hex(DuckyProtocol.exitDirectMode()), GoldenVectors.exitDirect)
    }

    func testSolidRedMatchesPythonReference() {
        let colors = Dictionary(uniqueKeysWithValues: DuckyOne2TKL.keys.map { ($0.ledIndex, RGB(255, 0, 0)) })
        XCTAssertEqual(DuckyProtocol.colorFrame(colors).map(hex), GoldenVectors.solidRed)
    }

    func testIndexPatternMatchesPythonReference() {
        var colors: [Int: RGB] = [:]
        for i in 0..<153 { colors[i] = RGB(UInt8(i), UInt8(255 - i), UInt8((i * 2) % 256)) }
        XCTAssertEqual(DuckyProtocol.colorFrame(colors).map(hex), GoldenVectors.indexPattern)
    }

    func testFrameShape() {
        let frame = DuckyProtocol.colorFrame([:])
        XCTAssertEqual(frame.count, 10)
        XCTAssertTrue(frame.allSatisfy { $0.count == 64 })
    }

    func testLayoutHasUniqueIndices() {
        let idx = DuckyOne2TKL.keys.map(\.ledIndex)
        XCTAssertEqual(Set(idx).count, idx.count)
        XCTAssertEqual(KeyLayout.one2TKL(.ansi).keys.count, 87)
        XCTAssertEqual(KeyLayout.one2TKL(.iso).keys.count, 88)
    }

    func testEffectsRenderEveryKey() {
        let layout = KeyLayout.one2TKL()
        for kind in EffectKind.allCases {
            let f = EffectRenderer.render(kind, layout: layout, settings: EffectSettings(), t: 1.234)
            XCTAssertEqual(f.count, layout.keys.count, "\(kind)")
        }
    }
}
