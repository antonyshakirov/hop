#!/bin/zsh
# Polished DMG via dmgbuild: background with an arrow, large icons,
# Applications symlink, volume icon. .DS_Store is written programmatically —
# the layout does not depend on Finder timing (the AppleScript path lost it).
# Usage: ./scripts/make-dmg.sh [path/to/Hop.app] (default dist/Hop.app)
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-dist/Hop.app}"
[[ -d "$APP" ]] || { echo "missing $APP — run ./scripts/build-app.sh first"; exit 1 }
OUT="dist/Hop.dmg"

# background — classic 1x PNG 640×400: a retina TIFF bloated the image by 3 MB,
# and Finder does not render a PNG with dpi set; slightly soft text on retina is fine
swift scripts/make-dmg-bg.swift dist/dmg-bg.png 1 >/dev/null

# cleanup: stale "Hop" volumes from previous runs confuse AppleScript
# (the disk is looked up by name) — detach them all
for stale in /Volumes/Hop*(N); do
    [[ -d "$stale" ]] && hdiutil detach "$stale" -force >/dev/null 2>&1 || true
done
rm -f "$OUT" dist/hop-rw.dmg
# 1) dmgbuild writes the layout (positions, window, icons) into a RW image
python3 -m dmgbuild -s scripts/dmg-settings.py -D app="$APP" -D format=UDRW "Hop" dist/hop-rw.dmg

# 2) known macOS 26 (Tahoe) bug: dmgbuild writes the background as BOTH an
#    alias AND a bookmark, and the bookmark is what breaks rendering — Finder
#    shows a blank window (community fix: electron-builder#9072, podman-desktop#15719).
#    Strip the bookmark, keep the alias
MOUNT=$(hdiutil attach dist/hop-rw.dmg -readwrite -noverify -noautoopen | awk -F"\t" '/\/Volumes\//{print $3}')
[[ -n "$MOUNT" ]] || { echo "rw image failed to mount"; exit 1 }
python3 - "$MOUNT" << 'STRIP'
import sys, plistlib
from ds_store import DSStore
mount = sys.argv[1]
with DSStore.open(f"{mount}/.DS_Store", "r+") as store:
    icvp = dict(store["."]["icvp"])
    assert icvp.get("backgroundImageAlias"), "no background alias from dmgbuild"
    icvp.pop("backgroundImageBookmark", None)
    icvp["backgroundType"] = 2
    store["."]["icvp"] = icvp
print("bookmark stripped, alias in place")
STRIP
sync
hdiutil detach "$MOUNT" >/dev/null
hdiutil convert dist/hop-rw.dmg -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
rm -f dist/hop-rw.dmg

# self-check by BYTES, not via Finder: the image's .DS_Store must contain
# layout entries (bwsp/icvp) and positions for both items
MOUNT=$(hdiutil attach "$OUT" -noautoopen -readonly | awk -F"\t" '/\/Volumes\//{print $3}')
python3 - "$MOUNT" << 'CHECK'
import sys
from ds_store import DSStore
mount = sys.argv[1]
with DSStore.open(f"{mount}/.DS_Store", "r") as store:
    entries = {(e.filename, e.code) for e in store}
names = {n for n, _ in entries}
codes = {c for _, c in entries}
assert "Hop.app" in names and "Applications" in names, f"missing positions: {names}"
assert b"bwsp" in codes and b"icvp" in codes, f"missing window view: {codes}"
import plistlib
with DSStore.open(f"{mount}/.DS_Store", "r") as store:
    for e in store:
        if e.code == b"icvp":
            v = e.value if isinstance(e.value, dict) else plistlib.loads(e.value)
            assert v.get("backgroundImageAlias"), "missing background alias"
            assert not v.get("backgroundImageBookmark"), "bookmark not stripped — background will vanish on Tahoe"
print("layout in image: positions + window + background (alias, no bookmark) in place")
CHECK
STATUS=$?
hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
[[ $STATUS == 0 ]] || { echo "⛔ layout was not written"; exit 1 }
echo "done: $OUT"
