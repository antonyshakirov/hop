#!/bin/zsh
# Builds Hop.app from the Swift package and signs it with an ad-hoc signature.
#
# Modes:
#   ./scripts/build-app.sh                 — only build dist/Hop.app
#   ./scripts/build-app.sh --install       — update /Applications/Hop.app
#   ./scripts/build-app.sh --install --dev — parallel "Hop Dev.app":
#       its own bundle id (…minimo.dev) → its own settings and permissions;
#       the main Hop.app is NOT touched and keeps running
set -euo pipefail
cd "$(dirname "$0")/.."

DEV=0
INSTALL=0
PROD=0
for arg in "$@"; do
    [[ "$arg" == "--dev" ]] && DEV=1
    [[ "$arg" == "--install" ]] && INSTALL=1
    [[ "$arg" == "--prod" ]] && PROD=1
done

# the production Hop.app is updated ONLY via releases (latest.json on the site)
# or an explicit --prod; day-to-day changes are installed as "Hop Dev.app"
if [[ $INSTALL == 1 && $DEV == 0 ]]; then
    # Anton's decision (2026-07-14, strict): ONLY he installs the production
    # Hop.app himself from the DMG; only the auto-updater updates it. --prod
    # works only with HOP_ALLOW_PROD=1 — so no session installs it out of habit
    if [[ $PROD == 0 || "${HOP_ALLOW_PROD:-}" != "1" ]]; then
        echo "⛔ hands off the production Hop.app: only Anton's manual install from the DMG"
        echo "   and the official auto-update. Test build: --install --dev"
        exit 1
    fi
fi

# Dev installs build DEBUG: the release build is a whole-module compile of the
# entire app and takes ~25 minutes on this machine, which is no way to look at a
# change (Anton, 2026-07-25). A debug build of the same tree takes seconds and
# behaves identically for everything except raw speed. Releases — and anything
# that is not --dev — stay optimized. HOP_RELEASE_BUILD=1 forces the slow path
# for a dev bundle when the optimized binary is what needs testing.
if [[ $DEV == 1 && "${HOP_RELEASE_BUILD:-}" != "1" ]]; then
    CONFIGURATION="debug"
else
    CONFIGURATION="release"
fi
# A dev bundle builds for THIS machine only — the point is to look at a change,
# and a second architecture doubles the wait for nothing. Everything shipped is
# universal: an arm64-only binary does not launch on an Intel Mac at all (Rosetta
# translates the other way), and both bundled helpers — the torrent engine and
# the 7-Zip archiver — have been universal all along.
if [[ $DEV == 1 ]]; then
    swift build -c "$CONFIGURATION"
    BINARY=".build/$CONFIGURATION/Hop"
else
    swift build -c "$CONFIGURATION" --arch arm64 --arch x86_64
    # SwiftPM writes the universal binary under a capitalised configuration name
    BINARY=".build/apple/Products/$(echo "$CONFIGURATION" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')/Hop"
fi

if [[ ! -f assets/AppIcon.icns ]]; then
    ./scripts/make-icon.sh
fi

# Document icons are generated rather than stored: nine near-identical sheets
# would be megabytes of binary in a repo that can redraw them in a second.
DOC_ICONS=(DocTorrent DocRar DocZip Doc7z DocTar DocGz DocTgz DocBz2 DocXz)
for icon in "${DOC_ICONS[@]}"; do
    if [[ ! -f "assets/$icon.icns" ]]; then
        ./scripts/make-doc-icons.sh
        break
    fi
done

if [[ $DEV == 1 ]]; then
    APP_NAME="Hop Dev"
else
    APP_NAME="Hop"
fi
APP="dist/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Hop"
cp scripts/Info.plist "$APP/Contents/Info.plist"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
for icon in "${DOC_ICONS[@]}"; do
    cp "assets/$icon.icns" "$APP/Contents/Resources/$icon.icns"
done
if [[ $DEV == 1 ]]; then
    # separate identity: no conflicts with the main version over settings
    # or the login item; the canonical bundle id of the main Hop never changes
    plutil -replace CFBundleIdentifier -string "com.antonshakirov.minimo.dev" "$APP/Contents/Info.plist"
    plutil -replace CFBundleName -string "Hop Dev" "$APP/Contents/Info.plist"
    plutil -replace CFBundleDisplayName -string "Hop Dev" "$APP/Contents/Info.plist"
fi
# stable signature: macOS permissions survive updates
IDENTITY="Minimo Signing"
if ! security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    IDENTITY="-"
fi
codesign --force --sign "$IDENTITY" "$APP"

echo "done: $APP ($CONFIGURATION)"

if [[ $INSTALL == 1 ]]; then
    TARGET="/Applications/$APP_NAME.app"
    # kill ONLY our own instance: both versions use the Hop binary,
    # pkill -x would take down the main version along with dev
    pkill -f "$TARGET/Contents/MacOS/Hop" 2>/dev/null || true
    sleep 0.5
    if [[ $DEV == 0 ]]; then
        rm -rf "/Applications/Dots.app" "/Applications/Personal Timer.app" "/Applications/Dotbar.app" "/Applications/Minimo.app"
    fi
    rm -rf "$TARGET"
    cp -R "$APP" "$TARGET"
    open "$TARGET"
    echo "installed and launched: $TARGET"
fi
