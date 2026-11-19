# Roadmap

Each milestone ends with something the user can try on the real keyboard.

## M0 — Hardware bring-up (do this first)
Done 2026-11-19, except the Python step and Mac sleep.
- [x] `scripts/probe-usb.sh`: confirm PID `0x0356` (RGB TKL).
- [ ] ~~`python3 tools/ducky.py list` then `solid ff0080`, `rainbow`, `release`.~~ Skipped: the Swift build worked straight away, so this pre-Swift check wasn't needed. `hidapi` isn't installed. Run it if `tools/ducky.py` ever needs re-verifying.
- [x] `swift build` and `swift test`. Two fixes: `KeyPress` clashed with `SwiftUI.KeyPress`, and `DuckyDevice` is now `@unchecked Sendable`. Tests need Xcode's toolchain (see CLAUDE.md).
- [x] `swift run duckyctl list`, confirm/fix the collection selection in `HIDTransport.open()`. Guess was right.
- [x] `swift run duckyctl solid 00ff00`, `effect "Rainbow Wave" 10`, `release`. The wave stuttered at 26 fps. Dropping the 2 ms packet gap gave ~95 fps and smooth motion. Added `duckyctl bench`.
- [x] Answer the open questions in `docs/RESEARCH.md` and record the answers there. Still open: does direct mode survive Mac sleep?

## M1 — Usable app (scaffold exists, polish it)
- [ ] `swift run DuckyLights`: sidebar of effects, live keyboard preview, palette, color pickers, speed/brightness.
- [ ] Click/drag to paint keys (Custom effect). Add an eyedropper and a "fill row/column" option.
- [ ] Make the preview look like the real board (dark case, keycap legends). Handle the ISO geometry (1.25u Left Shift, tall Enter) behind an ANSI/ISO setting.
- [ ] Handle hot-plug with `IOHIDManagerRegisterDeviceMatchingCallback` / removal callback (status updates, auto-reconnect).
- [ ] Release on quit, sleep and screen lock. Optionally release when the app is in the background.

## M2 — Proper macOS app packaging
- [ ] Move to an Xcode project (or XcodeGen `project.yml`) for a real `.app`: bundle ID, icon, Info.plist, no sandbox (or the USB entitlement).
- [ ] Menu-bar extra (`MenuBarExtra`) with quick effect switching, so the main window can stay closed.
- [ ] Launch at login (`SMAppService.mainApp`). Re-apply the last profile on launch and wake.

## M3 — Reactive effects
- [ ] Key-event source (see RESEARCH.md) feeding `AppModel.presses`. Add a mac keyCode → LED index table.
- [ ] Reactive, Ripple, and a "typing heatmap" effect.

## M4 — Profiles & extras
- [ ] Named profiles (effect + settings + paint) saved as JSON in Application Support. Import/export.
- [ ] More effects: gradient, Snake, Laser, audio-reactive (system audio needs ScreenCaptureKit), CPU-load bar on the F-row, notification flashes.
- [ ] A small local API or URL scheme (`duckylights://effect/wave`) for Shortcuts/Raycast.

## M5 — Firmware modes (research, optional)
Goal: select the keyboard's own modes (which keep running without the app) and write CM1/CM2 to flash.
- [ ] Windows VM (UTM/Parallels) with DuckyRGB plus USB passthrough, or a Windows PC. Capture with Wireshark + USBPcap.
- [ ] Change one setting at a time (mode, speed, brightness, color, CM record) and diff the captures.
- [ ] Add the decoded commands to `docs/PROTOCOL.md` and `tools/ducky.py` first, then Swift.
- [ ] Risk: writing profile/flash data wrongly could need a factory reset (hold both Win keys for 3 s). Don't touch firmware-update commands.
