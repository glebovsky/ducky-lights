import XCTest
@testable import DuckyKit

final class ProfileTests: XCTestCase {
    private func sample() -> Profile {
        var s = EffectSettings()
        s.primary = RGB(0, 170, 255); s.background = RGB(0, 0, 25); s.speed = 1.5; s.brightness = 0.8
        for l in ["W", "A", "S", "D", "Esc", "ISO \\"] {
            if let k = DuckyOne2TKL.keys.first(where: { $0.label == l }) { s.paint[k.ledIndex] = RGB(255, 0, 128) }
        }
        return Profile(name: "Gaming", effect: .custom, settings: s)
    }

    func testRoundTrip() throws {
        let p = sample()
        let back = try ProfileFile.decode(ProfileFile.encode([p]))
        XCTAssertEqual(back.profiles, [p])
        XCTAssertEqual(back.skipped, [])
    }

    func testFileIsHumanReadable() throws {
        let json = String(decoding: ProfileFile.encode([sample()]), as: UTF8.self)
        XCTAssertTrue(json.contains("\"format\" : \"ducky-lights-profiles\""))
        XCTAssertTrue(json.contains("\"effect\" : \"Custom (paint keys)\""))
        XCTAssertTrue(json.contains("\"Esc\" : \"ff0080\""))
    }

    func testHandEditedFileWithMissingAndBadFields() throws {
        let json = """
        { "format": "ducky-lights-profiles", "version": 1, "profiles": [
          { "name": "Minimal", "effect": "Static", "color": "ff8000" },
          { "name": "Typo", "effect": "Rainbow Waves" },
          { "name": "Keys", "effect": "Custom (paint keys)", "paint": { "Esc": "ff0000", "Nope": "00ff00", "Q": "zzz" },
            "speed": 99, "brightness": -1 }
        ] }
        """
        let d = try ProfileFile.decode(Data(json.utf8))
        XCTAssertEqual(d.profiles.map(\.name), ["Minimal", "Keys"])
        XCTAssertEqual(d.profiles[0].settings.primary, RGB(255, 128, 0))
        XCTAssertEqual(d.profiles[0].settings.speed, 1)                    // default
        XCTAssertEqual(d.profiles[1].settings.paint, [0: RGB(255, 0, 0)])
        XCTAssertEqual(d.profiles[1].settings.speed, 3)                    // clamped
        XCTAssertEqual(d.profiles[1].settings.brightness, 0)               // clamped
        XCTAssertEqual(d.skipped.count, 3)                                 // bad effect, unknown key, bad color
    }

    func testRejectsOtherFiles() {
        XCTAssertThrowsError(try ProfileFile.decode(Data("{\"hello\": 1}".utf8)))
        XCTAssertThrowsError(try ProfileFile.decode(Data("""
            {"format":"ducky-lights-profiles","version":99,"profiles":[]}
            """.utf8)))
    }

    func testStoreNamesImportsAndPersists() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("profiles.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        var store = ProfileStore(url: url)
        try store.load()
        XCTAssertEqual(store.profiles, [])

        let a = store.add(name: "Gaming", effect: .wave, settings: EffectSettings())
        let b = store.add(name: "gaming", effect: .staticColor, settings: EffectSettings())
        XCTAssertEqual(b.name, "gaming 2")
        store.rename(b.id, to: "Work")
        let imported = store.importProfiles([a])   // same id + name as an existing one
        XCTAssertNotEqual(imported[0].id, a.id)
        XCTAssertEqual(imported[0].name, "Gaming 2")
        store.move(fromOffsets: [2], toOffset: 0)
        XCTAssertEqual(store.profiles.map(\.name), ["Gaming 2", "Gaming", "Work"])
        try store.save()

        var again = ProfileStore(url: url)
        try again.load()
        XCTAssertEqual(again.profiles, store.profiles)
    }

    func testDiffersOnlyOnSettingsTheEffectUses() {
        let p = Profile(name: "S", effect: .staticColor, settings: EffectSettings())
        var s = p.settings
        s.speed = 2                                   // Static ignores speed
        XCTAssertFalse(p.differs(effect: .staticColor, settings: s))
        s.primary = RGB(1, 2, 3)
        XCTAssertTrue(p.differs(effect: .staticColor, settings: s))
        XCTAssertTrue(p.differs(effect: .wave, settings: p.settings))
    }
}
