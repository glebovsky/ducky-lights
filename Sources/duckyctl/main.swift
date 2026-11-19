// duckyctl — hardware bring-up and debugging tool.
//
//   swift run duckyctl list                 # all HID collections with the Ducky vendor ID
//   swift run duckyctl solid ff0080         # whole board one color
//   swift run duckyctl key Esc 00ff00       # single key
//   swift run duckyctl effect "Rainbow Wave" 10
//   swift run duckyctl bench 2 5            # timing stats: 2 ms packet gap, 5 s
//   swift run duckyctl release              # back to firmware lighting
//   swift run duckyctl frame ff0000         # print packets (no hardware) — compare with tools/ducky.py
import Foundation
import DuckyKit

func die(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

let args = Array(CommandLine.arguments.dropFirst())
let layout = KeyLayout.one2TKL(.ansi)

func color(_ s: String) -> RGB {
    guard let c = RGB(hex: s) else { die("bad color \(s), expected RRGGBB") }
    return c
}

guard let cmd = args.first else {
    die("usage: duckyctl list | solid RRGGBB | key LABEL RRGGBB | effect NAME [seconds] | bench [delayMs] [seconds] | release | frame RRGGBB")
}

if cmd == "frame" {
    guard args.count == 2 else { die("usage: duckyctl frame RRGGBB") }
    let c = color(args[1])
    let colors = Dictionary(uniqueKeysWithValues: DuckyOne2TKL.keys.map { ($0.ledIndex, c) })
    for (i, p) in DuckyProtocol.colorFrame(colors).enumerated() {
        print("\(i): " + p.map { String(format: "%02x", $0) }.joined())
    }
    exit(0)
}

#if canImport(IOKit)
let device = DuckyDevice()

switch cmd {
case "list":
    let all = device.candidates()
    if all.isEmpty { print("No HID devices with vendor ID 0x04d9 found.") }
    all.forEach { print($0) }
    if (try? device.connect()) != nil, let s = device.selected {
        print("\nWould use: \(s)")
    }

case "solid":
    guard args.count == 2 else { die("usage: duckyctl solid RRGGBB") }
    do {
        try device.connect()
        let c = color(args[1])
        try device.show(Dictionary(uniqueKeysWithValues: layout.keys.map { ($0.ledIndex, c) }))
        print("OK. Run `duckyctl release` to give lighting back to the keyboard.")
    } catch { die("\(error)") }

case "key":
    guard args.count == 3, let k = layout.key(labeled: args[1]) else {
        die("usage: duckyctl key LABEL RRGGBB   labels: " + layout.keys.map(\.label).joined(separator: " "))
    }
    do {
        try device.connect()
        try device.show([k.ledIndex: color(args[2])])
    } catch { die("\(error)") }

case "effect":
    guard args.count >= 2, let kind = EffectKind(rawValue: args[1]) else {
        die("usage: duckyctl effect NAME [seconds]   names: " + EffectKind.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ", "))
    }
    let seconds = args.count > 2 ? Double(args[2]) ?? 10 : 10
    do {
        try device.connect()
        let start = Date()
        var frames = 0
        while Date().timeIntervalSince(start) < seconds {
            let t = Date().timeIntervalSince(start)
            try device.show(EffectRenderer.render(kind, layout: layout, settings: EffectSettings(), t: t))
            frames += 1
        }
        device.release()
        print(String(format: "%.1f fps", Double(frames) / seconds))
    } catch { device.release(); die("\(error)") }

case "bench":
    // Rainbow Wave frames sent straight through the transport, with timing stats for each
    // HID write and each frame. Use to tune `DuckyProtocol.interPacketDelay` and find stutter.
    let delayMs = args.count > 1 ? Double(args[1]) ?? 2 : 2
    let seconds = args.count > 2 ? Double(args[2]) ?? 5 : 5
    let transport = HIDTransport()
    do { try transport.open() } catch { die("\(error)") }
    var writes: [Double] = [], frames: [Double] = []
    func send(_ p: [UInt8]) throws {
        let a = Date()
        try transport.write(p)
        writes.append(Date().timeIntervalSince(a))
        if delayMs > 0 { Thread.sleep(forTimeInterval: delayMs / 1000) }
    }
    func stats(_ name: String, _ xs: [Double]) {
        let s = xs.sorted()
        guard let last = s.last else { return }
        func q(_ p: Double) -> Double { s[min(s.count - 1, Int(Double(s.count) * p))] * 1000 }
        print(String(format: "%@ n=%d min=%.2f p50=%.2f p95=%.2f p99=%.2f max=%.2f ms",
                     name, s.count, s[0] * 1000, q(0.5), q(0.95), q(0.99), last * 1000))
    }
    do {
        try send(DuckyProtocol.enterDirectMode())
        let start = Date()
        while Date().timeIntervalSince(start) < seconds {
            let f = Date()
            let colors = EffectRenderer.render(.wave, layout: layout, settings: EffectSettings(),
                                               t: f.timeIntervalSince(start))
            for p in DuckyProtocol.colorFrame(colors) { try send(p) }
            frames.append(Date().timeIntervalSince(f))
        }
        try send(DuckyProtocol.exitDirectMode())
    } catch {
        try? transport.write(DuckyProtocol.exitDirectMode())
        die("\(error)")
    }
    transport.close()
    print(String(format: "delay=%.1fms fps=%.1f", delayMs, Double(frames.count) / seconds))
    stats("write", writes)
    stats("frame", frames)

case "release":
    do { try device.connect() } catch { die("\(error)") }
    device.release()
    print("Released.")

default:
    die("unknown command \(cmd)")
}
#else
die("Hardware commands need macOS (IOKit).")
#endif
