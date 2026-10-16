# Local verification

Run `./scripts/check-release` before a pull request or release, then `./scripts/check-release --verify` immediately before publishing that exact clean commit. `scripts/checks.sh` verifies an existing fresh proof for the exact source, or runs the same complete gate when that proof is absent, stale or invalid. This avoids repeating an unchanged successful run during pre-push and release packaging; it never accepts a failed or partial report. The proof binds HEAD, tree, tracked files, plan, command exit codes, logs, artifacts and cleanup; it expires after six hours. A changed source, failed latest run, missing output, altered log or stale proof is rejected.

Prerequisites are macOS, Node 22 with bundled npm, Xcode at `/Applications/Xcode.app`, the installed macOS 26.5 SDK, and the pinned CodeQL Swift bundle 2.27.2 with the reviewed compatibility extractor on PATH. Apple Silicon also needs Rosetta 2 for the official Intel Swift extractor. The check does not install Rosetta or accept its license.

Prepare a previously downloaded official archive with:

```sh
python3 scripts/own-ci/codeql-setup.py --archive /absolute/path/codeql-bundle-swift-osx64.tar.zst --extractor /absolute/path/reviewed-extractor --destination /absolute/path/new-sdk-directory
```

Preparation requires Python's `zstandard` module for this archive and makes no network request. It verifies the official archive, all 7,761 original SDK tree records, the reviewed source-built extractor and all 7,761 derived tree records. Only the extractor executable changes. The exact source patches, input identities, build recipe and differential controls are documented in [CodeQL compatibility](codeql-compatibility.md). A different rebuild requires a new review and explicit pin; setup never trusts an arbitrary executable or silently falls back to the broken official extractor. Put the resulting `codeql` directory on PATH. Each analysis authenticates the complete SDK tree again before execution. Missing, extra or modified content fails; no SDK file is excluded from hashing.

The gate includes:

- The frozen shared core's 26 regression tests, 74 adapter regressions and 13 offline SDK-preparation tests.
- The normal debug build with compiler warnings rejected; complete XCTest discovery and execution, at least 1,720 passing cases, with no skipped, duplicate or missing cases.
- Existing canvas, markup export, live-layer, translation and preparing-version self-tests.
- English-only incoming commit messages with no generated/co-author trailers.
- A separate fresh full Swift build for CodeQL, the pinned default 29-query suite, SARIF validation and successful-extraction diagnostics for every Swift file under `Sources`. A nonempty but partial database cannot pass. The original report is retained, including the official CLI's empty baseline and telemetry records. Only the four reviewed informational metadata kinds can have empty text; error, fatal, extraction-failure, malformed or unknown blank notifications are rejected. Analysis/extraction failures and error-level findings fail the gate; warnings remain visible in the saved report.

Native commands use a mandatory macOS sandbox. Only system/toolchain/verified SDK and private-run content can be read, only the run can be written, and network access is limited to loopback. HOME, Foundation home, module caches and temporary files belong to the run. Preferences and Keychain services are denied. Only the existing export self-test can contact the pasteboard service: it creates a UUID-named board, verifies its own synthetic image and releases it; it does not access the general clipboard. Other native modes deny that service too. The OS permission is service-wide, so the dedicated self-test entry point and inspected source are part of this boundary.

A process-local universal temporary adapter keeps Foundation's atomic replacements and standard temporary-directory APIs inside the owned TMPDIR. The macOS sandbox still rejects paths outside it. Cached adapter files require canonical no-follow regular-file reads. SwiftPM's nested sandbox is disabled inside the mandatory outer sandbox, and its native backend avoids the external build service; the backend's deprecation notice stays visible.

The normal build and tests use Xcode's current SDK. The pinned CodeQL extractor uses the installed macOS 26.5 SDK because it cannot parse SDK27's `-target-arch-variant` interface flag. CodeQL gets disposable copies of SwiftPM, its driver and frontend with short absolute runtime-library aliases; the installed Xcode remains untouched. Only ancillary SDK discovery, linking and plugin services are excluded from tracing; all official Swift compiler matchers remain enabled. Every production source still needs explicit successful-extraction evidence.

Release packaging reads the preparing version from the fresh authenticated proof artifact. It does not depend on a debug binary left in the real checkout by the checks. Packaging still has its own explicit release-version comparison and signing/notarization requirements.

Proofs and renderings stay outside the repository in an owned temporary state directory. No app installation, signing, notarization, upload, normal menu-bar launch or production-data access is part of these checks. The former hosted workflow bytes are retained under `docs/local-verification/legacy-workflows` for reference; GitHub Actions is not the release gate.
