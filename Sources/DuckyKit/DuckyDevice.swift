#if canImport(IOKit)
import Foundation

/// High-level device: direct-mode session + frame sending, serialized on a private queue.
/// Safe to share across threads: all transport access goes through `queue`.
public final class DuckyDevice: @unchecked Sendable {
    private let transport = HIDTransport()
    private let queue = DispatchQueue(label: "ducky.hid")
    public private(set) var inDirectMode = false

    public init() {}

    public var selected: HIDCandidate? { transport.selected }
    public func candidates() -> [HIDCandidate] { transport.candidates() }

    public func connect() throws {
        try queue.sync { if !transport.isOpen { try transport.open() } }
    }

    /// Take over lighting. Firmware effects and (reportedly) Fn shortcuts pause until `release()`.
    public func beginDirectMode() throws {
        try queue.sync {
            try send(DuckyProtocol.enterDirectMode())
            inDirectMode = true
        }
    }

    /// Send one full frame. Blocks ~20 ms (10 packets with 2 ms gaps) on the HID queue.
    public func show(_ colors: [Int: RGB]) throws {
        try queue.sync {
            if !inDirectMode {
                try send(DuckyProtocol.enterDirectMode())
                inDirectMode = true
            }
            for p in DuckyProtocol.colorFrame(colors) { try send(p) }
        }
    }

    /// Hand lighting back to the keyboard firmware. Call on quit, sleep, and app deactivation
    /// if the user prefers hardware effects.
    public func release() {
        queue.sync {
            if transport.isOpen { try? send(DuckyProtocol.exitDirectMode()) }
            inDirectMode = false
        }
    }

    public func disconnect() {
        release()
        queue.sync { transport.close() }
    }

    private func send(_ p: [UInt8]) throws {
        try transport.write(p)
        if DuckyProtocol.interPacketDelay > 0 { Thread.sleep(forTimeInterval: DuckyProtocol.interPacketDelay) }
    }
}
#endif
