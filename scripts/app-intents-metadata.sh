#!/bin/bash
# Builds the App Intents metadata bundle and drops it into the .app, so Siri,
# Shortcuts and Spotlight can see Hop's actions.
#
# Xcode runs this step for you; SwiftPM does not, so without this the intents in
# Sources/Hop/AppIntents.swift exist only inside the binary and nothing outside
# ever learns about them.
#
# Two stages, both undocumented by Apple but stable since the feature shipped:
#   1. a whole-module compile whose only product we keep is the const-value
#      sidecar — it needs -wmo AND an explicit -emit-const-values-path AND the
#      list of protocols to gather (-const-gather-protocols-file). Any one of
#      the three missing and the compiler writes nothing, silently.
#   2. appintentsmetadataprocessor, the same tool Xcode invokes, fed that sidecar.
#
# Failure here is NOT fatal: it costs the spoken shortcuts, not the app.
set -uo pipefail

APP="$1"              # path to the .app bundle
CONFIGURATION="$2"    # debug | release
BUNDLE_ID="$3"

PROCESSOR="$(xcrun -f appintentsmetadataprocessor 2>/dev/null || true)"
if [[ -z "$PROCESSOR" || ! -x "$PROCESSOR" ]]; then
    echo "app intents: processor not found (no Xcode toolchain) — skipping"
    exit 0
fi

WORK=".build/appintents"
mkdir -p "$WORK"
SDK="$(xcrun --show-sdk-path --sdk macosx)"
TOOLCHAIN="$(xcrun -f swift | sed 's|/usr/bin/swift$||')"
DEPLOYMENT="$(sed -n 's/.*macOS(\.v\([0-9]*\)).*/\1/p' Package.swift | head -1)"
DEPLOYMENT="${DEPLOYMENT:-14}.0"
TRIPLE="arm64-apple-macos$DEPLOYMENT"
SIDECAR="$WORK/Hop.swiftconstvalues"

echo '["AppIntent","AppShortcutsProvider","AppEntity","AppEnum","EntityQuery"]' \
    > "$WORK/const_extract_protocols.json"

# stage 1 — the sidecar
find Sources/Hop -name '*.swift' > "$WORK/sources.txt"
# shellcheck disable=SC2046
xcrun swiftc -wmo -c -o "$WORK/Hop.o" \
    -emit-const-values-path "$SIDECAR" \
    -Xfrontend -const-gather-protocols-file \
    -Xfrontend "$WORK/const_extract_protocols.json" \
    -module-name Hop -sdk "$SDK" -target "$TRIPLE" \
    -I ".build/arm64-apple-macosx/$CONFIGURATION/Modules" \
    $(cat "$WORK/sources.txt") 2>"$WORK/compile.log"

if [[ ! -s "$SIDECAR" ]]; then
    echo "app intents: no const values produced — see $WORK/compile.log"
    exit 0
fi

# stage 2 — the metadata bundle
echo "$SIDECAR" > "$WORK/constvalues.txt"
"$PROCESSOR" \
    --output "$APP/Contents/Resources" \
    --toolchain-dir "$TOOLCHAIN" \
    --module-name Hop \
    --sdk-root "$SDK" \
    --xcode-version "$(xcodebuild -version 2>/dev/null | tail -1 | awk '{print $3}')" \
    --platform-family macOS \
    --deployment-target "$DEPLOYMENT" \
    --target-triple "$TRIPLE" \
    --source-file-list "$WORK/sources.txt" \
    --swift-const-vals-list "$WORK/constvalues.txt" \
    --bundle-identifier "$BUNDLE_ID" \
    --force 2>&1 | sed 's/^/app intents: /'

if [[ -d "$APP/Contents/Resources/Metadata.appintents" ]]; then
    echo "app intents: metadata written"
else
    echo "app intents: processor produced nothing — spoken shortcuts will be absent"
fi
exit 0
