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

## M1 — Usable app
Done 2026-11-19 and checked on the board, except Mac sleep (not tried yet).
- [x] `swift run DuckyLights`: sidebar of effects, live keyboard preview, palette, color pickers, speed/brightness. Renders at 60 fps.
- [x] Click/drag to paint keys (Custom effect). Tools: brush, eraser, eyedropper, fill row, fill column. Hovering highlights the keys a click will change. Outside Custom the preview ignores clicks and the paint controls are disabled. That's the owner's call: clicks used to jump to Custom, and a draft-plus-Apply flow was tried and dropped.
- [x] Preview looks like the real board: dark case, LED light bleeding onto the plate, sculpted caps, shine-through legends (shifted symbols stacked). ANSI/ISO in Settings (1.25u Left Shift, tall Enter, `ISO #`/`ISO \`).
- [x] Hot-plug via IOHIDManager matching/removal callbacks. Unplug shows a status; replug resumes on its own.
- [x] Release on quit, Ctrl-C/SIGTERM, uncaught exceptions, sleep and screen lock (lock is a setting, on by default). Optional release while the app is in the background (off by default). Control comes back on wake/unlock/activate.
- [x] Menu bar duck (pulled forward from M2): open window, switch effects, release/take control, settings, quit. Closing the window keeps the app running in the menu bar.
- [ ] Check release + resume across Mac sleep on the real board.

## M2 — Proper macOS app packaging
Done 2026-11-19 and checked by the owner, except a real logout/login (not tried yet).
- [x] A real `.app` with no Xcode project: `scripts/build-app.sh [--install]` builds a release with SwiftPM, assembles the bundle from `Packaging/Info.plist` (`com.glebovsky.DuckyLights`, `LSUIElement`) and `Resources/AppIcon.icns`, signs it ad-hoc, and installs to /Applications. No sandbox. No permission prompts on the real board.
- [x] App icon: a rainbow-lit duck drawn in code (`AppIconView`), regenerated with `scripts/make-icon.sh`.
- [x] Menu-bar extra (`MenuBarExtra`) with quick effect switching, so the main window can stay closed. Done in M1. `LSUIElement` plus a Dock icon only while the window is open.
- [x] Launch at login (`SMAppService.mainApp`, toggle in Settings). "Open the window when the app starts" setting. Off means the app starts in the menu bar only, using `defaultLaunchBehavior(.suppressed)`, which is why the minimum is now macOS 15. The last effect is re-applied on launch, wake and replug. Settings saved by `swift run` builds carry over on first launch.
- [ ] Confirm the app really starts after logging out and back in.

## M3 — Reactive effects
Done 2026-11-19. The owner checked Reactive, Ripple, Heatmap and normal typing on the board. Not yet confirmed: that the built-in laptop keyboard doesn't trigger effects (by design only the Ducky's VID/PID is matched).
- [x] Key-event source: `KeyEventSource`, an IOHIDManager input-value callback on the Ducky's own keyboard collection (`0x01/0x06`). Not seized, so typing is unaffected, and only the Ducky counts. It maps HID usages to LED indices (`HIDKeyMap`, tested to cover every key except Fn, which the board never reports). Physical keys, so the macOS input layout doesn't matter. This needs Input Monitoring, used only while a typing effect is selected.
- [x] Reactive, Ripple, and Typing Heatmap (decaying per-key heat, cold-to-hot colors, a "Cool-down" slider, Reset). The renderer precomputes once per frame, so 20k presses of history render in a few ms.
- [x] Stable signing (`scripts/make-signing-cert.sh`) so Input Monitoring survives rebuilds. Ad-hoc signatures change every build.

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
