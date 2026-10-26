#!/bin/zsh
# Release gate: proves version X.Y.Z is ACTUALLY live on production before it
# is announced anywhere (git tag, GitHub release, posts). Checks the live
# latest.json, downloads the exact zip it points to, and inspects the bundle
# inside — a reference published before the files themselves would fail here,
# and so does a copy Gatekeeper would refuse to open.
#
#   ./scripts/verify-release.sh 1.3.1   # exit 0 = safe to announce
#
# Born from the 1.3.1 incident: the GitHub release went out while the site
# still served 404 for the new zip name (Next's public manifest needs a
# rebuild for NEW files; the deploy now self-checks, and this gate catches
# anything else).
set -euo pipefail

VERSION="${1:?usage: verify-release.sh <version>}"
SCRIPT_DIR="${0:A:h}"
BASE="https://hop.tools/downloads/hop"

fail() { echo "❌ $1"; exit 1 }
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || fail "expected a release version in X.Y.Z form"
TMP="$(mktemp -d -t hop-verify)"
trap 'rm -rf "$TMP"' EXIT

fetch() {
    curl -fsS --max-time 120 "$1" -o "$2" || fail "could not fetch $1"
}
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
manifest_value() {
    python3 -c 'import json,sys
value=json.load(open(sys.argv[1])).get(sys.argv[2])
if not isinstance(value,str) or not value or any(c.isspace() for c in value):
    raise SystemExit("missing or invalid manifest field: "+sys.argv[2])
print(value)' "$1" "$2"
}
plist_value() {
    plutil -extract "$2" raw "$1" 2>/dev/null || fail "missing $2 in $1"
}

fetch "$BASE/latest.json" "$TMP/latest.json"
LIVE_VERSION="$(manifest_value "$TMP/latest.json" version)" || fail "invalid release manifest"
[[ "$LIVE_VERSION" == "$VERSION" ]] || fail "live manifest says $LIVE_VERSION, expected $VERSION"
EXPECTED_ID="$(plist_value "$SCRIPT_DIR/Info.plist" CFBundleIdentifier)"
WORKER_ID="$(plist_value "$SCRIPT_DIR/HopAudioWorker-Info.plist" CFBundleIdentifier)"
typeset -a ARCHS ZIP_URLS SIG_URLS EXPECTED_ZIP_URLS
ARCHS=(arm64 x86_64)
ZIP_URLS=("$(manifest_value "$TMP/latest.json" zip)" "$(manifest_value "$TMP/latest.json" zipIntel)")
SIG_URLS=("$(manifest_value "$TMP/latest.json" sig)" "$(manifest_value "$TMP/latest.json" sigIntel)")
EXPECTED_ZIP_URLS=("$BASE/Hop-$VERSION.zip" "$BASE/Hop-$VERSION-intel.zip")
for index in 1 2; do
    arch="${ARCHS[$index]}"
    zip_url="${ZIP_URLS[$index]}"
    sig_url="${SIG_URLS[$index]}"
    [[ "$zip_url" == "${EXPECTED_ZIP_URLS[$index]}" && "$sig_url" == "${EXPECTED_ZIP_URLS[$index]}.sig" ]] \
        || fail "noncanonical release URLs for $arch"
    fetch "$zip_url" "$TMP/$arch.zip"
    fetch "$sig_url" "$TMP/$arch.sig"
    (( $(stat -f%z "$TMP/$arch.zip") > 1000000 )) || fail "$arch archive is suspiciously small"
    node "$SCRIPT_DIR/verify-release-signature.mjs" "$TMP/$arch.zip" "$TMP/$arch.sig" \
        || fail "$arch archive failed Ed25519 verification"
done

check_identity() {
    local app="$1" identifier="$2" executable="$3" info="$1/Contents/Info.plist"
    [[ -f "$info" ]] || fail "missing bundle metadata: $app"
    [[ "$(plist_value "$info" CFBundleIdentifier)" == "$identifier" ]] || fail "unexpected bundle identifier: $app"
    [[ "$(plist_value "$info" CFBundleExecutable)" == "$executable" ]] || fail "unexpected bundle executable: $app"
    [[ -f "$app/Contents/MacOS/$executable" && -x "$app/Contents/MacOS/$executable" ]] \
        || fail "missing bundle executable: $app"
}
check_thin_arch() {
    local actual
    actual="$(lipo -archs "$1")" || fail "could not inspect architecture: $1"
    [[ "$actual" == "$2" ]] || fail "expected only $2, found $actual: $1"
}
team() {
    local metadata
    metadata="$(codesign -dv --verbose=4 "$1" 2>&1)" || fail "could not inspect signing team: $1"
    echo "$metadata" | awk -F= '/^TeamIdentifier=/{value=$2;count++} END{if(count!=1 || value=="" || value=="not set")exit 1;print value}'
}

for arch in $ARCHS; do
    ditto -x -k "$TMP/$arch.zip" "$TMP/$arch" || fail "$arch archive does not unpack"
    app="$TMP/$arch/Hop.app"
    filter="$app/Contents/Library/SystemExtensions/$EXPECTED_ID.netfilter.systemextension"
    worker="$app/Contents/Helpers/HopAudioWorker.app"
    check_identity "$app" "$EXPECTED_ID" Hop
# SPEC: docs/spec.md — "Network access": the filter ships inside, signed, and the
# app holds the entitlement to install it.
    check_identity "$filter" "$EXPECTED_ID.netfilter" "$EXPECTED_ID.netfilter"
    check_identity "$worker" "$WORKER_ID" HopAudioWorker
    for bundle in "$app" "$filter"; do
        [[ "$(plist_value "$bundle/Contents/Info.plist" CFBundleShortVersionString)" == "$VERSION" ]] \
            || fail "$arch bundle version does not match $VERSION: $bundle"
    done
    diagnostic="$(plutil -extract HopOpenSoundAtLaunch raw "$app/Contents/Info.plist" 2>/dev/null || true)"
    [[ -z "$diagnostic" || "$diagnostic" == false || "$diagnostic" == 0 ]] \
        || fail "$arch release carries the open-Sound diagnostic flag"
    check_thin_arch "$app/Contents/MacOS/Hop" "$arch"
    check_thin_arch "$filter/Contents/MacOS/$EXPECTED_ID.netfilter" "$arch"
    lipo -verify_arch "$arch" "$worker/Contents/MacOS/HopAudioWorker" \
        || fail "$arch audio worker lacks the required architecture"
    codesign --verify --strict --deep "$app" || fail "$arch app signature is broken"
    app_team="$(team "$app")" || fail "$arch app has no signing team"
    for nested in "$filter" "$worker"; do
        codesign --verify --strict "$nested" || fail "$arch nested signature is broken: $nested"
        nested_team="$(team "$nested")" || fail "$arch nested bundle has no signing team: $nested"
        [[ "$nested_team" == "$app_team" ]] || fail "$arch nested signing team differs: $nested"
    done
# What the user's Mac will decide about this exact download. A build that is
# signed but not notarised passes every check above and is still blocked on a
# first install, which is the one thing the served copy has to prove.
    verdict="$(spctl -a -vvv -t exec "$app" 2>&1)" || fail "$arch app was refused by Gatekeeper"
    [[ "$verdict" == *"source=Notarized Developer ID"* ]] || fail "$arch app is not notarised"
    xcrun stapler validate "$app" >/dev/null 2>&1 || fail "$arch app has no valid stapled ticket"
    entitlements="$(codesign -d --entitlements - "$app" 2>/dev/null)" || fail "$arch app has no readable entitlements"
    python3 -c 'import plistlib,sys
if plistlib.loads(sys.stdin.buffer.read()).get("com.apple.developer.system-extension.install") is not True:
    raise SystemExit(1)' <<< "$entitlements" || fail "$arch app cannot install its network filter"
done

for dmg in Hop.dmg Hop-intel.dmg; do
    fetch "$BASE/$dmg" "$TMP/$dmg"
    xcrun stapler validate "$TMP/$dmg" >/dev/null 2>&1 || fail "$dmg has no valid stapled ticket"
done

# Every mirror, byte for byte: a mirror that lags tells the copies reaching it
# that there is nothing new.
check_mirror_payload() {
    local base="$1" name="$2" original="$3"
    fetch "$base/$name" "$TMP/mirror-payload"
    [[ "$(sha "$TMP/mirror-payload")" == "$(sha "$original")" ]] || fail "mirror serves different bytes: $base/$name"
}
typeset -a MIRRORS
MIRRORS=(${HOP_MIRROR_HOSTS:-ru.hop.tools})
for host in $MIRRORS; do
    base="https://$host/downloads/hop"
    fetch "$base/latest.json" "$TMP/mirror.json"
    [[ "$(sha "$TMP/mirror.json")" == "$(sha "$TMP/latest.json")" ]] || fail "mirror $host serves a different manifest"
    for index in 1 2; do
        arch="${ARCHS[$index]}"
        zip_url="${ZIP_URLS[$index]}"
        sig_url="${SIG_URLS[$index]}"
        check_mirror_payload "$base" "${zip_url:t}" "$TMP/$arch.zip"
        check_mirror_payload "$base" "${sig_url:t}" "$TMP/$arch.sig"
    done
    for dmg in Hop.dmg Hop-intel.dmg; do
        check_mirror_payload "$base" "$dmg" "$TMP/$dmg"
    done
    echo "✓ mirror $host serves identical ARM and Intel release files"
done

echo "✓ release $VERSION is live and correct: ARM and Intel archives, Ed25519 signatures, bundles, helpers and notarised DMGs match on every mirror"
