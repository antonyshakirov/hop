#!/bin/bash
# The check cycle, in one place: build, tests, translations.
#
# Called by three things, so they cannot drift apart — the CI workflow, the
# local pre-push hook, and release.sh before it packages anything. A release
# has never gone out red, and this is what keeps it that way (2026-08-29).
#
# Usage: scripts/checks.sh
# Exit status is non-zero on the first failure; nothing is printed on success
# beyond each step's own line, so it reads at a glance.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "=== 1/3 build ==="
# Warnings are failures here: the app ships with none, and a new one is a
# regression that a green build would otherwise hide.
if swift build 2>&1 | tee /tmp/hop-build.log | grep -E "^.*: (error|warning):" ; then
  echo "❌ build produced errors or warnings (see /tmp/hop-build.log)"
  exit 1
fi

echo "=== 2/3 tests ==="
swift test

echo "=== 3/3 translations ==="
./.build/debug/Hop --l10n-check

echo "✅ all checks passed"
