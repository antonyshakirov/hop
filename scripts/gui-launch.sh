#!/bin/zsh
# SPEC: docs/spec.md — Signing, notarisation, and developer installation.
hop_gui_temporary_directory() {
    /usr/bin/getconf DARWIN_USER_TEMP_DIR
}

hop_gui_run() {
    local gui_home="${HOME:-}" gui_user gui_tmp
    [[ "$gui_home" == /* && -d "$gui_home" ]] || return 1
    gui_user=$(/usr/bin/id -un) || return 1
    [[ -n "$gui_user" ]] || return 1
    gui_tmp=$(hop_gui_temporary_directory) || return 1
    [[ "$gui_tmp" == /* && -d "$gui_tmp" ]] || return 1
    /usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$gui_home" \
        USER="$gui_user" LOGNAME="$gui_user" TMPDIR="$gui_tmp" "$@"
}
