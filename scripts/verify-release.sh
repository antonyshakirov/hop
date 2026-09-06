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
BASE="https://hop.tools/downloads/hop"
DMG_URL="https://hop.tools/downloads/hop/Hop.dmg"

fail() { echo "❌ $1"; exit 1 }

TMP="$(mktemp -d -t hop-verify)"
trap 'rm -rf "$TMP"' EXIT

curl -fsS --max-time 30 "$BASE/latest.json" -o "$TMP/latest.json" \
    || fail "latest.json is unreachable"

LIVE_VERSION="$(python3 -c "import json;print(json.load(open('$TMP/latest.json'))['version'])")"
[[ "$LIVE_VERSION" == "$VERSION" ]] \
    || fail "live latest.json says '$LIVE_VERSION', expected '$VERSION' — deploy the site first"

ZIP_URL="$(python3 -c "import json;print(json.load(open('$TMP/latest.json'))['zip'])")"
SIG_URL="$(python3 -c "import json;print(json.load(open('$TMP/latest.json'))['sig'])")"

curl -fsS --max-time 120 "$ZIP_URL" -o "$TMP/release.zip" \
    || fail "the zip the manifest points to is NOT being served: $ZIP_URL"
curl -fsS --max-time 30 "$SIG_URL" -o "$TMP/release.sig" \
    || fail "the signature is NOT being served: $SIG_URL"

ZIP_SIZE="$(stat -f%z "$TMP/release.zip")"
(( ZIP_SIZE > 1000000 )) || fail "zip is suspiciously small ($ZIP_SIZE bytes)"
SIG_SIZE="$(stat -f%z "$TMP/release.sig")"
(( SIG_SIZE == 64 )) || fail "signature is $SIG_SIZE bytes, expected 64 (raw Ed25519)"

ditto -x -k "$TMP/release.zip" "$TMP/x" || fail "the served zip does not unpack"
BUNDLE_VERSION="$(plutil -extract CFBundleShortVersionString raw "$TMP/x/Hop.app/Contents/Info.plist")"
[[ "$BUNDLE_VERSION" == "$VERSION" ]] \
    || fail "the served zip contains Hop $BUNDLE_VERSION, expected $VERSION"

# What the user's Mac will decide about this exact download. A build that is
# signed but not notarised passes every check above and is still blocked on a
# first install, which is the one thing the served copy has to prove.
VERDICT="$(spctl -a -vvv -t exec "$TMP/x/Hop.app" 2>&1 || true)"
[[ "$VERDICT" == *"source=Notarized Developer ID"* ]] \
    || fail "the served app is not notarised — Gatekeeper says: $VERDICT"
xcrun stapler validate "$TMP/x/Hop.app" >/dev/null 2>&1 \
    || fail "the served app carries no stapled ticket — a first launch offline would be blocked"

curl -fsS --max-time 120 "$DMG_URL" -o "$TMP/Hop.dmg" || fail "served DMG is unreachable"
xcrun stapler validate "$TMP/Hop.dmg" >/dev/null 2>&1 \
    || fail "the served DMG carries no stapled ticket"

# Every mirror, byte for byte: a mirror that lags tells the copies reaching it
# that there is nothing new.
ZIP_SHA="$(shasum -a 256 "$TMP/release.zip" | cut -d' ' -f1)"
SIG_SHA="$(shasum -a 256 "$TMP/release.sig" | cut -d' ' -f1)"
typeset -a MIRRORS
MIRRORS=(${HOP_MIRROR_HOSTS:-ru.hop.tools})
for host in $MIRRORS; do
    base="https://$host/downloads/hop"
    curl -fsS --max-time 30 "$base/latest.json" -o "$TMP/mirror.json" \
        || fail "mirror $host does not serve latest.json"
    mirror_version="$(python3 -c "import json;print(json.load(open('$TMP/mirror.json'))['version'])")"
    [[ "$mirror_version" == "$VERSION" ]] \
        || fail "mirror $host says '$mirror_version', expected '$VERSION'"
    curl -fsS --max-time 120 "$base/$(basename "$ZIP_URL")" -o "$TMP/mirror.zip" \
        || fail "mirror $host does not serve the zip"
    curl -fsS --max-time 30 "$base/$(basename "$SIG_URL")" -o "$TMP/mirror.sig" \
        || fail "mirror $host does not serve the signature"
    [[ "$(shasum -a 256 "$TMP/mirror.zip" | cut -d' ' -f1)" == "$ZIP_SHA" ]] \
        || fail "mirror $host serves a DIFFERENT zip"
    [[ "$(shasum -a 256 "$TMP/mirror.sig" | cut -d' ' -f1)" == "$SIG_SHA" ]] \
        || fail "mirror $host serves a different signature"
    curl -fsS --max-time 120 "$base/Hop.dmg" -o /dev/null \
        || fail "mirror $host does not serve the DMG"
    echo "✓ mirror $host serves $VERSION, identical zip and signature"
done

echo "✓ release $VERSION is live and correct: latest.json → zip (bundle $BUNDLE_VERSION, $ZIP_SIZE bytes, notarised) + 64-byte sig + notarised DMG, on every mirror"
