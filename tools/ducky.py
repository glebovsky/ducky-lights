#!/usr/bin/env python3
"""
Reference implementation of the Ducky One 2 RGB (TKL) per-key lighting protocol.

This is the source of truth for the Swift `DuckyKit` encoder: the Swift tests
compare against vectors produced by `python3 tools/ducky.py vectors`.

Usage (on the Mac, keyboard plugged in):
    python3 -m pip install --user hidapi
    python3 tools/ducky.py list                 # find the keyboard + its HID interfaces
    python3 tools/ducky.py solid ff0080         # whole board one color (direct mode)
    python3 tools/ducky.py key Esc 00ff00       # one key green, rest off
    python3 tools/ducky.py rainbow --seconds 10 # software rainbow wave
    python3 tools/ducky.py release              # hand lighting back to the keyboard firmware

    python3 tools/ducky.py frame ff0000         # print the 10 packets for a frame (no hardware)
    python3 tools/ducky.py vectors              # regenerate Tests golden vectors (no hardware)

See docs/PROTOCOL.md for the byte-level description.
"""
import argparse
import colorsys
import json
import math
import os
import sys
import time

VENDOR_ID = 0x04D9
PRODUCT_IDS = {
    0x0356: "Ducky One 2 RGB TKL",
    0x0348: "Ducky One 2 RGB / Shine 7 (full size)",
}
LED_INTERFACE = 1          # OpenRGB + duckylights both talk to interface 1
REPORT_LEN = 64            # payload bytes per HID output report (report ID 0 is prepended on write)
STREAM_LEN = 40 + 7 * 60   # 460 bytes of RGB data across 8 data packets (153 LED slots)
INTER_PACKET_DELAY = 0     # writes already block ~1 ms (one USB frame); OpenRGB/DuckySharp's extra 2 ms halves the frame rate. Measured with `duckyctl bench`.

HERE = os.path.dirname(os.path.abspath(__file__))
LED_TABLE = os.path.join(HERE, "..", "Resources", "ducky-one2-tkl-leds.json")


# --------------------------------------------------------------------------- packets
def _pad(b: bytes) -> bytes:
    assert len(b) <= REPORT_LEN, len(b)
    return b + bytes(REPORT_LEN - len(b))


def enter_direct_mode() -> bytes:
    """0x41 0x01 — 'programming'/direct mode on. Firmware effects stop."""
    return _pad(bytes([0x41, 0x01]))


def exit_direct_mode() -> bytes:
    """0x41 0x00 — direct mode off. Firmware lighting (and Fn shortcuts) resume."""
    return _pad(bytes([0x41, 0x00]))


def color_frame(stream: bytes) -> list:
    """Return the 10 packets that paint one frame.

    `stream` is R,G,B bytes in LED-index order (index i -> bytes 3i..3i+2).
    It is zero-padded to 460 bytes.
    """
    stream = bytes(stream)[:STREAM_LEN]
    stream = stream + bytes(STREAM_LEN - len(stream))
    pkts = [_pad(bytes([0x56, 0x81, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
                        0x08, 0x00, 0x00, 0x00, 0xAA, 0xAA, 0xAA, 0xAA]))]
    first_hdr = bytes([0x56, 0x83, 0x00, 0x00,
                       0x01, 0x00, 0x00, 0x00, 0x80, 0x01, 0x00, 0xC1,
                       0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF,
                       0x00, 0x00, 0x00, 0x00])           # 24 bytes, data starts at offset 24
    pkts.append(_pad(first_hdr + stream[0:40]))
    for n in range(1, 8):
        start = 40 + (n - 1) * 60
        pkts.append(_pad(bytes([0x56, 0x83, n, 0x00]) + stream[start:start + 60]))
    pkts.append(_pad(bytes([0x51, 0x28, 0x00, 0x00, 0xFF])))  # apply / end of frame
    return pkts


# --------------------------------------------------------------------------- helpers
def parse_hex(s: str) -> tuple:
    s = s.lstrip("#")
    if len(s) != 6:
        raise SystemExit(f"bad color {s!r}, expected RRGGBB")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def load_leds():
    with open(LED_TABLE) as f:
        return json.load(f)


def stream_from(colors_by_index: dict) -> bytes:
    buf = bytearray(STREAM_LEN)
    for idx, (r, g, b) in colors_by_index.items():
        buf[3 * idx:3 * idx + 3] = bytes((r, g, b))
    return bytes(buf)


def solid_stream(rgb, leds) -> bytes:
    return stream_from({k["index"]: rgb for k in leds})


# --------------------------------------------------------------------------- hardware
def _hid():
    try:
        import hid  # pip install hidapi
    except ImportError:
        raise SystemExit("python hidapi missing: python3 -m pip install --user hidapi")
    return hid


def find_device_path(verbose=False):
    hid = _hid()
    found = None
    for d in hid.enumerate(VENDOR_ID, 0):
        pid = d["product_id"]
        if verbose:
            print(f"  {d['vendor_id']:04x}:{pid:04x} iface={d.get('interface_number')} "
                  f"usage_page=0x{d.get('usage_page', 0):04x} usage=0x{d.get('usage', 0):04x} "
                  f"product={d.get('product_string')!r} path={d['path']!r}")
        if pid in PRODUCT_IDS and d.get("interface_number") == LED_INTERFACE and found is None:
            found = d["path"]
    return found


class Keyboard:
    def __init__(self, read_replies=False):
        path = find_device_path()
        if not path:
            raise SystemExit("Ducky keyboard (interface 1) not found. Try: tools/ducky.py list")
        self.dev = _hid().device()
        self.dev.open_path(path)
        self.read_replies = read_replies

    def write(self, payload: bytes):
        self.dev.write(b"\x00" + payload)   # report ID 0 + 64 bytes
        if self.read_replies:
            reply = self.dev.read(64, 50)
            if reply:
                print("  <-", bytes(reply).hex())
        if INTER_PACKET_DELAY:
            time.sleep(INTER_PACKET_DELAY)

    def begin(self):
        self.write(enter_direct_mode())

    def frame(self, stream: bytes):
        for p in color_frame(stream):
            self.write(p)

    def end(self):
        self.write(exit_direct_mode())

    def close(self):
        self.dev.close()


# --------------------------------------------------------------------------- commands
def cmd_list(_):
    print(f"HID devices with vendor 0x{VENDOR_ID:04x}:")
    path = find_device_path(verbose=True)
    print("\nLED interface:", path or "NOT FOUND")


def cmd_solid(a):
    kb = Keyboard(a.read)
    kb.begin()
    kb.frame(solid_stream(parse_hex(a.color), load_leds()))
    print("Done. Lighting stays until `release` (Fn shortcuts may not work meanwhile).")
    kb.close()


def cmd_key(a):
    leds = {k["label"].lower(): k["index"] for k in load_leds()}
    idx = leds.get(a.label.lower())
    if idx is None:
        raise SystemExit(f"unknown key {a.label!r}; labels: {', '.join(sorted(leds))}")
    kb = Keyboard(a.read)
    kb.begin()
    kb.frame(stream_from({idx: parse_hex(a.color)}))
    kb.close()


def cmd_rainbow(a):
    leds = load_leds()
    kb = Keyboard(a.read)
    kb.begin()
    t0 = time.time()
    frames = 0
    try:
        while time.time() - t0 < a.seconds:
            t = time.time() - t0
            cols = {}
            for k in leds:
                h = (k["col"] / 19.0 - t * 0.3) % 1.0
                r, g, b = colorsys.hsv_to_rgb(h, 1, 1)
                cols[k["index"]] = (int(r * 255), int(g * 255), int(b * 255))
            kb.frame(stream_from(cols))
            frames += 1
    finally:
        kb.end()
        kb.close()
    print(f"{frames / a.seconds:.1f} fps")


def cmd_release(a):
    kb = Keyboard(a.read)
    kb.end()
    kb.close()
    print("Released: keyboard firmware lighting restored.")


def cmd_frame(a):
    for i, p in enumerate(color_frame(solid_stream(parse_hex(a.color), load_leds()))):
        print(f"{i}: {p.hex()}")


def cmd_vectors(_):
    """Golden vectors for Tests/DuckyKitTests/GoldenVectors.swift."""
    leds = load_leds()
    cases = {
        "solidRed": solid_stream((0xFF, 0, 0), leds),
        "indexPattern": stream_from({i: (i, 255 - i, (i * 2) % 256) for i in range(153)}),
    }
    out = ["// Generated by `python3 tools/ducky.py vectors` — do not edit by hand.",
           "enum GoldenVectors {"]
    for name, stream in cases.items():
        out.append(f"    static let {name}: [String] = [")
        for p in color_frame(stream):
            out.append(f'        "{p.hex()}",')
        out.append("    ]")
    out.append(f'    static let enterDirect = "{enter_direct_mode().hex()}"')
    out.append(f'    static let exitDirect = "{exit_direct_mode().hex()}"')
    out.append("}")
    print("\n".join(out))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--read", action="store_true", help="print the keyboard's reply after each packet")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list").set_defaults(fn=cmd_list)
    p = sub.add_parser("solid"); p.add_argument("color"); p.set_defaults(fn=cmd_solid)
    p = sub.add_parser("key"); p.add_argument("label"); p.add_argument("color"); p.set_defaults(fn=cmd_key)
    p = sub.add_parser("rainbow"); p.add_argument("--seconds", type=float, default=10); p.set_defaults(fn=cmd_rainbow)
    sub.add_parser("release").set_defaults(fn=cmd_release)
    p = sub.add_parser("frame"); p.add_argument("color"); p.set_defaults(fn=cmd_frame)
    sub.add_parser("vectors").set_defaults(fn=cmd_vectors)
    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
