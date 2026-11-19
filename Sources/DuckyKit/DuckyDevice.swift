#if canImport(IOKit)
import Foundation

/// High-level device: direct-mode session + frame sending, serialized on a private queue.
///
/// Safe to share across threads: all transport access goes through `queue`.
public final class DuckyDevice: @unchecked Sendable {
    private let transport = HIDTransport()
    private let queue = DispatchQueue(label: "ducky.hid")
    private var _inDirectMode = false
    private var shutDown = false

    public init() {}

    public var selected: HIDCandidate? { queue.sync { transport.selected } }
    public var inDirectMode: Bool { queue.sync { _inDirectMode } }
    public func candidates() -> [HIDCandidate] { queue.sync { transport.candidates() } }

    public func connect() throws {
        try queue.sync { if !transport.isOpen { try transport.open() } }
    }

    /// Take over lighting. Firmware effects and Fn lighting shortcuts pause until `release()`.
    /// Opens the device first if needed.
    public func beginDirectMode() throws {
        try queue.sync {
            guard !shutDown else { return }
            if !transport.isOpen { try transport.open() }
            try send(DuckyProtocol.enterDirectMode())
            _inDirectMode = true
        }
    }

    /// Send one full frame (~10 ms). Does nothing unless in direct mode, so a frame queued
    /// just before `release()` can't take the keyboard back. On a write error the device is
    /// closed; call `beginDirectMode()` again once it's back.
    public func show(_ colors: [Int: RGB]) throws {
        try queue.sync {
            guard _inDirectMode else { return }
            do {
                for p in DuckyProtocol.colorFrame(colors) { try send(p) }
            } catch {
                transport.close()
                _inDirectMode = false
                throw error
            }
        }
    }

    /// Hand lighting back to the keyboard firmware. Call on quit, sleep and lock.
    /// `force` sends the exit packet even if this process never entered direct mode
    /// (e.g. `duckyctl release` cleaning up after another process).
    public func release(force: Bool = false) {
        queue.sync {
            if transport.isOpen && (_inDirectMode || force) { try? send(DuckyProtocol.exitDirectMode()) }
            _inDirectMode = false
        }
    }

    /// Release for good (app quitting): later `beginDirectMode()` calls do nothing.
    public func shutdown() {
        queue.sync { shutDown = true }
        release()
    }

    public func disconnect() {
        release()
        queue.sync { transport.close() }
    }

    public enum ConnectionEvent: Sendable { case appeared, disappeared }

    /// Watch the lighting interface being plugged in or removed. `handler` runs on the main
    /// thread, and fires `.appeared` right away if the keyboard is already attached.
    /// Direct mode does not survive a replug, so on `.appeared` call `beginDirectMode()` again.
    public func watchHotPlug(_ handler: @escaping @Sendable (ConnectionEvent) -> Void) {
        queue.sync {
            transport.startMonitoring { [weak self] event, candidate in
                guard candidate.isLightingInterface, let self else { return }
                switch event {
                case .added:
                    handler(.appeared)
                case .removed:
                    self.queue.sync {
                        self.transport.close()
                        self._inDirectMode = false
                    }
                    handler(.disappeared)
                }
            }
        }
    }

    private func send(_ p: [UInt8]) throws {
        try transport.write(p)
        if DuckyProtocol.interPacketDelay > 0 { Thread.sleep(forTimeInterval: DuckyProtocol.interPacketDelay) }
    }
}
#endif
