#!/bin/bash
# Generate AppIcon.icns from the Claude spark. Re-run if the design changes.
set -e
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
cp tools/genicon.swift "$TMP/main.swift" # swiftc only allows top-level code in main.swift
swiftc "$TMP/main.swift" -o "$TMP/genicon"
"$TMP/genicon" /tmp/clawbar_icon_1024.png
SET=AppIcon.iconset
rm -rf "$SET"; mkdir "$SET"
gen() { sips -z "$1" "$1" /tmp/clawbar_icon_1024.png --out "$SET/$2" >/dev/null; }
gen 16 icon_16x16.png;     gen 32 icon_16x16@2x.png
gen 32 icon_32x32.png;     gen 64 icon_32x32@2x.png
gen 128 icon_128x128.png;  gen 256 icon_128x128@2x.png
gen 256 icon_256x256.png;  gen 512 icon_256x256@2x.png
gen 512 icon_512x512.png;  gen 1024 icon_512x512@2x.png
iconutil -c icns "$SET" -o AppIcon.icns
rm -rf "$SET"
echo "AppIcon.icns listo ($(du -h AppIcon.icns | cut -f1))"
