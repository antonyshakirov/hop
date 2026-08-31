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

# hop_sign_app <bundle> <identity> [no-timestamp]
hop_sign_app() {
    local app="$1" identity="$2" timestamp="${3:-timestamp}"
    local args=(--force --options runtime --entitlements "$HOP_ENTITLEMENTS")
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
