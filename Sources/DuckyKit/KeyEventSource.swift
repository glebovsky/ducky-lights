#if canImport(IOKit)
import Foundation
import IOKit
import IOKit.hid

/// Key-down events from the Ducky's own keyboard interface, as LED indices.
///
/// Listens without seizing the device, so typing works as normal. Only the Ducky is
/// watched: typing on another keyboard doesn't light it. Needs the Input Monitoring
/// permission (System Settings › Privacy & Security). Callbacks run on the main thread.
public final class KeyEventSource {
    public enum Access: Sendable { case granted, denied, unknown }

    public static var access: Access {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: return .granted
        case kIOHIDAccessTypeDenied: return .denied
        default: return .unknown
        }
    }

    /// Show the system prompt (first time only; afterwards macOS just returns the answer).
    @discardableResult
    public static func requestAccess() -> Bool { IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }

    private var manager: IOHIDManager?
    private var onKeyDown: ((Int) -> Void)?

    public init() {}

    deinit { stop() }

    public var isRunning: Bool { manager != nil }

    /// Start listening. Throws `HIDError.openFailed(kIOReturnNotPermitted)` without permission.
    public func start(_ onKeyDown: @escaping (Int) -> Void) throws {
        guard manager == nil else { return }
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let devices = DuckyProtocol.knownProducts.keys.map { pid -> [String: Any] in
            [kIOHIDVendorIDKey: DuckyProtocol.vendorID, kIOHIDProductIDKey: pid,
             kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard]
        }
        IOHIDManagerSetDeviceMatchingMultiple(m, devices as CFArray)
        IOHIDManagerSetInputValueMatching(m, [kIOHIDElementUsagePageKey: HIDKeyMap.keyboardUsagePage] as CFDictionary)
        self.onKeyDown = onKeyDown
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(m, { ctx, _, _, value in
            guard let ctx else { return }
            let element = IOHIDValueGetElement(value)
            // Value 1 = pressed, 0 = released. Usages outside the key range (rollover
            // errors, 0xFFFFFFFF from array elements) don't map to an LED and are dropped.
            guard IOHIDValueGetIntegerValue(value) == 1,
                  let led = HIDKeyMap.ledIndex(usage: Int(IOHIDElementGetUsage(element))) else { return }
            Unmanaged<KeyEventSource>.fromOpaque(ctx).takeUnretainedValue().onKeyDown?(led)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let r = IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        guard r == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            self.onKeyDown = nil
            throw HIDError.openFailed(r)
        }
        manager = m
    }

    public func stop() {
        guard let m = manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = nil
        onKeyDown = nil
    }
}
#endif
