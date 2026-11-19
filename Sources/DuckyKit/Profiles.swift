import Foundation

/// A named look: an effect plus everything it needs (colors, speed, brightness, painted keys).
/// The keyboard layout (ANSI/ISO) is not part of it; that's a fact about the hardware.
public struct Profile: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var effect: EffectKind
    public var settings: EffectSettings

    public init(id: UUID = UUID(), name: String, effect: EffectKind, settings: EffectSettings) {
        self.id = id; self.name = name; self.effect = effect; self.settings = settings
    }

    /// Whether `effect`/`settings` differ from what this profile saved, counting only the
    /// settings that effect uses (dragging Speed on Static doesn't make it "edited").
    public func differs(effect e: EffectKind, settings s: EffectSettings) -> Bool {
        guard e == effect else { return true }
        let c = effect.controls, a = settings
        if c.contains(.primary) && a.primary != s.primary { return true }
        if c.contains(.background) && a.background != s.background { return true }
        if c.contains(.speed) && a.speed != s.speed { return true }
        if c.contains(.brightness) && a.brightness != s.brightness { return true }
        if c.contains(.paint) && a.paint != s.paint { return true }
        return false
    }
}

/// The JSON format for the profile store and for import/export (same format for both, so an
/// exported file is always importable). Human-editable: hex colors, effects by name, painted
/// keys by label.
///
/// ```json
/// { "format": "ducky-lights-profiles", "version": 1,
///   "profiles": [ { "id": "…", "name": "Gaming", "effect": "Custom (paint keys)",
///                   "color": "00aaff", "background": "000019", "speed": 1, "brightness": 1,
///                   "paint": { "W": "ff0080", "A": "ff0080" } } ] }
/// ```
public enum ProfileFile {
    public static let format = "ducky-lights-profiles"
    public static let version = 1

    public enum Error: Swift.Error, CustomStringConvertible {
        case notAProfileFile
        case newerVersion(Int)

        public var description: String {
            switch self {
            case .notAProfileFile: return "This isn't a Ducky Lights profile file."
            case .newerVersion(let v): return "This file is from a newer Ducky Lights (format version \(v))."
            }
        }
    }

    /// What decoding found. `skipped` lists things that were dropped (unknown effect, key…).
    public struct Decoded {
        public var profiles: [Profile]
        public var skipped: [String]
    }

    private struct Document: Codable {
        var format: String
        var version: Int
        var profiles: [Entry]
    }

    private struct Entry: Codable {
        var id: UUID?
        var name: String
        var effect: String
        var color: String?
        var background: String?
        var speed: Double?
        var brightness: Double?
        var paint: [String: String]?
    }

    private static let labelByIndex = Dictionary(DuckyOne2TKL.keys.map { ($0.ledIndex, $0.label) }) { a, _ in a }
    private static let indexByLabel = Dictionary(DuckyOne2TKL.keys.map { ($0.label, $0.ledIndex) }) { a, _ in a }

    public static func encode(_ profiles: [Profile]) -> Data {
        let doc = Document(format: format, version: version, profiles: profiles.map { p in
            let s = p.settings
            let paint = Dictionary(s.paint.compactMap { i, c in labelByIndex[i].map { ($0, c.hex) } }) { a, _ in a }
            return Entry(id: p.id, name: p.name, effect: p.effect.rawValue, color: s.primary.hex,
                         background: s.background.hex, speed: s.speed, brightness: s.brightness,
                         paint: paint.isEmpty ? nil : paint)
        })
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? enc.encode(doc)) ?? Data()
    }

    public static func decode(_ data: Data) throws -> Decoded {
        guard let doc = try? JSONDecoder().decode(Document.self, from: data), doc.format == format else {
            throw Error.notAProfileFile
        }
        guard doc.version <= version else { throw Error.newerVersion(doc.version) }
        var out = Decoded(profiles: [], skipped: [])
        for e in doc.profiles {
            guard let effect = EffectKind(rawValue: e.effect) else {
                out.skipped.append("\"\(e.name)\": unknown effect \"\(e.effect)\"")
                continue
            }
            var s = EffectSettings()
            if let c = e.color.flatMap(RGB.init(hex:)) { s.primary = c }
            if let c = e.background.flatMap(RGB.init(hex:)) { s.background = c }
            if let v = e.speed { s.speed = min(3, max(0.1, v)) }
            if let v = e.brightness { s.brightness = min(1, max(0, v)) }
            for (label, hex) in e.paint ?? [:] {
                guard let i = indexByLabel[label], let c = RGB(hex: hex) else {
                    out.skipped.append("\"\(e.name)\": key \"\(label)\" = \"\(hex)\"")
                    continue
                }
                s.paint[i] = c
            }
            out.profiles.append(Profile(id: e.id ?? UUID(), name: e.name, effect: effect, settings: s))
        }
        return out
    }
}

/// Profiles kept in one JSON file (`ProfileFile` format). Not thread-safe; use from one place.
public struct ProfileStore {
    public let url: URL?
    public private(set) var profiles: [Profile] = []

    /// `url: nil` keeps everything in memory (previews, tests).
    public init(url: URL?) {
        self.url = url
    }

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Ducky Lights", isDirectory: true).appendingPathComponent("profiles.json")
    }

    /// Load from disk. A missing file is an empty store; a broken one throws (and is left alone).
    public mutating func load() throws {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { profiles = []; return }
        profiles = try ProfileFile.decode(Data(contentsOf: url)).profiles
    }

    public func save() throws {
        guard let url else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ProfileFile.encode(profiles).write(to: url, options: .atomic)
    }

    public func profile(_ id: UUID) -> Profile? { profiles.first { $0.id == id } }

    /// A name not used yet: "Gaming", then "Gaming 2", "Gaming 3", …
    public func uniqueName(_ base: String, excluding id: UUID? = nil) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = trimmed.isEmpty ? "Profile" : trimmed
        let taken = Set(profiles.filter { $0.id != id }.map { $0.name.lowercased() })
        if !taken.contains(root.lowercased()) { return root }
        var n = 2
        while taken.contains("\(root) \(n)".lowercased()) { n += 1 }
        return "\(root) \(n)"
    }

    @discardableResult
    public mutating func add(name: String, effect: EffectKind, settings: EffectSettings) -> Profile {
        let p = Profile(name: uniqueName(name), effect: effect, settings: settings)
        profiles.append(p)
        return p
    }

    public mutating func update(_ id: UUID, effect: EffectKind, settings: EffectSettings) {
        guard let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[i].effect = effect
        profiles[i].settings = settings
    }

    public mutating func rename(_ id: UUID, to name: String) {
        guard let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[i].name = uniqueName(name, excluding: id)
    }

    public mutating func delete(_ id: UUID) {
        profiles.removeAll { $0.id == id }
    }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().map { profiles[$0] }
        var rest = profiles.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        rest.insert(contentsOf: moving, at: max(0, min(insertAt, rest.count)))
        profiles = rest
    }

    /// Add imported profiles. They always get new IDs (importing twice gives two copies,
    /// never overwrites) and unique names. Returns what was added.
    @discardableResult
    public mutating func importProfiles(_ incoming: [Profile]) -> [Profile] {
        var added: [Profile] = []
        for var p in incoming {
            p.id = UUID()
            p.name = uniqueName(p.name)
            profiles.append(p)
            added.append(p)
        }
        return added
    }
}
