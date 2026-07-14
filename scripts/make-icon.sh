#!/bin/zsh
# Builds assets/AppIcon.icns from scripts/make-icon.swift
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p assets
TMP=$(mktemp -d)
swift scripts/make-icon.swift "$TMP/icon.png"

ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s "$TMP/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d "$TMP/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o assets/AppIcon.icns
rm -rf "$TMP"
echo "done: assets/AppIcon.icns"
