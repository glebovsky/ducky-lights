#!/bin/bash
# Identify the Ducky keyboard on macOS. Looking for vendor 0x04d9, product 0x0356 (One 2 RGB TKL).
set -u
echo "== USB (system_profiler) =="
system_profiler SPUSBDataType 2>/dev/null | grep -i -B2 -A10 "ducky" || echo "no 'Ducky' entry found"
echo
echo "== HID collections (hidutil) =="
hidutil list 2>/dev/null | head -1
hidutil list 2>/dev/null | grep -i -E "0x4d9|ducky" || echo "no vendor 0x4d9 HID devices"
echo
echo "Expect ProductID 0x356 (= 854) for the RGB TKL. 0x348 = full-size One 2 RGB."
