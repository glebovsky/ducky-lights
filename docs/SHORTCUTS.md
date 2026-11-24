# Ducky One 2 RGB TKL: built-in shortcuts

Everything here runs in the keyboard's firmware. None of it needs the app, and none of the lighting shortcuts respond while the app holds the board in direct mode. Use **Release to keyboard** first.

Source: Ducky's *One Series User Manual* (file `Ducky_One_One2_10in1_usermanual_ol.pdf` from duckychannel.com.tw, English part, pages 29–47; read 2026-11-24, not kept in the repo). Only the parts that apply to the One 2 **RGB** **TKL** are summarized here. Single-color, full-size and JIS details are in the PDF. The app shows the same data (`Sources/DuckyKit/FirmwareShortcuts.swift`): keep the two in sync.

**Status per row:** ✅ = checked on the owner's board, 📄 = from the manual only.

## Media: none by default

The One 2 has no media keys out of the box (the manual: multimedia keys "need to be recorded first before use"). Record them as macros on profile 2–6; see [Macros](#macros-ducky-macro-v20).

| Fn + Win + | Function | Fn + Win + | Function |
|---|---|---|---|
| A | Mute | M | Search |
| B | Volume up | N | Previous page (browser Back) |
| C | Volume down | O | Next page (browser Forward) |
| D | Play / pause | P | Mouse left click |
| E | Stop | Q | Mouse right click |
| F | Next track | R | Mouse middle click |
| G | Previous track | S / T | Mouse cursor up / down |
| H | Calculator | U / V | Mouse cursor left / right |
| I | My Computer | W / X | Mouse scroll up / down |
| J | Browser | | |
| K | Mail | | |
| L | Media player | | |

These letters only mean something while recording a macro (step 4 below). On a Mac, Calculator, My Computer, Mail and Search may do nothing. 📄

**Example: F5 = mute** (the manual's example D):
1. Fn + 2 (switch to profile 2; profile 1 is factory and can't hold macros).
2. Hold Fn + Ctrl for 3 s. Caps Lock flashes slowly.
3. Press F5 (the key that will trigger the macro). Caps Lock flashes fast.
4. Press Fn + Win + A, then Fn + Q ("press once to run").
5. Fn + Ctrl to finish (or Fn + Alt to record another key).

## Lighting (RGB)

| Shortcut | What it does | |
|---|---|---|
| Fn + F10 | Next mode: Wave → Alpha → Tetris → Color Cycle → Rain Drop → Circle Ripple → Random Reactive → Aurora → Reactive → Breathe → Full Backlit → Off | 📄 |
| Hold Fn + F10 (3 s) | All backlight off, including CM1 and CM2 | 📄 |
| Fn + ← / → | Slower / faster | 📄 |
| Fn + ↑ / ↓ | Brighter / dimmer (not in the manual's RGB table, but the board responds to it) | ✅ |
| Fn + F5 / F6 / F7 | Red / green / blue level, 10 steps each. Only in Aurora, Reactive, Breathe, Full Backlit | 📄 |
| Fn + F8 | Clear red, green and blue (same four modes) | 📄 |
| Fn + Space | Color palette: the board shows colors, press one and every key takes it (same four modes) | 📄 |
| Hold Fn + Alt + Ctrl (3 s) | Display mode: cycles through all the effects (showcase) | 📄 |

## Custom lighting (CM1 / CM2)

| Shortcut | What it does | |
|---|---|---|
| Fn + F11 / Fn + F12 | CM1 / CM2 on, press again for off | 📄 |
| Fn + PrtSc / Fn + Pause | Start recording CM1 / CM2 | 📄 |
| Caps Lock + F5 / F6 / F7 | While recording: set the red / green / blue of the current color | 📄 |
| Caps Lock + F8 | While recording: clear the color | 📄 |
| Caps Lock + Space | While recording: color palette | 📄 |
| Caps Lock + ScrLk | Stop recording and save | 📄 |

Recording: pick the color first (Caps Lock shows it), then press each key that should get it. Press a set key again to unset it. Thirty seconds with no change ends recording without saving. CM1 and CM2 can't run together or alongside other modes. 📄

## Macros (Ducky Macro V2.0)

| Shortcut | What it does | |
|---|---|---|
| Fn + 1 … 6 | Switch to profile 1–6. Caps Lock blinks the profile number. Profile 1 is factory and can't hold macros | 📄 |
| Hold Fn + Ctrl (3 s) | Start recording. Press the trigger key, then the output (keys, or Fn + Win + letter for media) | 📄 |
| Fn + Q / W / E | Run mode: once per press / toggle on and off / while held | 📄 |
| Fn + 1 … 6 (while recording) | Delay between recorded presses: 0.02 / 0.1 / 0.2 / 0.4 / 0.8 / 1 s. Without it, your own typing speed is recorded | 📄 |
| Fn + Ctrl | Finish recording | 📄 |
| Fn + Alt | Save this key and record another | 📄 |
| Hold Win + Space (3 s) | Clear all macros of the current profile | 📄 |

These **can't** be macro triggers: Fn, Fn + Esc, Fn + F1–F12, Fn + PrtSc, Fn + ScrLk, Fn + Pause, Fn + 0–9, Fn + Ctrl, Fn + Alt, Fn + Win, Fn + arrows, Fn + Space. Plain keys (F5, PgUp…) and other Fn + key combos can. 📄

## Other

| Shortcut | What it does | |
|---|---|---|
| Fn + ScrLk | Mouse keys on / off. The arrows and keys above them move and click | 📄 |
| Hold Fn + any Alt + any Win (3 s) | Win key lock on / off (default: Win works). Backlight flashes 3× | 📄 |
| Hold Fn + Esc (3 s) | USB repeat tuning on / off; then Fn + F1–F4 sets the repeat delay (1×, 2×, 4×, 8×), Fn + Alt + F1–F4 the repeat rate | 📄 |
| Hold Left Win + Right Win (3 s) | Factory reset (ANSI and ISO). Backlight flashes 3× | 📄 |
| Hold Right Alt + Space while plugging in | USB 3.0 power mode (default) | 📄 |
| Hold Left Alt + Space while plugging in | USB 2.0 power mode | 📄 |
| Hold Left Ctrl + Left Shift + Caps Lock while plugging in | Demo mode (lights only, sends no keys; 5 V supplies only) | 📄 |

## DIP switches (underside)

- **1–3:** where the Fn key is. Default OFF, OFF, OFF = right Fn next to the right Win. The PDF (page 40) has the full table: Fn can move to either Ctrl, Win or Alt.
- **4:** OFF = N-key rollover (default), ON = 6-key rollover (for KVMs). Unplug for 15 s after switching. Firmware updates need NKRO.
