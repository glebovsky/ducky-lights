# Ducky One 2 RGB — USB lighting protocol (per-key / "direct" mode)

Unofficial. Pieced together from three independent reverse-engineering efforts that agree byte-for-byte (see `RESEARCH.md` for sources). The reference implementation is `tools/ducky.py`; the Swift encoder (`Sources/DuckyKit/DuckyProtocol.swift`) is tested against vectors it generates.

## Device

| | |
|---|---|
| Vendor ID | `0x04D9` (Holtek — shared with many other devices, so always also check the product ID) |
| Product ID, **One 2 RGB TKL** | `0x0356` |
| Product ID, One 2 RGB full-size / Shine 7 | `0x0348` (same protocol, 132-slot matrix) |
| Lighting interface | USB interface **1** (interface 0 is the normal keyboard) |
| Transport | HID **output reports**, report ID `0`, **64-byte** payload |
| Pacing | No extra gap needed. Each output report write blocks ~1 ms (one USB frame), so a 10-packet frame takes ~10 ms (~95 fps). Verified on hardware 2026-11-19 with a 30 s soak (28k writes, no stalls, no garbled frames). OpenRGB and DuckySharp sleep 2 ms per packet, which gives ~26 fps and visible stutter. |

On macOS there is no "interface number" property on `IOHIDDevice`. `HIDTransport` picks the collection with a known PID, a vendor-defined usage page (≥ `0xFF00`) and a max output report size ≥ 64. Confirmed on hardware: the board exposes three collections, keyboard (`0x01/0x06`, out 1), system control (`0x01/0x80`, out 1) and lighting (`0xFF00/0x01`, out 64, in 64).

Single-color models (e.g. DKON1887S, white/blue LEDs) have no per-key RGB and are almost certainly not supported.

## Packets

All packets are 64 bytes, zero-padded. Offsets below are within the 64-byte payload (hidapi users prepend a `0x00` report ID byte, making 65).

### Enter direct mode — `41 01`
Takes over lighting. Firmware effects stop. Send once per session.

### Exit direct mode — `41 00`
Hands lighting back to the firmware; the previously active hardware mode resumes. **Always send this on quit / sleep.** OpenRGB never sends it, and its users report that Fn shortcuts and macros stop working while OpenRGB holds the keyboard (OpenRGB issue #2202). That's consistent with direct mode suspending Fn handling, but not yet confirmed.

### One frame = 10 packets

```
#0  begin    56 81 00 00 01 00 00 00 08 00 00 00 AA AA AA AA
#1  data 0   56 83 00 00 01 00 00 00 80 01 00 C1 00 00 00 00 FF FF FF FF 00 00 00 00 [stream 0..39]
#2  data 1   56 83 01 00 [stream 40..99]
#3  data 2   56 83 02 00 [stream 100..159]
 …
#8  data 7   56 83 07 00 [stream 400..459]
#9  apply    51 28 00 00 FF
```

- `08` in the begin packet = number of data packets. duckylights' notes suggest the `AA AA AA AA` is a mask that keeps the lock-indicator LEDs out of it.
- The **stream** is 460 bytes = 153 LED slots of `R G B`. LED index *i* lives at bytes `3i, 3i+1, 3i+2`. Triplets **straddle packet boundaries**. For example, index 13's R is the last byte of data packet 0 and its G,B open data packet 1. The encoder treats the stream as one continuous buffer, so this falls out naturally.
- Unused slots should be zero.
- The full-size and TKL boards use the same index scheme. The TKL just skips the numpad and media slots (108 slots span the TKL keys).

### Replies
The keyboard answers each packet with an input report echoing the command (duckylights reads one after every write; OpenRGB ignores them). Not reading them works, per OpenRGB. `tools/ducky.py --read …` prints them, which is useful for debugging.

## LED index map (TKL)

The full table with labels is in `Resources/ducky-one2-tkl-leds.json`. Geometry for drawing is in `Sources/DuckyKit/DuckyOne2TKLLayout.swift`. Indices run **roughly column-major**, in blocks of 6 per electrical column, but the electrical columns don't line up perfectly with the physical ones. Always use the table, never compute an index.

```
row\col  0   1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16  17  18
F-row    0   .  12  18  24  30   .  42  48  54  60   .  66  72  78  84  90  96 102
Number   1   7  13  19  25  31  37  43  49  55  61   .  67  73  85   .  91  97 103
QWERTY   2   .   8  14  20  26   .  32  38  44  50  56  62  68  74  86  92  98 104
Home     3   .   9  15  21  27   .  33  39  45  51  57  63  69  75  87   .   .   .
Shift    4  10  16  22  28  34   .  40   .  46  52  58  64  70  82   .   .  100   .
Bottom   5  11  17   .   .   .   .  41   .   .   .   .  65  77  83  89  95 101 107
```

Notable: Esc=0, Caps=3, Space=41, Enter(ANSI)=87, Backspace=85, `\`(ANSI)=86, ISO `#`=75, ISO `\`=10, Fn=83, arrows ←=95 ↑=100 ↓=101 →=107.

## Firmware ("hardware") modes — not controllable yet

The official Windows software (DuckyRGB) uploads a mode table to the keyboard. DuckySharp replays a captured upload as its "release" sequence: packets `56 02 NN 00 …` that each carry a mode ID and an ASCII name. Decoded, that table is:

| # | name | | # | name |
|---|---|---|---|---|
| 0x00 | Off | | 0x0C | Random |
| 0x01 | Static All | | 0x0D | Random R |
| 0x02 | Static List | | 0x0E | Rain |
| 0x03 | Breath | | 0x0F | Rain v2 |
| 0x04 | Color Cycle | | 0x10 | Single |
| 0x05 | Wave | | 0x11 | Single Rand |
| 0x06 | Triangle | | 0x12 | Laser |
| 0x07 | Snake | | 0x13 | Ripple v2 |
| 0x08 | Snake v2 | | 0x14 | Swirl Active |
| 0x09 | Snake Stack | | 0x15 | Ram List |
| 0x0A | Snake Cover | | 0x16 | Factory |
| 0x0B | Swirl Passive | | | |

Other commands seen in captures (duckylights' notebook) but not decoded: `12 xx` (get info), `40 20`, `40 63` and `52 xx` (per-profile reads, 6 profiles), `42 xx`, `51 00`/`51 01`, `56 15`/`56 21` (profile data), `56 42` (music-equalizer stream). Selecting a firmware mode, setting its speed/brightness/color, and writing CM1/CM2 to flash all need fresh USB captures of DuckyRGB (see ROADMAP M5).
