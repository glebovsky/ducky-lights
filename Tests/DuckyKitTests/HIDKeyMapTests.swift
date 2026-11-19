import XCTest
@testable import DuckyKit

final class HIDKeyMapTests: XCTestCase {
    func testEveryMappedLabelExists() {
        let labels = Set(DuckyOne2TKL.keys.map(\.label))
        for (usage, label) in HIDKeyMap.labels {
            XCTAssertTrue(labels.contains(label), String(format: "usage 0x%02x -> unknown label %@", usage, label))
        }
    }

    func testEveryKeyExceptFnHasAUsage() {
        let mapped = Set(HIDKeyMap.labels.values)
        for key in DuckyOne2TKL.keys where key.label != "Fn" {
            XCTAssertTrue(mapped.contains(key.label), "no HID usage for \(key.label)")
        }
    }

    func testUsagesAreOneToOne() {
        XCTAssertEqual(Set(HIDKeyMap.labels.values).count, HIDKeyMap.labels.count)
    }

    func testSpotChecks() {
        XCTAssertEqual(HIDKeyMap.ledIndex(usage: 0x29), 0)    // Esc
        XCTAssertEqual(HIDKeyMap.ledIndex(usage: 0x2C), 41)   // Space
        XCTAssertEqual(HIDKeyMap.ledIndex(usage: 0x28), 87)   // Enter
        XCTAssertEqual(HIDKeyMap.ledIndex(usage: 0x52), 100)  // Up
        XCTAssertNil(HIDKeyMap.ledIndex(usage: 0x01))         // ErrorRollOver
        XCTAssertNil(HIDKeyMap.ledIndex(usage: 0x53))         // Num Lock: not on a TKL
    }
}
