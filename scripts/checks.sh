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

echo "=== 1/4 build ==="
# Warnings are failures here: the app ships with none, and a new one is a
# regression that a green build would otherwise hide.
if swift build 2>&1 | tee /tmp/hop-build.log | grep -E "^.*: (error|warning):" ; then
  echo "❌ build produced errors or warnings (see /tmp/hop-build.log)"
  exit 1
fi

echo "=== 2/4 tests ==="
swift test

echo "=== 3/4 canvas ==="
# The editor's canvas is drawn by a path the export never touches: the loupe
# under the hand is not the loupe in the file.
if ! ./.build/debug/Hop --canvas-selftest /tmp/hop-canvas-selftest.png; then
  echo "❌ the canvas self-test failed"
  exit 1
fi

echo "=== 4/4 translations ==="
./.build/debug/Hop --l10n-check

echo "✅ all checks passed"
