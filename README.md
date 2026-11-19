# Ducky Lights

A macOS app for the **Ducky One 2 RGB TKL**. Pick colors from a palette, paint individual keys, and run animations (wave, breathing, radar, raindrop, …) with a live on-screen preview of the keyboard.

> Status: M0 and M1 done (see `docs/ROADMAP.md`). The app runs from `swift run`. Packaging it as a real `.app` is next (M2).

## Try it in 2 minutes (before any Swift)

```bash
cd ~/stuff/ducky-lights
bash scripts/probe-usb.sh                 # want ProductID 0x356 (RGB TKL)
python3 -m pip install --user hidapi
python3 tools/ducky.py list
python3 tools/ducky.py solid ff0080       # whole board pink
python3 tools/ducky.py key Esc 00ff00     # just Esc green
python3 tools/ducky.py rainbow --seconds 10
python3 tools/ducky.py release            # back to the keyboard's own lighting
```

If `solid` works, the app will work.

## The app

A window with effects, a live preview of the board and paint tools (brush, eraser, eyedropper, fill row/column), plus a duck in the menu bar for quick switching. It hands lighting back to the keyboard on quit, sleep and screen lock, and picks the keyboard up again when it's replugged.


```bash
swift run DuckyLights      # SwiftUI app
swift run duckyctl list    # CLI for debugging
swift test
```

## How it works

The keyboard has a "direct mode": the Mac streams a full frame of per-key colors (10 USB HID packets) and the keyboard shows it. The app renders effects itself, about 30 times a second. The keyboard's **built-in** modes (the ones Fn+F10 cycles through) can't be selected from the Mac yet, because that part of the protocol hasn't been reverse-engineered. While the app is in control, Fn lighting shortcuts may not respond. Click **Release to keyboard**, or quit the app, to hand control back.

Details: [`docs/PROTOCOL.md`](docs/PROTOCOL.md) · [`docs/RESEARCH.md`](docs/RESEARCH.md) · [`docs/ROADMAP.md`](docs/ROADMAP.md)

## Credits

The protocol knowledge comes from [OpenRGB](https://gitlab.com/CalcProgrammer1/OpenRGB) (Ducky controller by Adam Honse), [duckylights](https://github.com/PascalDutch/duckylights) and [DuckySharp](https://github.com/voximity/DuckySharp). No code was copied. The LED index table is derived from OpenRGB's.
