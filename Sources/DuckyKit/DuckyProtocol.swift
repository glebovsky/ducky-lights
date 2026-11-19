import Foundation

/// Byte-level encoder for the Ducky One 2 RGB per-key ("direct") lighting protocol.
/// Pure Foundation, no I/O. Reference: tools/ducky.py and docs/PROTOCOL.md.
///
/// Every packet is a 64-byte HID *output* report with report ID 0.
public enum DuckyProtocol {
    public static let vendorID = 0x04D9
    public static let knownProducts: [Int: String] = [
        0x0356: "Ducky One 2 RGB TKL",
        0x0348: "Ducky One 2 RGB / Shine 7",
    ]
    /// USB interface carrying the lighting endpoint.
    public static let ledInterface = 1
    public static let reportLength = 64
    /// 40 bytes in data packet 0 + 60 bytes in each of packets 1...7.
    public static let streamLength = 40 + 7 * 60
    public static let maxLEDSlots = streamLength / 3   // 153
    /// Extra delay between packets. `IOHIDDeviceSetReport` already blocks ~1 ms per packet
    /// (one USB frame), so 0 gives ~95 fps with clean frames on real hardware. OpenRGB and
    /// DuckySharp add 2 ms, which drops to ~26 fps and looks jerky. Measure with `duckyctl bench`.
    public static let interPacketDelay: TimeInterval = 0

    private static func pad(_ bytes: [UInt8]) -> [UInt8] {
        precondition(bytes.count <= reportLength)
        return bytes + [UInt8](repeating: 0, count: reportLength - bytes.count)
    }

    /// 0x41 0x01: take over lighting (firmware effects stop).
    public static func enterDirectMode() -> [UInt8] { pad([0x41, 0x01]) }

    /// 0x41 0x00: hand lighting back to the firmware. Always send before quitting/sleeping.
    public static func exitDirectMode() -> [UInt8] { pad([0x41, 0x00]) }

    /// Build the R,G,B stream from per-LED colors.
    public static func stream(from colors: [Int: RGB]) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: streamLength)
        for (idx, c) in colors where idx >= 0 && idx < maxLEDSlots {
            buf[3 * idx] = c.r; buf[3 * idx + 1] = c.g; buf[3 * idx + 2] = c.b
        }
        return buf
    }

    /// The 10 packets that paint one full frame: begin, 8 data packets, apply.
    public static func colorFrame(stream input: [UInt8]) -> [[UInt8]] {
        var s = Array(input.prefix(streamLength))
        s += [UInt8](repeating: 0, count: streamLength - s.count)

        var packets: [[UInt8]] = []
        packets.append(pad([0x56, 0x81, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
                            0x08, 0x00, 0x00, 0x00, 0xAA, 0xAA, 0xAA, 0xAA]))
        let firstHeader: [UInt8] = [0x56, 0x83, 0x00, 0x00,
                                    0x01, 0x00, 0x00, 0x00, 0x80, 0x01, 0x00, 0xC1,
                                    0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF,
                                    0x00, 0x00, 0x00, 0x00]
        packets.append(pad(firstHeader + s[0..<40]))
        for n in 1...7 {
            let start = 40 + (n - 1) * 60
            packets.append(pad([0x56, 0x83, UInt8(n), 0x00] + s[start..<start + 60]))
        }
        packets.append(pad([0x51, 0x28, 0x00, 0x00, 0xFF]))
        return packets
    }

    public static func colorFrame(_ colors: [Int: RGB]) -> [[UInt8]] {
        colorFrame(stream: stream(from: colors))
    }
}
