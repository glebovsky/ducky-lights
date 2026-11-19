# Ducky Lights — notes for Claude Code

A native macOS app (SwiftUI + IOKit HID) for controlling the per-key RGB lighting of the owner's **Ducky One 2 RGB TKL** keyboard (USB `04D9:0356`). Ducky ships no macOS software. Today the owner changes lighting only through Fn shortcuts (listed in `HardwareModesView`).

## Read first
- `docs/PROTOCOL.md`: the USB protocol (byte-level), LED index map, firmware mode table.
- `docs/RESEARCH.md`: sources, what's possible vs. not, **open questions to verify on hardware**.
- `docs/ROADMAP.md`: milestones. Start at **M0**.

## Layout
```
tools/ducky.py                    Python reference implementation (hidapi). Source of truth for packets.
Resources/ducky-one2-tkl-leds.json LED index → key label + matrix row/col (from OpenRGB)
Sources/DuckyKit/                 Library, no UI
  DuckyProtocol.swift             pure packet encoder (no I/O), tested against golden vectors
  DuckyOne2TKLLayout.swift        generated key geometry (x, y, width in 1u units)
  KeyLayout.swift, RGB.swift
  HIDTransport.swift              IOKit: find device, open, 64-byte output reports
  DuckyDevice.swift               direct-mode session, frame sending on a serial queue, hot-plug events
  Effects/Effects.swift           software effects (static, custom paint, breathing, wave, radar, …)
Sources/DuckyLights/              SwiftUI app (AppModel = 60 fps render/send loop + release holds)
  KeyboardView.swift              Canvas-drawn board, painting gestures, keycap legends
  MenuBar.swift                   menu bar duck (icon drawn in code) + its menu
Sources/duckyctl/                 CLI for bring-up: list / solid / key / effect / release / frame
Tests/DuckyKitTests/              XCTest; GoldenVectors.swift is generated
scripts/probe-usb.sh              identify the keyboard over USB
```

## Commands
```bash
swift build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test   # xcode-select points at CommandLineTools, which has no XCTest
swift run duckyctl list
swift run duckyctl solid ff0080
swift run duckyctl bench 0 5      # write/frame timing stats (packet gap ms, seconds)
swift run duckyctl release
swift run DuckyLights
.build/debug/DuckyLights --snapshot <dir>   # render preview PNGs offscreen, no hardware (no Screen Recording permission needed)
python3 tools/ducky.py vectors > Tests/DuckyKitTests/GoldenVectors.swift   # after any protocol change
```

## Status / caveats
- M1 done (2026-11-19), see ROADMAP. Next is **M2** (real `.app`, launch at login).
- M0 done (2026-11-19). Builds with Swift 6.2, tests pass, verified on the real board: solid colors, ~95 fps animation, release restores Fn shortcuts. Answers are in `docs/RESEARCH.md`.
- `tools/ducky.py` has not been run on this Mac (`hidapi` isn't installed). The golden vectors still match Swift.
- No extra gap between packets: each HID write already blocks ~1 ms. A 2 ms gap made animations stutter.
- Direct mode does not survive a USB replug. Mac sleep is untested.
- Built-in firmware modes **can't** be selected over USB yet. The app gets its animations by rendering frames itself in direct mode.

## Rules
- `DuckyDevice.show()` only sends while in direct mode (`beginDirectMode()` enters it). That way a frame queued behind a `release()` can't take the board back. Keep it that way.
- The app's window can't be screenshotted here (no Screen Recording permission). Use `--snapshot` to check visuals, and ask the owner for anything interactive.
- **Always release direct mode** (`DuckyProtocol.exitDirectMode`, `41 00`) on quit, sleep, crash paths you can catch, and when the user clicks "Release to keyboard". Leaving the board in direct mode reportedly disables Fn shortcuts.
- Protocol changes go into `tools/ducky.py` + `docs/PROTOCOL.md` first. Then regenerate the vectors and update Swift.
- Keep `DuckyProtocol` pure (no IOKit) so it stays unit-testable.
- Never send unknown or undocumented commands to the keyboard outside a deliberate M5 research session. Never touch firmware-update commands.
- Target macOS 14+, Swift 5.9+, no third-party dependencies unless there's a clear win.
- Testing on hardware is manual. Ask the owner to look at the keyboard and report back when a change affects what it shows.
