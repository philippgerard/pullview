#!/bin/sh
# Renders Resources/AppIcon.icns from scripts/icon/render.swift (all shapes drawn in code).
set -eu
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
swift scripts/icon/render.swift "$TMP"
SET="$TMP/AppIcon.iconset"
mkdir "$SET"
for size in 16 32 128 256 512; do
  sips -z $size $size "$TMP/icon_1024.png" --out "$SET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$TMP/icon_1024.png" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
mkdir -p Resources
iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo Resources/AppIcon.icns
