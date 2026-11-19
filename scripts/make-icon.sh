#!/bin/bash
# Regenerate Resources/AppIcon.icns from AppIconView (Sources/DuckyLights/DuckyLightsApp.swift).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product DuckyLights >/dev/null
tmp=$(mktemp -d)
.build/debug/DuckyLights --render-icon "$tmp/icon_1024.png" >/dev/null
set=$tmp/AppIcon.iconset
mkdir "$set"
for s in 16 32 128 256 512; do
  sips -z $s $s "$tmp/icon_1024.png" --out "$set/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$tmp/icon_1024.png" --out "$set/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$set" -o Resources/AppIcon.icns
cp "$tmp/icon_1024.png" Resources/AppIcon-1024.png
rm -rf "$tmp"
echo "wrote Resources/AppIcon.icns"
