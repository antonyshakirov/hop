#!/bin/zsh
# Hop release: ./scripts/release.sh 1.0.1 [--critical]
# Builds Hop.app, signs it with Developer ID, has Apple notarise it, staples the
# ticket, zips it, signs the zip with Ed25519, writes latest.json and uploads
# the lot to the site's server. The site repo only learns the version number.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/signing.sh

VERSION="${1:?usage: release.sh <version> [--critical]}"
CRITICAL=false
[[ "${2:-}" == "--critical" ]] && CRITICAL=true

SITE_DIR="${HOP_SITE_DIR:-$HOME/Development Projects/Products Platform/projects/hop-website}"
[[ -d "$SITE_DIR/src" ]] || { echo "site repo not found: $SITE_DIR"; exit 1 }
# Outside the static site's root: the site deploy syncs with --delete.
SITE_SSH="${HOP_SITE_SSH:-atelier-nl}"
SITE_DOWNLOADS="${HOP_SITE_DOWNLOADS:-/var/www/hop-website/downloads/hop}"
[[ -f "$HOME/.minimo-release-key" ]] || { echo "signing key ~/.minimo-release-key not found"; exit 1 }

# SPEC: docs/spec.md — "Signing, notarisation, and why permissions must survive
# an update". Everything Apple has to accept is proven before the build, not
# after it.
IDENTITY="$(hop_signing_identity)"
[[ -n "$IDENTITY" ]] || {
    echo "no Developer ID Application certificate in the login keychain."
    echo "Without it a release is neither trusted by Gatekeeper nor notarisable,"
    echo "and it would reset every user's permissions. Restore it first."
    exit 1
}
DAYS_LEFT="$(hop_certificate_days_left || true)"
if [[ -n "$DAYS_LEFT" ]]; then
    (( DAYS_LEFT > 0 )) || {
        echo "the Developer ID certificate expired ${DAYS_LEFT#-} days ago — renew it"
        exit 1
    }
    if (( DAYS_LEFT > 30 )); then
        echo "signing as: $IDENTITY ($DAYS_LEFT days left)"
    else
        echo "⚠ signing as: $IDENTITY — the certificate expires in $DAYS_LEFT days"
    fi
fi

[[ -f .env ]] || {
    echo "no .env — copy .env.example and fill in the app-specific password."
    exit 1
}
eval "$(python3 - <<'PYENV'
import re, shlex
for line in open(".env"):
    match = re.match(r"^(APPLE_[A-Z_]+)=(.*)$", line.strip())
    if match:
        print(f"export {match.group(1)}={shlex.quote(match.group(2))}")
PYENV
)"
for name in APPLE_ID APPLE_TEAM_ID APPLE_APP_PASSWORD; do
    [[ -n "${(P)name:-}" ]] || { echo ".env is missing $name"; exit 1 }
done
xcrun notarytool history --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" >/dev/null 2>&1 || {
    echo "Apple refuses these notary credentials — check APPLE_ID and the"
    echo "app-specific password in .env (appleid.apple.com → Sign-In and Security)."
    exit 1
}

# Nothing is packaged from a red tree: build, tests and translations first —
# the same script CI and the pre-push hook run. A release that fails its own
# checks is not a release (2026-08-29).
scripts/checks.sh

# the version is baked into Info.plist BEFORE the build
plutil -replace CFBundleShortVersionString -string "$VERSION" scripts/Info.plist

./scripts/build-app.sh

# WORKAROUND: notarytool can exit zero on a submission Apple rejected, so the
# status line is read as well.
notarize() {
    local file="$1" output
    echo "notarising $(basename "$file")…"
    output=$(xcrun notarytool submit "$file" \
        --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_PASSWORD" --wait --timeout 30m 2>&1) || {
        echo "$output"
        echo "notarisation failed for $(basename "$file")"
        exit 1
    }
    if [[ "$output" != *"status: Accepted"* ]]; then
        echo "$output"
        local id
        id=$(echo "$output" | sed -n 's/.*id: \([0-9a-f-]\{36\}\).*/\1/p' | head -1)
        [[ -n "$id" ]] && xcrun notarytool log "$id" \
            --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
            --password "$APPLE_APP_PASSWORD" 2>&1 | head -40
        echo "notarisation was not accepted for $(basename "$file")"
        exit 1
    fi
}

# One universal build, split into two single-architecture bundles. Shipping the
# universal binary to everyone would double every download and every update for
# a slice the machine cannot run; thinning it means each Mac gets exactly what it
# needs, and both halves are the same compile (Anton, 2026-07-29).
build_slice() {
    local arch="$1" dir="dist/$1"
    rm -rf "$dir"
    mkdir -p "$dir"
    cp -R dist/Hop.app "$dir/Hop.app"
    lipo "$dir/Hop.app/Contents/MacOS/Hop" -thin "$arch" -output "$dir/Hop.app/Contents/MacOS/Hop"
    # thinning invalidates the signature — sign the bundle again, as build-app.sh does
    hop_sign_app "$dir/Hop.app" "$IDENTITY"
    hop_verify_signature "$dir/Hop.app" "$IDENTITY" || {
        echo "wrong or broken signature in $arch build"; exit 1
    }
    ditto -c -k --keepParent "$dir/Hop.app" "dist/notarize-$arch.zip"
    notarize "dist/notarize-$arch.zip"
    rm -f "dist/notarize-$arch.zip"
    xcrun stapler staple "$dir/Hop.app" >/dev/null || {
        echo "stapling failed: $arch"; exit 1
    }
    local verdict
    verdict=$(spctl -a -vvv -t exec "$dir/Hop.app" 2>&1)
    [[ "$verdict" == *"source=Notarized Developer ID"* ]] || {
        echo "$verdict"
        echo "Gatekeeper does not see the $arch build as notarised"; exit 1
    }
}
build_slice arm64
build_slice x86_64

ZIP="dist/Hop-$VERSION.zip"                 # arm64 keeps the historical name:
ZIP_INTEL="dist/Hop-$VERSION-intel.zip"     # every client before 1.7.0 reads it
rm -f "$ZIP" "$ZIP.sig" "$ZIP_INTEL" "$ZIP_INTEL.sig"
ditto -c -k --keepParent dist/arm64/Hop.app "$ZIP"
ditto -c -k --keepParent dist/x86_64/Hop.app "$ZIP_INTEL"
swift scripts/sign-release.swift "$ZIP" | tail -1
swift scripts/sign-release.swift "$ZIP_INTEL" | tail -1

# polished DMGs for the landing page: one per architecture, offered separately
sign_dmg() {
    local dmg="$1"
    codesign --force --timestamp --sign "$IDENTITY" "$dmg"
    notarize "$dmg"
    xcrun stapler staple "$dmg" >/dev/null || { echo "stapling failed: $dmg"; exit 1 }
}
./scripts/make-dmg.sh dist/arm64/Hop.app dist/Hop.dmg
./scripts/make-dmg.sh dist/x86_64/Hop.app dist/Hop-intel.dmg
sign_dmg dist/Hop.dmg
sign_dmg dist/Hop-intel.dmg
# Both images are uploaded further down, together with the zips.

# Homebrew tap: version and both checksums, written here so `brew install` can
# never lag a release behind again — the tap sat at 1.5.1 while 1.6.0 was already
# downloading from the site (found 2026-07-29).
TAP_CASK="${HOP_TAP_CASK:-$HOME/Development Projects/Products Platform/projects/homebrew-tap/Casks/hop.rb}"
if [[ -f "$TAP_CASK" ]]; then
    ARM_SHA=$(shasum -a 256 dist/Hop.dmg | awk '{print $1}')
    INTEL_SHA=$(shasum -a 256 dist/Hop-intel.dmg | awk '{print $1}')
    VERSION="$VERSION" ARM_SHA="$ARM_SHA" INTEL_SHA="$INTEL_SHA" TAP_CASK="$TAP_CASK" python3 - <<'PYEOF'
import os, re
# The whole head of the cask is REGENERATED — version and both blocks together —
# rather than patched line by line, so the checksum can never drift from the
# image it is supposed to pin, and an Intel block never exists without a real
# hash of a real file (a `sha256 :no_check` would accept whatever the URL serves).
path = os.environ["TAP_CASK"]
text = open(path, encoding="utf-8").read()
head = '''  version "%s"

  # One build per architecture: each carries only the code its own processor
  # runs, so neither download is heavier than it has to be.
  on_arm do
    sha256 "%s"
    url "https://github.com/antonyshakirov/hop/releases/download/v#{version}/Hop.dmg"
  end
  on_intel do
    sha256 "%s"
    url "https://github.com/antonyshakirov/hop/releases/download/v#{version}/Hop-intel.dmg"
  end
''' % (os.environ["VERSION"], os.environ["ARM_SHA"], os.environ["INTEL_SHA"])
new, count = re.subn(r'  version ".*?\n(.*?)\n(?=  name "Hop")', head, text,
                     count=1, flags=re.S)
if count != 1:
    raise SystemExit("cask head not recognised — update %s by hand" % path)
open(path, "w", encoding="utf-8").write(new)
print("cask updated:", os.environ["VERSION"])
PYEOF
else
    echo "⚠ tap cask not found at $TAP_CASK — update it by hand"
fi

BASE="https://hop.tools/downloads/hop"
# `zip`/`sig` stay the arm64 build under their historical names, so a client from
# before 1.7.0 keeps updating; an Intel one reads the `…Intel` pair instead.
STAGE="$(mktemp -d)"
cat > "$STAGE/latest.json" << JSON
{
  "version": "$VERSION",
  "zip": "$BASE/Hop-$VERSION.zip",
  "sig": "$BASE/Hop-$VERSION.zip.sig",
  "zipIntel": "$BASE/Hop-$VERSION-intel.zip",
  "sigIntel": "$BASE/Hop-$VERSION-intel.zip.sig",
  "critical": $CRITICAL,
  "date": "$(date -u +%Y-%m-%d)"
}
JSON

# Builds first, latest.json last: a manifest naming files the server does not
# have yet sends every installed copy to a 404.
cp dist/Hop.dmg dist/Hop-intel.dmg "$STAGE/"
# Symbolic mode, not `F644`: macOS ships openrsync now, which refuses every
# numeric form and takes this one. GNU rsync understands it too, so the script
# runs the same on a machine that still has it (1.10.0 release, 2026-09-03).
UPLOAD_MODE="u=rw,go=r"
rsync -az --chmod="$UPLOAD_MODE" \
    "$ZIP" "$ZIP.sig" "$ZIP_INTEL" "$ZIP_INTEL.sig" \
    "$STAGE/Hop.dmg" "$STAGE/Hop-intel.dmg" \
    "$SITE_SSH:$SITE_DOWNLOADS/" \
    || { echo "upload of the builds failed"; exit 1 }
rsync -az --chmod="$UPLOAD_MODE" "$STAGE/latest.json" "$SITE_SSH:$SITE_DOWNLOADS/" \
    || { echo "upload of latest.json failed"; exit 1 }
rm -rf "$STAGE"
echo "uploaded to $SITE_SSH:$SITE_DOWNLOADS"

# The landing shows the version in its hero, its footer and its
# SoftwareApplication markup, out of one constant. Leaving that to a human meant
# it silently fell two releases behind — the site advertised 1.5.0 while 1.5.2
# was already downloading (Anton, 2026-07-28). Written here, it cannot drift.
CONFIG="$SITE_DIR/src/views/hop/config.ts"
if [[ -f "$CONFIG" ]]; then
    /usr/bin/sed -i '' -E "s/^export const HOP_VERSION = \".*\";$/export const HOP_VERSION = \"$VERSION\";/" "$CONFIG"
    grep -q "HOP_VERSION = \"$VERSION\"" "$CONFIG" \
        || { echo "could not set HOP_VERSION in $CONFIG"; exit 1 }
    echo "landing HOP_VERSION → $VERSION"
else
    echo "warning: $CONFIG not found, landing version left alone"
fi

# hop-dl CDN zone (Bunny, id 6152002): Hop.dmg lives under an UNversioned
# name — without a purge after a release the CDN would serve the old DMG until TTL expires.
# Look for the key in env, then in the Essentóne site .env (it already lives there).
BUNNY_KEY="${BUNNY_API_KEY:-}"
if [[ -z "$BUNNY_KEY" ]]; then
    ESS_ENV="$HOME/Development Projects/Products Platform/projects/essentone/development/website/.env"
    [[ -f "$ESS_ENV" ]] && BUNNY_KEY="$(grep -E '^BUNNY_API_KEY=' "$ESS_ENV" | cut -d= -f2- | tr -d '"')"
fi
if [[ -n "$BUNNY_KEY" ]]; then
    curl -s -X POST "https://api.bunny.net/pullzone/6152002/purgeCache" \
        -H "AccessKey: $BUNNY_KEY" -H "Content-Length: 0" > /dev/null \
        && echo "CDN hop-dl: cache purged"
else
    echo "⚠ BUNNY_API_KEY not found — purge the hop-dl zone cache manually in the Bunny panel"
fi

echo ""
echo "release $VERSION is ready and already served:"
echo "  $BASE/{latest.json, Hop-$VERSION.zip, -intel.zip, .sig, Hop.dmg}"
echo "next: 1) commit the site repo (HOP_VERSION) + ./deploy.sh — the landing prints the version;"
echo "      1b) commit the tap (Casks/hop.rb — version + both checksums are written already);"
echo "      2) ./scripts/verify-release.sh $VERSION  # MUST print the checkmark;"
echo "      3) only then: git tag v$VERSION + push;"
echo "         gh release create v$VERSION \"$ZIP\" \"$ZIP.sig\" \"$ZIP_INTEL\" \"$ZIP_INTEL.sig\" dist/Hop.dmg dist/Hop-intel.dmg -R antonyshakirov/hop"
