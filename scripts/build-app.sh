#!/bin/zsh
# Builds Hop.app from the Swift package and signs it with Developer ID.
#
# Modes:
#   ./scripts/build-app.sh                 — only build dist/Hop.app
#   ./scripts/build-app.sh --install       — update /Applications/Hop.app
#   ./scripts/build-app.sh --install --dev — parallel "Hop Dev.app":
#       its own bundle id (…minimo.dev) → its own settings and permissions;
#       the main Hop.app is NOT touched and keeps running
#   HOP_NOTARIZE=1 is required to install a Dev build containing the hardware service.
set -euo pipefail
cd "$(dirname "$0")/.."

DEV=0
INSTALL=0
PROD=0
OPEN_SOUND=0
SHOW_RELEASE_CARD=0
for arg in "$@"; do
    [[ "$arg" == "--dev" ]] && DEV=1
    [[ "$arg" == "--install" ]] && INSTALL=1
    [[ "$arg" == "--prod" ]] && PROD=1
    [[ "$arg" == "--open-sound" ]] && OPEN_SOUND=1
    [[ "$arg" == "--show-release-card" ]] && SHOW_RELEASE_CARD=1
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
    BUILD_ARGS=(-c "$CONFIGURATION")
else
    BUILD_ARGS=(-c "$CONFIGURATION" --arch arm64 --arch x86_64)
fi
swift build "${BUILD_ARGS[@]}"
# WORKAROUND: the bin path is asked of SwiftPM, never spelled out — Swift 6.4 moved it and 2.1.1 shipped a stale binary.
BINARY="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)/Hop"
WORKER_BINARY="${BINARY%/Hop}/HopAudioWorker"
HARDWARE_BINARY="${BINARY%/Hop}/HopHardwareHelper"
PLUGIN_BINARY="${BINARY%/Hop}/HopPluginRuntime"
for EXECUTABLE in "$BINARY" "$WORKER_BINARY" "$HARDWARE_BINARY" "$PLUGIN_BINARY"; do
    if [[ ! -f "$EXECUTABLE" ]]; then
        echo "❌ swift build did not produce $EXECUTABLE"
        exit 1
    fi
done
STALE="$(find Sources Package.swift -type f \( -name '*.swift' -o -name '*.c' -o -name '*.h' -o -name Package.swift \) -newer "$BINARY" | head -1 || true)"
if [[ -n "$STALE" ]]; then
    echo "❌ $BINARY is older than $STALE — refusing to package a stale build"
    exit 1
fi
STALE="$(find Sources/HopAudioWorker Sources/HopAudioEngine Sources/HopAudioDSP Sources/HopCore Package.swift -type f \( -name '*.swift' -o -name '*.c' -o -name '*.h' -o -name Package.swift \) -newer "$WORKER_BINARY" | head -1 || true)"
if [[ -n "$STALE" ]]; then
    echo "❌ $WORKER_BINARY is older than $STALE — refusing to package a stale worker"
    exit 1
fi
STALE="$(find Sources/HopHardwareHelper Sources/HopHardwareKit Package.swift -type f \( -name '*.swift' -o -name Package.swift \) -newer "$HARDWARE_BINARY" | head -1 || true)"
if [[ -n "$STALE" ]]; then
    echo "❌ $HARDWARE_BINARY is older than $STALE — refusing to package a stale service"
    exit 1
fi
if [[ $DEV != 1 ]]; then
    for EXECUTABLE in "$BINARY" "$WORKER_BINARY" "$HARDWARE_BINARY" "$PLUGIN_BINARY"; do
        ARCHS="$(lipo -archs "$EXECUTABLE")"
        if [[ "$ARCHS" != *arm64* || "$ARCHS" != *x86_64* ]]; then
            echo "❌ $EXECUTABLE is not universal ($ARCHS)"
            exit 1
        fi
    done
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
OUTPUT_DIRECTORY="${HOP_BUILD_OUTPUT:-dist}"
APP="$OUTPUT_DIRECTORY/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Hop"
cp scripts/Info.plist "$APP/Contents/Info.plist"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
WORKER_APP="$APP/Contents/Helpers/HopAudioWorker.app"
mkdir -p "$WORKER_APP/Contents/MacOS"
cp "$WORKER_BINARY" "$WORKER_APP/Contents/MacOS/HopAudioWorker"
cp scripts/HopAudioWorker-Info.plist "$WORKER_APP/Contents/Info.plist"
HARDWARE_APP="$APP/Contents/Helpers/HopHardwareHelper.app"
mkdir -p "$HARDWARE_APP/Contents/MacOS" "$APP/Contents/Library/LaunchDaemons"
cp "$HARDWARE_BINARY" "$HARDWARE_APP/Contents/MacOS/HopHardwareHelper"
cp scripts/HopHardwareHelper-Info.plist "$HARDWARE_APP/Contents/Info.plist"
PLUGIN_XPC="$APP/Contents/XPCServices/HopPluginRuntime.xpc"
mkdir -p "$PLUGIN_XPC/Contents/MacOS"
cp "$PLUGIN_BINARY" "$PLUGIN_XPC/Contents/MacOS/HopPluginRuntime"
cp scripts/HopPluginRuntime-Info.plist "$PLUGIN_XPC/Contents/Info.plist"
cp scripts/com.antonshakirov.minimo.hardware.plist "$APP/Contents/Library/LaunchDaemons/com.antonshakirov.minimo.hardware.plist"
cp docs/third-party/ClamDown-LICENSE.txt "$APP/Contents/Resources/ClamDown-LICENSE.txt"
for icon in "${DOC_ICONS[@]}"; do
    cp "assets/$icon.icns" "$APP/Contents/Resources/$icon.icns"
done
if [[ $DEV == 1 ]]; then
    # separate identity: no conflicts with the main version over settings
    # or the login item; the canonical bundle id of the main Hop never changes
    plutil -replace CFBundleIdentifier -string "com.antonshakirov.minimo.dev" "$APP/Contents/Info.plist"
    plutil -replace CFBundleName -string "Hop Dev" "$APP/Contents/Info.plist"
    plutil -replace CFBundleDisplayName -string "Hop Dev" "$APP/Contents/Info.plist"
    plutil -replace HopHardwareDiagnosticsVersion -integer 1 "$APP/Contents/Info.plist"
    plutil -replace CFBundleIdentifier -string "com.antonshakirov.minimo.dev.audio-worker" "$WORKER_APP/Contents/Info.plist"
    plutil -replace CFBundleIdentifier -string "com.antonshakirov.minimo.dev.hardware-helper" "$HARDWARE_APP/Contents/Info.plist"
    plutil -replace CFBundleIdentifier -string "com.antonshakirov.minimo.dev.plugin-runtime" "$PLUGIN_XPC/Contents/Info.plist"
    plutil -replace HopPluginParentIdentifier -string "com.antonshakirov.minimo.dev" "$PLUGIN_XPC/Contents/Info.plist"
    python3 - "$APP/Contents/Library/LaunchDaemons" <<'PYHARDWARE'
import pathlib, plistlib, sys
directory = pathlib.Path(sys.argv[1])
source = directory / 'com.antonshakirov.minimo.hardware.plist'
value = plistlib.loads(source.read_bytes())
value['Label'] = 'com.antonshakirov.minimo.dev.hardware'
value['MachServices'] = {'com.antonshakirov.minimo.dev.hardware': True}
value['AssociatedBundleIdentifiers'] = ['com.antonshakirov.minimo.dev']
(directory / 'com.antonshakirov.minimo.dev.hardware.plist').write_bytes(plistlib.dumps(value))
source.unlink()
PYHARDWARE
    # SPEC: docs/spec.md — "Versioning", a dev build carries the release it is preparing.
    PREPARING="$("$BINARY" --preparing-version)"
    plutil -replace CFBundleShortVersionString -string "$PREPARING" "$APP/Contents/Info.plist"
    plutil -replace CFBundleVersion -string "$PREPARING" "$APP/Contents/Info.plist"
fi
APP_VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
APP_BUILD="$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist")"
plutil -replace CFBundleVersion -string "$APP_BUILD" "$HARDWARE_APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$HARDWARE_APP/Contents/Info.plist"
source scripts/signing.sh
IDENTITY="$(hop_signing_identity)"
if [[ -z "$IDENTITY" ]]; then
    echo "⚠ no Developer ID Application certificate — signing ad hoc."
    echo "  This build is for looking at a change only: Gatekeeper rejects it,"
    echo "  and every permission it is granted dies with it."
    IDENTITY="-"
fi
# SPEC: docs/spec.md — "Network access": every build carries the filter.
# macOS requires notarization for the network filter and LaunchDaemon, so a dev
# build that has to run either is built with HOP_NOTARIZE=1;
# notarisation also wants a secure timestamp on the nested code of a release.
TIMESTAMP=no-timestamp
[[ "${HOP_NOTARIZE:-}" == "1" || $DEV == 0 ]] && TIMESTAMP=timestamp
APP_ENTITLEMENTS="$HOP_ENTITLEMENTS"
if [[ "$IDENTITY" != "-" ]]; then
    FILTER_BINARY="$(dirname "$BINARY")/HopNetFilter"
    if [[ -f "$FILTER_BINARY" ]] && hop_embed_network_filter "$APP" "$FILTER_BINARY" "$IDENTITY" "$TIMESTAMP"; then
        APP_ENTITLEMENTS="$HOP_NETWORK_ENTITLEMENTS"
        echo "network filter: embedded"
    elif [[ $DEV == 0 ]]; then
        echo "❌ network filter: not embedded — a release must carry it (profiles in ~/.minimo-signing/profiles, HopNetFilter built)"
        exit 1
    else
        echo "⚠ network filter: not embedded (no profiles in ~/.minimo-signing/profiles or no binary)"
    fi
elif [[ $DEV == 0 ]]; then
    echo "❌ network filter: a release needs the Developer ID identity to embed it"
    exit 1
fi
hop_sign_app "$WORKER_APP" "$IDENTITY" "$TIMESTAMP" scripts/HopAudioWorker.entitlements
hop_sign_app "$HARDWARE_APP" "$IDENTITY" "$TIMESTAMP" scripts/HopHardwareHelper.entitlements
PLUGIN_TEAM="$(codesign -dvv "$HARDWARE_APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
plutil -replace HopPluginSigningTeam -string "$PLUGIN_TEAM" "$PLUGIN_XPC/Contents/Info.plist"
hop_sign_app "$PLUGIN_XPC" "$IDENTITY" "$TIMESTAMP" scripts/HopPluginRuntime.entitlements
hop_sign_app "$APP" "$IDENTITY" "$TIMESTAMP" "$APP_ENTITLEMENTS"
codesign --verify --deep --strict "$APP"

if [[ "${HOP_NOTARIZE:-}" == "1" ]]; then
    [[ -f .env ]] || { echo "❌ HOP_NOTARIZE=1 needs .env with the notary credentials"; exit 1; }
    eval "$(python3 - <<'PYENV'
import re, shlex
for line in open(".env"):
    match = re.match(r"^(APPLE_[A-Z_]+)=(.*)$", line.strip())
    if match:
        print(f"export {match.group(1)}={shlex.quote(match.group(2))}")
PYENV
)"
    ZIP="$OUTPUT_DIRECTORY/$APP_NAME-notarize.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    RESULT=$(xcrun notarytool submit "$ZIP" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_PASSWORD" --wait 2>&1)
    rm -f "$ZIP"
    # WORKAROUND: notarytool exits zero on a rejected submission; read the status.
    if [[ "$RESULT" != *"status: Accepted"* ]]; then
        echo "$RESULT" | tail -5
        echo "❌ notarisation failed"
        exit 1
    fi
    xcrun stapler staple -q "$APP"
    echo "notarised and stapled"
fi

echo "done: $APP ($CONFIGURATION)"

if [[ $INSTALL == 1 ]]; then
    TARGET="/Applications/$APP_NAME.app"
    if [[ $DEV == 1 ]] && ! spctl -a -t exec "$APP" >/dev/null 2>&1; then
        echo "❌ the development app must be notarized before installing its hardware service"
        echo "   rebuild with HOP_NOTARIZE=1"
        exit 1
    fi
    if [[ $DEV == 1 && -d "$TARGET/Contents/Helpers/HopHardwareHelper.app" ]]; then
        DIAGNOSTICS="$(plutil -extract HopHardwareDiagnosticsVersion raw "$TARGET/Contents/Info.plist" 2>/dev/null || true)"
        if [[ "$DIAGNOSTICS" != "1" ]]; then
            echo "❌ the installed development build lacks the hardware maintenance handshake"
            echo "   inspect its service state before replacing this earlier development build"
            exit 1
        fi
        "$TARGET/Contents/MacOS/Hop" --hardware-prepare-update
    fi
    # kill ONLY our own instance: both versions use the Hop binary,
    # pkill -x would take down the main version along with dev
    pkill -f "$TARGET/Contents/MacOS/Hop" 2>/dev/null || true
    sleep 0.5
    if [[ $DEV == 0 ]]; then
        rm -rf "/Applications/Dots.app" "/Applications/Personal Timer.app" "/Applications/Dotbar.app" "/Applications/Minimo.app"
    fi
    rm -rf "$TARGET"
    cp -R "$APP" "$TARGET"
    if [[ $DEV == 1 && $SHOW_RELEASE_CARD == 1 ]]; then
        open "$TARGET" --args --show-release-card
    elif [[ $DEV == 1 && $OPEN_SOUND == 1 ]]; then
        open "$TARGET" --args --open-sound
    else
        open "$TARGET"
    fi
    echo "installed and launched: $TARGET"
fi
