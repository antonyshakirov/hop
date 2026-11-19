# Local verification

Run `./scripts/check-release` before a pull request or release, then `./scripts/check-release --verify` immediately before publishing that exact clean commit. `scripts/checks.sh` verifies an existing fresh proof for the exact source, or runs the same complete gate when that proof is absent, stale or invalid. This avoids repeating an unchanged successful run during pre-push and release packaging; it never accepts a failed or partial report. The proof binds HEAD, tree, tracked files, plan, command exit codes, logs, artifacts and cleanup; it expires after six hours. A changed source, failed latest run, missing output, altered log or stale proof is rejected.

Prerequisites are macOS, Node 22 with bundled npm, Xcode at `/Applications/Xcode.app`, the installed macOS 26.5 SDK, and the pinned CodeQL Swift bundle 2.27.2 with the reviewed compatibility extractor on PATH. Apple Silicon also needs Rosetta 2 for the official Intel Swift extractor. The check does not install Rosetta or accept its license.

Prepare a previously downloaded official archive with:

```sh
python3 scripts/own-ci/codeql-setup.py --archive /absolute/path/codeql-bundle-swift-osx64.tar.zst --extractor /absolute/path/reviewed-extractor --destination /absolute/path/new-sdk-directory
```

Preparation requires Python's `zstandard` module for this archive and makes no network request. It verifies the official archive, all 7,761 original SDK tree records, the reviewed source-built extractor and all 7,761 derived tree records. Only the extractor executable changes. The exact source patches, input identities, build recipe and differential controls are documented in [CodeQL compatibility](codeql-compatibility.md). A different rebuild requires a new review and explicit pin; setup never trusts an arbitrary executable or silently falls back to the broken official extractor. Put the resulting `codeql` directory on PATH. Each analysis authenticates the complete SDK tree again before execution. Missing, extra or modified content fails; no SDK file is excluded from hashing.

### Local build cleanup

Every Hop verification run must permanently delete its disposable working copy, Swift builds, modules, temporary SDK and CodeQL database as soon as its processes have stopped. This applies after success, failure, and handled cancellation. A successful proof requires completed cleanup. Preserve the proof, logs, final check artifacts and diagnostic reports. Remove temporary data directly from the filesystem. Keep the installed app and explicitly requested packages or screenshots.

Use `scripts/check-release`, `scripts/build-app.sh` and `scripts/make-screens.sh` for local verification, packaging and screenshots. The latter two use a private Swift scratch directory and remove it on exit. Use `--install --dev` only when deliberately installing a development copy. Without an explicit output directory this leaves only the installed bundle. The standalone packaging command keeps its requested bundle in `dist/`. If a process is killed with SIGKILL or the machine loses power, inspect the interrupted run, stop any surviving processes and remove its owned temporary payload before starting another run. Keep the evidence.

### Local build budget

The build, test and CodeQL steps, app packaging and screenshot builds
share `/private/tmp/hop-build-budget-<uid>.lock`. The lock is acquired outside
the native sandbox and works across checkouts and isolated HOME/TMPDIR values.
Only one protected build or check step runs at a time, with two Swift compiler jobs and
lower scheduling priority. CodeQL finalization and analysis retain their existing
two-thread limit. Waiting commands remain subject to the check step's timeout.
Cancellation stops the protected process group before releasing the lock.
The leader is reaped only after group cleanup, preventing PID reuse during
signalling. The command inherits the lock too: abrupt launcher death cannot
start a concurrent build while that command is still alive.
Workers that deliberately create their own session are outside group cleanup.

For manual builds and preflight recipes, use
`python3 -B scripts/build-budget.py swift build` or replace `build` with `test`.
This launcher caps explicit job requests too. Raw toolchain invocations and old
standalone recipes do not automatically enter the queue; migrate them to this
launcher or the updated `hop-step.mjs` before starting another build.

Run the resource regressions without building Hop:
`python3 -B -I scripts/build-budget.test.py`.

### Release checks

The gate includes:

- Build-budget regressions covering serialization across checkouts, failures,
  cancellation, process-group cleanup and the two-job Swift limit.
- The frozen shared core's 26 regression tests, 74 adapter regressions and 13 offline SDK-preparation tests.
- The normal debug build with compiler warnings rejected; complete XCTest discovery and execution, at least 1,720 passing cases, with no skipped, duplicate or missing cases.
- Existing canvas, markup export, live-layer, translation and preparing-version self-tests.
- English-only incoming commit messages with no generated/co-author trailers.
- A separate fresh full Swift build for CodeQL, the pinned default 29-query suite, SARIF validation and successful-extraction diagnostics for every Swift file under `Sources`. A nonempty but partial database cannot pass. The original report is retained, including the official CLI's empty baseline and telemetry records. Only the four reviewed informational metadata kinds can have empty text; error, fatal, extraction-failure, malformed or unknown blank notifications are rejected. Analysis/extraction failures and error-level findings fail the gate; warnings remain visible in the saved report.

XCTest discovery builds all test products first. Each UI suite then runs in a fresh
process to bound AppKit animation and dispatch state; other targets run once per
target. Execution stays sequential under the same build budget and sandbox.
The test step has a bounded 20-minute budget for compilation, sequential process
startup and execution. Individual test deadlines remain unchanged.
Every discovered case must pass exactly once in its assigned batch, and each batch
must report successful completion. Unknown discovery entries, missing or repeated
batches, foreign cases, failures and skips fail the gate. Filtered runs do not
replace or reduce the complete discovery requirement.

Native commands use a mandatory macOS sandbox. Only system/toolchain/verified SDK and private-run content can be read, only the run can be written, and network access is limited to loopback. HOME, Foundation home, module caches and temporary files belong to the run. Preferences and Keychain services are denied. Only the existing export self-test can contact the pasteboard service: it creates a UUID-named board, verifies its own synthetic image and releases it; it does not access the general clipboard. Other native modes deny that service too. The OS permission is service-wide, so the dedicated self-test entry point and inspected source are part of this boundary.

A process-local universal temporary adapter keeps Foundation's atomic replacements and standard temporary-directory APIs inside the owned TMPDIR. The macOS sandbox still rejects paths outside it. Cached adapter files require canonical no-follow regular-file reads. SwiftPM's nested sandbox is disabled inside the mandatory outer sandbox, and its native backend avoids the external build service; the backend's deprecation notice stays visible.

The normal build and tests use Xcode's current SDK. The pinned CodeQL extractor uses the installed macOS 26.5 SDK because it cannot parse SDK27's `-target-arch-variant` interface flag. CodeQL gets disposable copies of SwiftPM, its driver and frontend with short absolute runtime-library aliases; the installed Xcode remains untouched. Only ancillary SDK discovery, linking and plugin services are excluded from tracing; all official Swift compiler matchers remain enabled. Every production source still needs explicit successful-extraction evidence.

Release packaging reads the preparing version from the fresh authenticated proof artifact. It does not depend on a debug binary left in the real checkout by the checks. Packaging still has its own explicit release-version comparison and signing/notarization requirements.

Proofs and renderings stay outside the repository in an owned temporary state directory. No app installation, signing, notarization, upload, normal menu-bar launch or production-data access is part of these checks. The former hosted workflow bytes are retained under `docs/local-verification/legacy-workflows` for reference; GitHub Actions is not the release gate.
