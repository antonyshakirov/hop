#!/bin/sh
# The pre-push hook and release packaging accept a passing proof for this source;
# otherwise they run the check the changed files call for (see scripts/own-ci/scope.json).
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
if [ "$#" -eq 0 ] && "$root/scripts/check-release" --verify; then exit 0; fi
if [ "$#" -eq 0 ]; then exec "$root/scripts/check-release" --auto; fi
exec "$root/scripts/check-release" "$@"
