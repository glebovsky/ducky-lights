#if canImport(IOKit)
import Foundation
import IOKit
import IOKit.hid

/// One HID top-level collection exposed by the keyboard. A USB interface can expose
/// several; macOS has no direct "interface number" property, so we pick by usage page.
public struct HIDCandidate: CustomStringConvertible {
    public let device: IOHIDDevice
    public let productID: Int
    public let product: String
    public let usagePage: Int
    public let usage: Int
    public let maxOutputReportSize: Int
    public let maxInputReportSize: Int
    public let locationID: Int

    public var isVendorDefined: Bool { usagePage >= 0xFF00 }

    /// The collection that takes lighting packets: known PID, vendor-defined page, 64-byte output.
    /// Confirmed on a One 2 RGB TKL: `0xFF00/0x0001`, out 64, in 64.
    public var isLightingInterface: Bool {
        DuckyProtocol.knownProducts[productID] != nil && isVendorDefined
            && maxOutputReportSize >= DuckyProtocol.reportLength
    }

    init(_ d: IOHIDDevice) {
        func int(_ key: String) -> Int { (IOHIDDeviceGetProperty(d, key as CFString) as? Int) ?? 0 }
        func str(_ key: String) -> String { (IOHIDDeviceGetProperty(d, key as CFString) as? String) ?? "" }
        device = d
        productID = int(kIOHIDProductIDKey)
        product = str(kIOHIDProductKey)
        usagePage = int(kIOHIDPrimaryUsagePageKey)
        usage = int(kIOHIDPrimaryUsageKey)
        maxOutputReportSize = int(kIOHIDMaxOutputReportSizeKey)
        maxInputReportSize = int(kIOHIDMaxInputReportSizeKey)
        locationID = int(kIOHIDLocationIDKey)
    }

    public var description: String {
        String(format: "%04x:%04x \"%@\" usagePage=0x%04x usage=0x%04x out=%d in=%d loc=0x%08x%@",
               DuckyProtocol.vendorID, productID, product, usagePage, usage,
               maxOutputReportSize, maxInputReportSize, locationID,
               isVendorDefined ? "  <- vendor-defined" : "")
    }
}

public enum HIDError: Error, CustomStringConvertible {
    case notFound
    case openFailed(IOReturn)
    case writeFailed(IOReturn)

    public var description: String {
        switch self {
        case .notFound: return "Ducky keyboard lighting interface not found (is it the RGB model? try `duckyctl list`)"
        case .openFailed(let r): return String(format: "IOHIDDeviceOpen failed: 0x%08x", r)
        case .writeFailed(let r): return String(format: "IOHIDDeviceSetReport failed: 0x%08x", r)
        }
    }
}

/// Minimal IOKit HID transport: find the Ducky lighting collection and send 64-byte output reports.
///
/// Not thread-safe; `DuckyDevice` serializes access on its own queue.
public final class HIDTransport {
    private let manager: IOHIDManager
    private var device: IOHIDDevice?
    public private(set) var selected: HIDCandidate?

    public init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: DuckyProtocol.vendorID] as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    deinit {
        if onEvent != nil {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        }
        close()
    }

    /// Every HID collection with the Ducky/Holtek vendor ID. Use for diagnostics.
    public func candidates() -> [HIDCandidate] {
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        return set.map(HIDCandidate.init).sorted { ($0.productID, $0.usagePage, $0.usage) < ($1.productID, $1.usagePage, $1.usage) }
    }

    /// Open the lighting collection (see `HIDCandidate.isLightingInterface`).
    public func open() throws {
        guard let c = candidates().first(where: \.isLightingInterface) else { throw HIDError.notFound }
        let r = IOHIDDeviceOpen(c.device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard r == kIOReturnSuccess else { throw HIDError.openFailed(r) }
        device = c.device
        selected = c
    }

    public var isOpen: Bool { device != nil }

    public enum Event: Sendable { case added, removed }
    private var onEvent: ((Event, HIDCandidate) -> Void)?

    /// Report every Ducky collection that appears or disappears, on the main run loop.
    /// Fires `.added` once for each collection already attached. Call once.
    public func startMonitoring(_ handler: @escaping (Event, HIDCandidate) -> Void) {
        onEvent = handler
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, device in
            guard let ctx else { return }
            let me = Unmanaged<HIDTransport>.fromOpaque(ctx).takeUnretainedValue()
            me.onEvent?(.added, HIDCandidate(device))
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, device in
            guard let ctx else { return }
            let me = Unmanaged<HIDTransport>.fromOpaque(ctx).takeUnretainedValue()
            me.onEvent?(.removed, HIDCandidate(device))
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    public func write(_ payload: [UInt8]) throws {
        guard let device else { throw HIDError.notFound }
        let r = payload.withUnsafeBufferPointer { buf in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(0), buf.baseAddress!, buf.count)
        }
        guard r == kIOReturnSuccess else { throw HIDError.writeFailed(r) }
    }

    public func close() {
        if let device { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        device = nil
        selected = nil
    }
}
#endif
