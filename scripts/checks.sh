#!/bin/sh
# The pre-push hook and release packaging use the complete source-bound gate.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
if [ "$#" -eq 0 ] && "$root/scripts/check-release" --verify; then exit 0; fi
exec "$root/scripts/check-release" "$@"
