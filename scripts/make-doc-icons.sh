#!/bin/zsh
# Builds assets/Doc*.icns from scripts/make-doc-icons.swift — one document icon
# per file type Hop can be the opener for.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p assets
TMP=$(mktemp -d)
swift scripts/make-doc-icons.swift "$TMP"

for iconset in "$TMP"/*.iconset; do
    name=$(basename "$iconset" .iconset)
    iconutil -c icns "$iconset" -o "assets/$name.icns"
done
rm -rf "$TMP"
echo "done: assets/Doc*.icns"
