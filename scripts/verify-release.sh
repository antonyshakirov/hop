#!/bin/zsh
# Release gate: proves version X.Y.Z is ACTUALLY live on production before it
# is announced anywhere (git tag, GitHub release, posts). Checks the live
# latest.json, downloads the exact zip it points to, and inspects the bundle
# inside — a reference published before the files themselves would fail here.
#
#   ./scripts/verify-release.sh 1.3.1   # exit 0 = safe to announce
#
# Born from the 1.3.1 incident: the GitHub release went out while the site
# still served 404 for the new zip name (Next's public manifest needs a
# rebuild for NEW files; the deploy now self-checks, and this gate catches
# anything else).
set -euo pipefail

VERSION="${1:?usage: verify-release.sh <version>}"
BASE="https://www.antonshakirov.com/downloads/hop"
DMG_URL="https://www.antonshakirov.com/products/hop/Hop.dmg"

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

curl -fsS --max-time 60 -o /dev/null "$DMG_URL" || fail "landing DMG is unreachable"

echo "✓ release $VERSION is live and correct: latest.json → zip (bundle $BUNDLE_VERSION, $ZIP_SIZE bytes) + 64-byte sig + DMG"
