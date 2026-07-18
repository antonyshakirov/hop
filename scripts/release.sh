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

ZIP="dist/Hop-$VERSION.zip"
rm -f "$ZIP" "$ZIP.sig"
ditto -c -k --keepParent dist/Hop.app "$ZIP"
swift scripts/sign-release.swift "$ZIP" | tail -1

# polished DMG for the landing page download (placed where the site serves it from)
./scripts/make-dmg.sh dist/Hop.app
mkdir -p "$SITE_DIR/public/products/hop"
cp dist/Hop.dmg "$SITE_DIR/public/products/hop/Hop.dmg"

BASE="https://www.antonshakirov.com/downloads/hop"
mkdir -p "$SITE_DIR/public/downloads/hop"
cp "$ZIP" "$ZIP.sig" "$SITE_DIR/public/downloads/hop/"
cat > "$SITE_DIR/public/downloads/hop/latest.json" << JSON
{
  "version": "$VERSION",
  "zip": "$BASE/Hop-$VERSION.zip",
  "sig": "$BASE/Hop-$VERSION.zip.sig",
  "critical": $CRITICAL,
  "date": "$(date -u +%Y-%m-%d)"
}
JSON

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
echo "  $SITE_DIR/public/downloads/hop/{latest.json, Hop-$VERSION.zip, .sig}"
echo "next: commit in the site repo + FORCE_BUILD=1 ./deploy.sh (the NEW zip name needs a rebuild,"
echo "        or Next serves 404 for it); git tag v$VERSION in hop;"
echo "        gh release create v$VERSION \"$ZIP\" \"$ZIP.sig\" dist/Hop.dmg -R antonyshakirov/hop"
