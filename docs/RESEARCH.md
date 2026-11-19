# Research notes

## What's possible on macOS today

| Capability | Status |
|---|---|
| Per-key static colors from the Mac | ✅ Known protocol (direct mode) |
| Animations (wave, breathing, ripple…) | ✅ Rendered by the app and streamed as frames. Measured ~95 fps max (10 packets × ~1 ms blocking write, no extra gap). They run only while the app runs. |
| Selecting the keyboard's **built-in** modes / speed / brightness from the Mac | ❌ Not reverse-engineered. Needs USB captures (ROADMAP M5). |
| Saving custom zones (CM1/CM2) to keyboard flash | ❌ Same, needs captures. |
| Fn shortcuts while the app is in control | ❌ Confirmed: Fn lighting shortcuts do nothing in direct mode. `41 00` brings them back. The app must release on quit, sleep, and on demand. |

There is no official macOS software. Ducky's DuckyRGB tool is Windows-only.

## Sources

- **OpenRGB, `Controllers/DuckyKeyboardController`** (GPL-2.0, Adam Honse, 2020). VID/PIDs, interface 1, the frame packets, and the TKL matrix plus LED names that `Resources/ducky-one2-tkl-leds.json` comes from. Mirror: https://github.com/CalcProgrammer1/OpenRGB (canonical: https://gitlab.com/CalcProgrammer1/OpenRGB). We reimplemented the protocol and copied no code.
- **OpenRGB issue #2202**: "Ducky One 2 RGB TKL stops responding to Fn-key and macros" while OpenRGB controls it. https://gitlab.com/CalcProgrammer1/OpenRGB/-/issues/2202
- **duckylights** (Python, GPL-2.0, PascalDutch). Wireshark captures of DuckyRGB in a VM, a protocol-analysis notebook, and the `41 01` / `41 00` enter/exit discovery. https://github.com/PascalDutch/duckylights
- **DuckySharp** (C#, MIT, voximity). Same frame format; documents the packet-boundary straddle; its release sequence contains the firmware mode-name table. https://github.com/voximity/DuckySharp
- Checked 2026-11-19 and found nothing new: `yizhang-paul/ducky_one_2_extreme_feedback` (Go, MIT, says it supports the One 2 TKL) has no HID code and calls a separate HTTP "engine". QMK has `ducky/one2mini` and `ducky/one2sf` but no One 2 TKL, and flashing QMK is a firmware replacement, which is out of scope.
- The user's own notes: `~/stuff/second-brain/Ducky One 2 TKL lighting.md` (Fn shortcuts and firmware modes).

## Open questions (answered on hardware, 2026-11-19, macOS 15, Apple silicon)

The original questions stay below with their answers.

1. **Is this keyboard the RGB model?** Run `scripts/probe-usb.sh`. You need PID `0x0356`. A single-color model can't do per-key colors.
   **Yes.** `system_profiler` shows `Ducky Keyboard`, VID `0x04d9`, PID `0x0356`, firmware version 1.10, full speed (12 Mb/s).
2. **Which IOHIDDevice collection is the lighting one on macOS?** `swift run duckyctl list` prints usage page, usage and report sizes for every collection. The guess is vendor-defined page (≥ `0xFF00`) with 64-byte output reports. Fix `HIDTransport.open()` if it's wrong.
   **The guess was right.** Three collections: `0x0001/0x0006` keyboard (out 1, in 8), `0x0001/0x0080` system control (out 1, in 31), `0xFF00/0x0001` vendor (out 64, in 64). `HIDTransport.open()` picks the vendor one. No change needed.
3. **Does opening it need Input Monitoring permission?** Vendor-defined collections normally don't. Keyboard collections do. If `IOHIDDeviceOpen` returns `kIOReturnNotPermitted` (0xE00002E2), that's why.
   **No prompt and no error** when `duckyctl` runs from a terminal. Re-check once the app ships as its own `.app` bundle (M2), since TCC permissions attach to the launching app.
4. **Do Fn shortcuts really stop in direct mode, and does `41 00` restore them?**
   **Yes to both.** With the board held green in direct mode, Fn+F10 and the brightness shortcuts did nothing. After `41 00` they worked again.
5. **Does the keyboard need its replies read?** OpenRGB doesn't read them and works. If frames start stalling after a while, add an input-report callback that drains them.
   **No.** A 30 s soak at ~95 fps (28,342 writes) never reading replies showed no stalls. Write latency p50 1.0 ms, p99 2.0 ms, max 6.8 ms.
6. **Max frame rate.** Try shorter inter-packet delays (1 ms, 0) and watch for dropped or garbled frames.
   **~95 fps with no inter-packet gap**, and frames looked clean. `IOHIDDeviceSetReport` blocks ~1 ms per packet already. The 2 ms gap borrowed from OpenRGB gave 26 fps with 31–43 ms frame jitter, and the owner saw it as jerky. `interPacketDelay` is now 0. Re-measure with `swift run duckyctl bench <delayMs> <seconds>`.
7. **Does `41 01` persist across USB re-enumeration or Mac sleep?** Presumably not, so on wake / replug the app must reconnect and re-enter direct mode.
   **Replug: no.** After unplugging a board held red, it came back in its own firmware lighting. The app must re-enter direct mode on reconnect (M1 hot-plug). **Mac sleep: not tested yet.**

## macOS implementation notes

- Use IOKit `IOHIDManager` / `IOHIDDeviceSetReport(kIOHIDReportTypeOutput, reportID 0, 64 bytes)`. No third-party dependency needed. (hidapi is fine too, and it's what `tools/ducky.py` uses.)
- **App Sandbox:** either disable it (simplest for a personal app) or enable it with the `com.apple.security.device.usb` entitlement. HID access from a sandboxed app is finicky, so start unsandboxed.
- Reactive effects need key-down events. Use `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` (needs **Accessibility** permission) or an `IOHIDManager` input callback on the keyboard collection (needs **Input Monitoring**). Map `keyCode` (macOS virtual key codes) to LED index with a lookup table.
- macOS keyboards report Cmd/Opt in the Win/Alt positions. The labels in the layout say "Win/Cmd", "Alt/Opt".
