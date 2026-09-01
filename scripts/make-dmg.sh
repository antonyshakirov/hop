#!/bin/zsh
# Polished DMG via dmgbuild: background with an arrow, large icons,
# Applications symlink, volume icon. .DS_Store is written programmatically —
# the layout does not depend on Finder timing (the AppleScript path lost it).
# Usage: ./scripts/make-dmg.sh [path/to/Hop.app] (default dist/Hop.app)
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-dist/Hop.app}"
[[ -d "$APP" ]] || { echo "missing $APP — run ./scripts/build-app.sh first"; exit 1 }
# A second argument names the image, so the release can build one DMG per
# architecture without the two overwriting each other.
OUT="${2:-dist/Hop.dmg}"

swift scripts/make-dmg-bg.swift dist/dmg-bg.png >/dev/null

# cleanup: stale "Hop" volumes from previous runs confuse AppleScript
# (the disk is looked up by name) — detach them all
for stale in /Volumes/Hop*(N); do
    [[ -d "$stale" ]] && hdiutil detach "$stale" -force >/dev/null 2>&1 || true
done
rm -f "$OUT" dist/hop-rw.dmg
# 1) dmgbuild writes the layout (positions, window, icons) into a RW image
python3 -m dmgbuild -s scripts/dmg-settings.py -D app="$APP" -D format=UDRW "Hop" dist/hop-rw.dmg

# 2) WORKAROUND: Finder draws nothing for the layout dmgbuild leaves behind —
#    see "DMG window" in docs/spec.md
MOUNT=$(hdiutil attach dist/hop-rw.dmg -readwrite -noverify -noautoopen | awk -F"\t" '/\/Volumes\//{print $3}')
[[ -n "$MOUNT" ]] || { echo "rw image failed to mount"; exit 1 }
python3 - "$MOUNT" << 'FIXBG'
import os, shutil, sys
import mac_alias
from ds_store import DSStore
mount = sys.argv[1]
folder = os.path.join(mount, ".background")
os.makedirs(folder, exist_ok=True)
picture = os.path.join(folder, "background.png")
shutil.move(os.path.join(mount, ".background.png"), picture)
with DSStore.open(os.path.join(mount, ".DS_Store"), "r+") as store:
    icvp = dict(store["."]["icvp"])
    assert icvp.get("backgroundImageAlias"), "no background alias from dmgbuild"
    icvp["backgroundImageAlias"] = mac_alias.Alias.for_file(picture).to_bytes()
    icvp["backgroundType"] = 2
    store["."]["icvp"] = icvp
    store.delete(".", b"pBBk")
print("picture moved into .background, alias repointed, bookmark record dropped")
FIXBG
sync
hdiutil detach "$MOUNT" >/dev/null
hdiutil convert dist/hop-rw.dmg -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
rm -f dist/hop-rw.dmg

# self-check by BYTES, not via Finder: positions, window and the background
# layout Finder honours
MOUNT=$(hdiutil attach "$OUT" -noautoopen -readonly | awk -F"\t" '/\/Volumes\//{print $3}')
python3 - "$MOUNT" << 'CHECK'
import os, plistlib, sys
from ds_store import DSStore
mount = sys.argv[1]
assert os.path.isfile(f"{mount}/.background/background.png"), "picture is not in .background"
assert not os.path.exists(f"{mount}/.background.png"), "picture still sits at the volume root"
with DSStore.open(f"{mount}/.DS_Store", "r") as store:
    entries = {(e.filename, e.code) for e in store}
names = {n for n, _ in entries}
codes = {c for _, c in entries}
assert "Hop.app" in names and "Applications" in names, f"missing positions: {names}"
assert b"bwsp" in codes and b"icvp" in codes, f"missing window view: {codes}"
assert (".", b"pBBk") not in entries, "bookmark record left in place — Finder draws a blank window"
with DSStore.open(f"{mount}/.DS_Store", "r") as store:
    for e in store:
        if e.code == b"icvp":
            v = e.value if isinstance(e.value, dict) else plistlib.loads(e.value)
            assert v.get("backgroundImageAlias"), "missing background alias"
            assert v.get("backgroundType") == 2, "background is not set to a picture"
print("layout in image: positions + window + picture in .background (alias, no bookmark)")
CHECK
STATUS=$?
hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
[[ $STATUS == 0 ]] || { echo "⛔ layout was not written"; exit 1 }
echo "done: $OUT"
