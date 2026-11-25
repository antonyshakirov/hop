#!/bin/zsh
# Hop release upload: ./scripts/upload-release.sh <manifest> <build>...
# SPEC: docs/spec.md — "Mirrors", how a release reaches every host.
set -euo pipefail

MANIFEST="${1:?usage: upload-release.sh <manifest> <build>...}"
shift
(( $# > 0 )) || { echo "usage: upload-release.sh <manifest> <build>..."; exit 2 }
typeset -a BUILDS
BUILDS=("$@")

PRIMARY="${HOP_UPLOAD_PRIMARY:?HOP_UPLOAD_PRIMARY=host:/dir is required}"
PRIMARY_URL="${HOP_UPLOAD_PRIMARY_URL:?HOP_UPLOAD_PRIMARY_URL=https://host/path is required}"
typeset -a MIRRORS
MIRRORS=(${=HOP_UPLOAD_MIRRORS:-})
ATTEMPTS="${HOP_UPLOAD_ATTEMPTS:-3}"
ATTEMPT_SECONDS="${HOP_UPLOAD_ATTEMPT_SECONDS:-300}"
# WORKAROUND: macOS openrsync refuses numeric --chmod forms.
UPLOAD_MODE="u=rw,go=r"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

for file in "$MANIFEST" $BUILDS; do
    [[ -f "$file" ]] || { echo "missing release file: $file"; exit 1 }
done

# WORKAROUND: some connections to the Russian mirror crawl at ~40 KB/s and rsync
# has no speed floor, so every attempt gets a deadline and a fresh connection.
bounded() {
    local seconds="$1" input="$2"; shift 2
    "$@" < "$input" &
    local child=$!
    local waited=0
    while kill -0 "$child" 2>/dev/null; do
        if (( waited >= seconds )); then
            kill -9 "$child" 2>/dev/null || true
            wait "$child" 2>/dev/null || true
            return 124
        fi
        sleep 1
        (( waited += 1 ))
    done
    wait "$child"
}

push() {
    local target="$1"; shift
    local attempt
    for attempt in $(seq 1 "$ATTEMPTS"); do
        if bounded "$ATTEMPT_SECONDS" /dev/null rsync -az --chmod="$UPLOAD_MODE" "$@" "$target/"; then
            return 0
        fi
        echo "upload to $target: attempt $attempt of $ATTEMPTS did not finish"
    done
    return 1
}

quote() { print -r -- "${(qq)1}" }

pull_script() {
    local dir="$1"; shift
    print -r -- "set -eu"
    print -r -- "cd $(quote "$dir")"
    local file name sum
    local -a temps
    for file in "$@"; do temps+=("$(quote ".${file:t}.pull")"); done
    print -r -- "trap \"rm -f ${(j: :)temps}\" EXIT"
    for file in "$@"; do
        name="${file:t}"
        sum="$(shasum -a 256 "$file" | cut -d' ' -f1)"
        print -r -- "curl -fsS --max-time $ATTEMPT_SECONDS -o $(quote ".$name.pull") $(quote "$PRIMARY_URL/$name?sha256=$sum")"
        print -r -- "[ \"\$(sha256sum $(quote ".$name.pull") | cut -d' ' -f1)\" = $sum ] || { echo 'hash mismatch: $name' >&2; exit 1; }"
        print -r -- "chmod 644 $(quote ".$name.pull")"
    done
    for file in "$@"; do
        name="${file:t}"
        print -r -- "mv -f $(quote ".$name.pull") $(quote "$name")"
    done
}

pull() {
    local target="$1"
    local host="${target%%:*}" dir="${target#*:}"
    local script="$WORK/pull.sh"
    pull_script "$dir" $BUILDS > "$script"
    bounded $(( ATTEMPT_SECONDS * ${#BUILDS} + 60 )) "$script" ssh -o ConnectTimeout=15 "$host" 'sh -s'
}

push "$PRIMARY" $BUILDS || { echo "upload of the builds to $PRIMARY failed"; exit 1 }
echo "builds uploaded to $PRIMARY"
for mirror in $MIRRORS; do
    if pull "$mirror"; then
        echo "builds fetched by $mirror from $PRIMARY_URL"
    else
        echo "$mirror could not fetch the builds, pushing them from this Mac"
        push "$mirror" $BUILDS || { echo "upload of the builds to $mirror failed"; exit 1 }
        echo "builds uploaded to $mirror"
    fi
done
for target in "$PRIMARY" $MIRRORS; do
    push "$target" "$MANIFEST" || { echo "upload of ${MANIFEST:t} to $target failed"; exit 1 }
    echo "${MANIFEST:t} uploaded to $target"
done
