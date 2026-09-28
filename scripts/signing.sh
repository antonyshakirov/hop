#!/bin/zsh
# SPEC: docs/spec.md — "Signing, notarisation, and why permissions must survive
# an update". Sourced by build-app.sh and release.sh.

HOP_ENTITLEMENTS="scripts/Hop.entitlements"

# → the Developer ID Application identity in the login keychain, empty if none.
hop_signing_identity() {
    security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' \
        | head -1
}

# hop_sign_app <bundle> <identity> [no-timestamp] [entitlements]
hop_sign_app() {
    local app="$1" identity="$2" timestamp="${3:-timestamp}" entitlements="${4:-$HOP_ENTITLEMENTS}"
    local args=(--force --options runtime --entitlements "$entitlements")
    if [[ "$timestamp" == "no-timestamp" ]]; then
        args+=(--timestamp=none)
    else
        args+=(--timestamp)
    fi
    codesign "${args[@]}" --sign "$identity" "$app"
}

# WORKAROUND: `codesign | grep -q` makes grep leave early, codesign dies of
# SIGPIPE, and `set -o pipefail` turns a correct signature into a failed build.
hop_verify_signature() {
    local app="$1" identity="$2"
    codesign --verify --strict "$app" || return 1
    local info
    info=$(codesign -dvv "$app" 2>&1)
    [[ "$info" == *"Authority=$identity"* ]] || return 1
}

# → days until the Developer ID certificate expires; fails if it cannot be read.
hop_certificate_days_left() {
    local end
    end=$(security find-certificate -c "Developer ID Application" -p 2>/dev/null \
        | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
    [[ -n "$end" ]] || return 1
    local expiry now
    expiry=$(date -j -f "%b %d %T %Y %Z" "$end" +%s 2>/dev/null) || return 1
    now=$(date +%s)
    echo $(( (expiry - now) / 86400 ))
}

# SPEC: docs/spec.md — "Network access". Wraps the HopNetFilter binary into
# <app>/Contents/Library/SystemExtensions, signs it with its own profile, and
# writes the app's extra entitlements to $HOP_NETWORK_ENTITLEMENTS. Returns 1
# (and leaves the app untouched) when the profiles are not on this machine.
# hop_embed_network_filter <app> <filter binary> <identity> <timestamp>
hop_embed_network_filter() {
    local app="$1" binary="$2" identity="$3" timestamp="$4"
    local profiles=~/.minimo-signing/profiles
    local app_id ext_id
    app_id=$(plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist")
    ext_id="$app_id.netfilter"
    [[ -f "$profiles/$app_id.provisionprofile" && -f "$profiles/$ext_id.provisionprofile" ]] || return 1
    local team
    team=$(security cms -D -i "$profiles/$app_id.provisionprofile" 2>/dev/null \
        | plutil -extract TeamIdentifier.0 raw - 2>/dev/null) || return 1

    local ext="$app/Contents/Library/SystemExtensions/$ext_id.systemextension"
    rm -rf "$app/Contents/Library/SystemExtensions"
    mkdir -p "$ext/Contents/MacOS"
    cp "$binary" "$ext/Contents/MacOS/$ext_id"
    sed -e "s/EXTENSION_ID/$ext_id/g" -e "s/MACH_SERVICE/$team.$ext_id/" \
        scripts/HopNetFilter-Info.plist > "$ext/Contents/Info.plist"
    local version
    version=$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")
    plutil -replace CFBundleShortVersionString -string "$version" "$ext/Contents/Info.plist"
    plutil -replace CFBundleVersion -string "$version" "$ext/Contents/Info.plist"
    cp "$profiles/$ext_id.provisionprofile" "$ext/Contents/embedded.provisionprofile"

    local work
    work=$(mktemp -d)
    cat > "$work/filter.entitlements" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.application-identifier</key><string>$team.$ext_id</string>
<key>com.apple.developer.team-identifier</key><string>$team</string>
<key>com.apple.developer.networking.networkextension</key><array><string>content-filter-provider-systemextension</string></array>
<key>com.apple.security.application-groups</key><array><string>$team.$app_id</string></array>
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.network.client</key><true/>
</dict></plist>
PLIST
    hop_sign_app "$ext" "$identity" "$timestamp" "$work/filter.entitlements" || return 1

    cp "$profiles/$app_id.provisionprofile" "$app/Contents/embedded.provisionprofile"
    cp "$HOP_ENTITLEMENTS" "$work/app.entitlements"
    # PlistBuddy, not plutil: plutil reads the dots in these keys as a path.
    local buddy=/usr/libexec/PlistBuddy
    $buddy -c "Add :com.apple.application-identifier string $team.$app_id" \
        -c "Add :com.apple.developer.team-identifier string $team" \
        -c "Add :com.apple.developer.system-extension.install bool true" \
        -c "Add :com.apple.developer.networking.networkextension array" \
        -c "Add :com.apple.developer.networking.networkextension:0 string content-filter-provider-systemextension" \
        "$work/app.entitlements" || return 1
    HOP_NETWORK_ENTITLEMENTS="$work/app.entitlements"
}
