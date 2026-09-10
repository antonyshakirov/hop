#!/bin/bash
# The check cycle, in one place: build, tests, the two canvases, translations.
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

# One directory per run, thrown away on the way out. A fixed path under /tmp is
# one anybody on the machine can plant a symlink at before the output lands.
run=$(mktemp -d "${TMPDIR:-/tmp}/hop-checks.XXXXXX")
trap 'rm -rf "$run"' EXIT

echo "=== 1/6 build ==="
# Warnings are failures here: the app ships with none, and a new one is a
# regression that a green build would otherwise hide.
if ! swift build 2>&1 | tee "$run/build.log"; then
  echo "❌ build failed"
  exit 1
fi
if grep -E "^.*: (error|warning):" "$run/build.log"; then
  echo "❌ build produced errors or warnings"
  exit 1
fi

echo "=== 2/6 tests ==="
swift test

echo "=== 3/6 canvas ==="
# The editor's canvas is drawn by a path the export never touches: the loupe
# under the hand is not the loupe in the file.
if ! ./.build/debug/Hop --canvas-selftest "$run/canvas-selftest.png"; then
  echo "❌ the canvas self-test failed"
  exit 1
fi

echo "=== 4/6 live layer ==="
# The drawing layer draws its own blur and its own loupe from a streamed frame.
# What a blur hides has to stay hidden — under the glass as well.
live_renders="$run/live"
mkdir -p "$live_renders"
if ! ./.build/debug/Hop --live-selftest "$live_renders"; then
  echo "❌ the live layer self-test failed"
  exit 1
fi

echo "=== 5/6 translations ==="
./.build/debug/Hop --l10n-check

echo "=== 6/6 version ==="
# SPEC: docs/spec.md — "Versioning", the release a build is preparing.
if ! ./.build/debug/Hop --preparing-version; then
  echo "❌ the release notes and the release cards disagree on the version"
  exit 1
fi

echo "✅ all checks passed"
