#!/bin/zsh
# Builds assets/AppIcon.icns from scripts/make-icon.swift
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p assets
TMP=$(mktemp -d)

ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
# Every size is DRAWN, not scaled: scaling averaged the asterisk with the plate
# behind it and the small sizes came out grey and soft.
for s in 16 32 128 256 512; do
    swift scripts/make-icon.swift "$ICONSET/icon_${s}x${s}.png" $s >/dev/null
    swift scripts/make-icon.swift "$ICONSET/icon_${s}x${s}@2x.png" $((s * 2)) >/dev/null
done
iconutil -c icns "$ICONSET" -o assets/AppIcon.icns
rm -rf "$TMP"
echo "done: assets/AppIcon.icns"
