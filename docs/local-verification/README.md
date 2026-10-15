# Local verification

Status: migration in progress. Both hosted workflows remain active until all equivalent local checks pass. The current local adapter fails closed; it has no successful full-candidate proof yet.

The proposed entry point is `./scripts/check-release`; `./scripts/check-release --verify` accepts only a fresh successful report for the same clean HEAD, tree, source and plan. The shared core is pinned byte-for-byte to the reviewed 26-test version. Node 22 with its bundled npm, Xcode/Swift and the official CodeQL 2.27.2 bundle must be available outside the repository.

The plan preserves these checks:

| Existing check | Local command or entry point |
| --- | --- |
| Debug build, compiler warnings rejected | `swift build --disable-sandbox --build-system native` with the existing warning pattern |
| Complete XCTest suite | `swift test --disable-sandbox --build-system native`, preceded by discovery; every discovered case must complete once, pass and match the report |
| Editor canvas | `Hop --canvas-selftest` with a synthetic frame |
| Markup export | `Hop --markup-selftest` with synthetic content |
| Live drawing layer | `Hop --live-selftest` with synthetic streamed frames |
| Translation checks | `Hop --l10n-check` |
| Preparing-version consistency | `Hop --preparing-version` |
| Incoming commit messages | Every commit from the pinned dev base through HEAD; English-only and no generated/co-author trailers |
| Swift CodeQL | Fresh traced Swift build and the bundled default Swift code-scanning suite, producing SARIF |

The base for incoming messages is `5b5b006c08c4d996cf26e898d46d1eb3afe63c69`. With no incoming commits, the base tip is checked. A future base update needs review of this pin.

Native commands run under mandatory macOS `sandbox-exec`. File contents are limited to the toolchain/system and private run; writes are limited to the run. HOME, Foundation's fixed user home, temporary files and module caches are synthetic. Preferences and Keychain services are denied; network access is loopback only. Only the existing markup-export self-test can contact the pasteboard service: its inspected entry point uses a UUID-named board for its synthetic image and releases it. It does not use the general clipboard. The OS exception is service-wide; the dedicated entry point is part of the boundary. Other modes deny that service. A Node preload is supplemental and is not the Swift firewall. Internal steps reject an ordinary HOME or a workspace outside the exact private run layout.

Canonical path resolution can open the exact parent directories `/private`, `/private/tmp` and the owned run's parent. These literal directory permissions expose their entry names, not child-file contents. Sibling reads, symlink escapes and writes to the parent remain denied.

A process-local universal Foundation adapter confines atomic replacement directories and standard temporary-directory APIs to the private run. Without it, SwiftPM's atomic output-map write requests a replacement directory in the real user's `TemporaryItems`; the outer sandbox correctly rejects that request. The installed compiler, Foundation and application source remain unchanged. Cached adapter files must be canonical, owned regular files opened without following links.

SwiftPM's nested manifest sandbox is disabled because macOS rejects applying it inside the mandatory outer sandbox. The supported native backend avoids the external SwiftBuild service. Debug settings and product/test sources remain unchanged. The toolchain's native-backend deprecation notice is retained; compiler warnings are checked with the same pattern as `checks.sh`.

Current execution limits:

- The frozen shared core's 26 regressions pass. The adapter plan requires at least 61 regressions plus six offline SDK-preparation tests; this is not a substitute for executing the application checks.
- A source-bound run of checkpoint `1ad2c89` passed the original seven checks: debug build, all 1,720 discovered XCTest cases (no skips), canvas, markup export, live layer, translations and preparing-version consistency. Its other five prerequisite steps passed too. The full gate and subsequent publication verification still failed because of CodeQL; this is not a successful full-candidate proof.
- Rosetta 2 was installed using Apple's official installer after explicit human approval and license acceptance. The Intel Swift extractor now executes. The official CodeQL 2.27.2 bundle and all 7,761 SDK-tree records are authenticated before execution.
- CodeQL remains blocked by extractor errors on the full application, including ambiguous `NSAccessibilityElement` and unexpected macro expressions. Normal compilation succeeds. SDK 27 also exposes an unsupported interface flag; the installed SDK 26.5 avoids that separate incompatibility. The adapter rejects nonzero extractors, error/fatal log records, incomplete source coverage, failed analysis and error-level findings. No equivalent CodeQL PASS or full-candidate proof is claimed.
- No app installation, launch of the normal menu-bar application, signing, notarization, release, GitHub upload or merge was performed. Preferences checks cover in-process synthetic values; persistent preferences semantics are not proven with their daemon denied.

`checks.sh` and both workflow files remain unchanged. Their later archival requires successful equivalent execution and review; a partial run must not be treated as a release gate.
