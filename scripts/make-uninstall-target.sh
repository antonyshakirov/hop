#!/usr/bin/env bash
# A harmless app that exists only to be uninstalled, plus a file in EVERY place
# an uninstaller is supposed to look. It is how the uninstaller module is scored —
# and how any other uninstaller can be scored against it on the same footing.
#
#   ./scripts/make-uninstall-target.sh          # create the app and seed traces
#   ./scripts/make-uninstall-target.sh --system # also the /Library places (sudo)
#   ./scripts/make-uninstall-target.sh --check   # what is still on disk
#   ./scripts/make-uninstall-target.sh --clean   # remove everything it made
#
# The app does nothing: its executable is a shell script that exits. Nothing is
# ever installed, registered or launched, so seeding and checking are safe to
# repeat as often as a comparison needs.
set -euo pipefail

APP_NAME="Hop Uninstall Test"
BUNDLE_ID="com.antonshakirov.hop-uninstall-test"
TEAM="ABCDE12345"
APP="/Applications/$APP_NAME.app"
LIB="$HOME/Library"

# Every path this fixture creates. The uninstaller's own list of folders is the
# spec; this is the same list written as files, which is what makes the score
# objective: a tool either moves these or it does not.
user_paths=(
    "$LIB/Application Support/$BUNDLE_ID"
    "$LIB/Application Support/$APP_NAME"
    "$LIB/Caches/$BUNDLE_ID"
    "$LIB/Caches/$BUNDLE_ID.ShipIt"
    "$LIB/Preferences/$BUNDLE_ID.plist"
    "$LIB/Preferences/ByHost/$BUNDLE_ID.00000000-0000-0000-0000-000000000000.plist"
    "$LIB/Containers/$BUNDLE_ID"
    "$LIB/Containers/$BUNDLE_ID.Share"
    "$LIB/Group Containers/$TEAM.$BUNDLE_ID"
    "$LIB/Application Scripts/$BUNDLE_ID"
    "$LIB/Saved Application State/$BUNDLE_ID.savedState"
    "$LIB/HTTPStorages/$BUNDLE_ID"
    "$LIB/WebKit/$BUNDLE_ID"
    "$LIB/Logs/$APP_NAME"
    "$LIB/Logs/DiagnosticReports/${APP_NAME}_2026-07-30-120000.ips"
    "$LIB/Cookies/$BUNDLE_ID.binarycookies"
    "$LIB/Autosave Information/$BUNDLE_ID"
    "$LIB/LaunchAgents/$BUNDLE_ID.plist"
    "$LIB/Application Support/CrashReporter/${APP_NAME}_2026-07-30-120000.plist"
    # the plug-in style leftovers a real app installs and never takes back
    "$LIB/Internet Plug-Ins/$APP_NAME.plugin"
    "$LIB/PreferencePanes/$APP_NAME.prefPane"
    "$LIB/QuickLook/$APP_NAME.qlgenerator"
    "$LIB/Spotlight/$APP_NAME.mdimporter"
    "$LIB/Services/$APP_NAME.workflow"
    "$LIB/Widgets/$APP_NAME.wdgt"
    "$LIB/Screen Savers/$APP_NAME.saver"
    "$LIB/Input Methods/$APP_NAME.app"
    "$LIB/ColorPickers/$APP_NAME.colorPicker"
    "$LIB/Frameworks/$APP_NAME.framework"
    "$LIB/Audio/Plug-Ins/HAL/$APP_NAME.driver"
    "$LIB/Audio/Plug-Ins/Components/$APP_NAME.component"
)
system_paths=(
    "/Library/Application Support/$BUNDLE_ID"
    "/Library/Preferences/$BUNDLE_ID.plist"
    "/Library/Caches/$BUNDLE_ID"
    "/Library/LaunchAgents/$BUNDLE_ID.plist"
    "/Library/LaunchDaemons/$BUNDLE_ID.helper.plist"
    "/Library/PrivilegedHelperTools/$BUNDLE_ID"
    "/Users/Shared/$APP_NAME"
    "/var/db/receipts/$BUNDLE_ID.bom"
    "/var/db/receipts/$BUNDLE_ID.plist"
    "/Library/Internet Plug-Ins/$APP_NAME.plugin"
    "/Library/PreferencePanes/$APP_NAME.prefPane"
    "/Library/QuickLook/$APP_NAME.qlgenerator"
    "/Library/Frameworks/$APP_NAME.framework"
    "/Library/Audio/Plug-Ins/HAL/$APP_NAME.driver"
)

WITH_SYSTEM=false
MODE=seed
for arg in "$@"; do
    case "$arg" in
        --system) WITH_SYSTEM=true ;;
        --check) MODE=check ;;
        --clean) MODE=clean ;;
        *) echo "unknown option: $arg"; exit 1 ;;
    esac
done

make_app() {
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>test</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
</dict>
</plist>
PLIST
    printf '#!/bin/sh\nexit 0\n' > "$APP/Contents/MacOS/test"
    chmod +x "$APP/Contents/MacOS/test"
    # a megabyte of nothing, so the app has a size worth reporting
    mkdir -p "$APP/Contents/Resources"
    dd if=/dev/zero of="$APP/Contents/Resources/filler.bin" bs=1024 count=1024 2>/dev/null
}

# A few of these folders are protected by macOS itself — ~/Library/Cookies needs
# Full Disk Access — so a refusal is reported and skipped rather than aborting the
# run: a fixture that dies halfway is worse than one with a hole it names.
skipped=()
seed_one() {
    local path="$1" sudo_prefix="${2:-}"
    local target="$path"
    if [[ "$path" == *.plist || "$path" == *.savedState || "$path" == *.binarycookies \
          || "$path" == *.ips || "$path" == *.bom ]]; then
        $sudo_prefix mkdir -p "$(dirname "$path")" 2>/dev/null || true
    else
        $sudo_prefix mkdir -p "$path" 2>/dev/null || true
        target="$path/data.txt"
    fi
    if ! printf 'hop uninstall test fixture\n' | $sudo_prefix tee "$target" >/dev/null 2>&1; then
        skipped+=("$path")
    fi
}

case "$MODE" in
seed)
    make_app
    for path in "${user_paths[@]}"; do seed_one "$path"; done
    echo "created: $APP"
    echo "seeded : $(( ${#user_paths[@]} - ${#skipped[@]} )) of ${#user_paths[@]} user-level traces"
    if $WITH_SYSTEM; then
        echo "the /Library and receipt places need an administrator:"
        for path in "${system_paths[@]}"; do seed_one "$path" sudo; done
        echo "seeded : ${#system_paths[@]} system-level traces"
    else
        echo "skipped: system-level traces (pass --system to include them)"
    fi
    if (( ${#skipped[@]} )); then
        echo "refused by macOS (needs full disk access), left out of the score:"
        for path in "${skipped[@]}"; do echo "  $path"; done
    fi
    echo
    echo "now compare — every tool gets the same target:"
    echo "  ./.build/debug/Hop --uninstall-scan '$APP'"
    echo "  …or point another uninstaller at $APP_NAME, then:"
    echo "  ./scripts/make-uninstall-target.sh --check"
    ;;
check)
    left=0
    total=0
    for path in "${user_paths[@]}" "${system_paths[@]}"; do
        [[ "$path" == /Library/* || "$path" == /var/db/* || "$path" == /Users/Shared/* ]] \
            && ! $WITH_SYSTEM && [[ ! -e "$path" ]] && continue
        total=$((total + 1))
        if [[ -e "$path" ]]; then
            left=$((left + 1))
            echo "LEFT: $path"
        fi
    done
    [[ -e "$APP" ]] && { echo "LEFT: $APP"; left=$((left + 1)); total=$((total + 1)); }
    echo
    echo "$left of $total seeded traces are still on disk"
    ;;
clean)
    rm -rf "$APP"
    for path in "${user_paths[@]}"; do rm -rf "$path"; done
    echo "removed the app and its user-level traces"
    echo "the /Library ones, if seeded, need: sudo rm -rf '/Library/Application Support/$BUNDLE_ID' …"
    ;;
esac
