#!/bin/zsh
# Hop release: ./scripts/release.sh 1.0.1 [--critical]
# Builds Hop.app, zips it, signs with Ed25519, writes latest.json and
# lays everything out in the site repo (public/hop/). Site deploy is separate.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: release.sh <version> [--critical]}"
CRITICAL=false
[[ "${2:-}" == "--critical" ]] && CRITICAL=true

SITE_DIR="${HOP_SITE_DIR:-$HOME/Development Projects/Products Platform/projects/antonshakirov-com/development}"
[[ -d "$SITE_DIR/public" ]] || { echo "site repo not found: $SITE_DIR"; exit 1 }
[[ -f "$HOME/.minimo-release-key" ]] || { echo "signing key ~/.minimo-release-key not found"; exit 1 }

# the version is baked into Info.plist BEFORE the build
plutil -replace CFBundleShortVersionString -string "$VERSION" scripts/Info.plist

./scripts/build-app.sh

# One universal build, split into two single-architecture bundles. Shipping the
# universal binary to everyone would double every download and every update for
# a slice the machine cannot run; thinning it means each Mac gets exactly what it
# needs, and both halves are the same compile (Anton, 2026-07-29).
# The SAME identity build-app.sh uses. macOS ties a permission — full disk
# access above all — to the app's code signature, so a release signed ad hoc is
# a different app to the system every single time: every user who had granted
# anything is asked again after every update (Anton, 2026-07-30). Signing here
# with the stable certificate is what makes a grant survive an update, and a
# missing certificate stops the release rather than quietly costing everyone
# their permissions.
IDENTITY="Minimo Signing"
security find-certificate -c "$IDENTITY" >/dev/null 2>&1 || {
    echo "signing certificate '$IDENTITY' not found — a release signed ad hoc"
    echo "would reset every user's permissions on update. Restore it first."
    exit 1
}

build_slice() {
    local arch="$1" dir="dist/$1"
    rm -rf "$dir"
    mkdir -p "$dir"
    cp -R dist/Hop.app "$dir/Hop.app"
    lipo "$dir/Hop.app/Contents/MacOS/Hop" -thin "$arch" -output "$dir/Hop.app/Contents/MacOS/Hop"
    # thinning invalidates the signature — sign the bundle again, as build-app.sh does
    codesign --force --deep --sign "$IDENTITY" "$dir/Hop.app" 2>/dev/null
    codesign --verify --deep "$dir/Hop.app" || { echo "signature failed: $arch"; exit 1 }
    codesign -dv "$dir/Hop.app" 2>&1 | grep -q "Authority=$IDENTITY" || {
        echo "wrong signing authority in $arch build"; exit 1
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
./scripts/make-dmg.sh dist/arm64/Hop.app dist/Hop.dmg
./scripts/make-dmg.sh dist/x86_64/Hop.app dist/Hop-intel.dmg
mkdir -p "$SITE_DIR/public/products/hop"
cp dist/Hop.dmg "$SITE_DIR/public/products/hop/Hop.dmg"
cp dist/Hop-intel.dmg "$SITE_DIR/public/products/hop/Hop-intel.dmg"

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

BASE="https://www.antonshakirov.com/downloads/hop"
mkdir -p "$SITE_DIR/public/downloads/hop"
cp "$ZIP" "$ZIP.sig" "$ZIP_INTEL" "$ZIP_INTEL.sig" "$SITE_DIR/public/downloads/hop/"
# `zip`/`sig` stay the arm64 build under their historical names, so a client from
# before 1.7.0 keeps updating; an Intel one reads the `…Intel` pair instead.
cat > "$SITE_DIR/public/downloads/hop/latest.json" << JSON
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
echo "release $VERSION is ready:"
echo "  $SITE_DIR/public/downloads/hop/{latest.json, Hop-$VERSION.zip, -intel.zip, .sig}"
echo "next: 1) commit in the site repo + ./deploy.sh (it self-checks new public names now);"
echo "      1b) commit the tap (Casks/hop.rb — version + both checksums are written already);"
echo "      2) ./scripts/verify-release.sh $VERSION  # MUST print the checkmark;"
echo "      3) only then: git tag v$VERSION + push;"
echo "         gh release create v$VERSION \"$ZIP\" \"$ZIP.sig\" \"$ZIP_INTEL\" \"$ZIP_INTEL.sig\" dist/Hop.dmg dist/Hop-intel.dmg -R antonyshakirov/hop"
