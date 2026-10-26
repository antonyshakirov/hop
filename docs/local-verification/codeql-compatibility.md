# CodeQL Swift compatibility build

The release gate uses CodeQL 2.27.2, its unchanged Swift query packs and a reviewed source-built Swift extractor. The official extractor emits 29 `Unexpected MacroExpansionExpr` errors and two Objective-C name-ambiguity errors while analyzing Hop. These are extraction failures, not 31 security findings in the application. Suppressing their logs, accepting a partial database or changing actor isolation in Hop is not an acceptable repair.

`scripts/own-ci/codeql-sdk.json` authenticates the official bundle, the complete original SDK tree, the compatibility executable and the complete derived SDK tree. Only `swift/tools/osx64/extractor.real` changes. The launcher, runtime libraries, schema, queries and all other SDK files retain their official bytes. The compatibility executable is a local build prerequisite; it is not downloaded from an unreviewed binary URL or committed to this repository.

## Two bounded source changes

The patches and authenticated build inputs are in `scripts/own-ci/codeql-compatibility`.

- `typed-macro-expansion.patch` resolves a Swift expression macro to its typed rewritten expression before allocating a CodeQL label. The ordinary expression translator then records the expanded tree. Missing, untyped or cyclic rewrites fail explicitly. This preserves the actor identity inside `#isolation`, including caller-side default arguments.
- `ordinary-value-lookup.patch` changes one Clang lookup from `LookupAnyName` to `LookupOrdinaryName`. The surrounding importer branch accepts only `ValueDecl` aliases. A valid Objective-C class and protocol may share a name; including the protocol namespace in this value lookup produced the spurious diagnostic before the optional alias feature was checked. Independent class/protocol import and enum, variable and function aliases remain available.

No application compiler flag, application source, XCTest source or SDK framework header is changed. The experimental alias feature is enabled only in the synthetic alias regression, never in the Hop build.

## Rebuild and review

`build-inputs.json` records exact commits, public asset URLs, SHA256 values, compiler identity and the reviewed output. `swift-importer-source.json` records all 18 private importer source/header files by Git blob identity and SHA256. `link-arguments.json` records the final linker arguments, with only the output and compiler-archive paths represented by placeholders. Paths in that file are relative to the Bazel execution root unless absolute system paths are specified.

Use a fresh owned build directory, private HOME/cache/TMPDIR and a mandatory native filesystem sandbox. Dependency acquisition is a separate public-network preparation phase. The actual C++ build and fixture executions deny external network access and personal-file, preferences, Keychain and general-pasteboard access. Do not run these native stages against real user data or relax that boundary to make a compiler succeed.

1. Materialize `github/codeql` at `a7057b836bf29767461026718b14d20790b9085f`, including `swift`, `shared` and `misc`. Authenticate the source tree, Bazel 9.0.0 and the release's Git-LFS-pinned `swift-prebuilt-macos.tar.zst`. Extract the prebuilt's public/generated headers, Swift shims and original compiler archive. Preserve all original inputs.
2. Prepare only `//swift/extractor:extractor.real` and its declared Bazel dependencies. The official target uses C++20/x86_64 and Python 3.12 code generation. A disposable untracked `MODULE.bazel.lock` can freeze this preparation; do not add it to the upstream source or publish it. The compiler stage uses `--lockfile_mode=error` and cannot fetch missing inputs.
3. Build the unmodified extractor first and retain its binary, source identity, log and original linker response. The reviewed reproduction used the authenticated Command Line Tools clang with the installed Xcode SDK as its explicit host sysroot, owned action TMPDIR and two workers. The generic compiler configuration must also declare the SDK as a system include so Bazel's header validation remains enabled. Do not disable header validation or substitute an unverified compiler.
4. Materialize the pinned Swift release's `lib/ClangImporter` source. Compile the unmodified `ImportMacro.cpp` and then the one-word patched version, each with the same prebuilt public headers and private importer headers. The verified compile options were `-std=c++20 -fno-rtti -DNDEBUG -O2 -arch x86_64`, the installed macOS 26.5 sysroot, and include paths for the prebuilt `include`, `stdlib/public/SwiftShims` and private importer source directory.
5. Clone the original `libCodeQLSwiftFrontendTool.a` separately for each control. Replace its unique `ImportMacro.cpp.o` member using BSD `ar -r -s` with `ZERO_AR_DATE=1`. Verify object ordering and all payload hashes: exactly that member changes; the other 4,637 object payloads and the original archive remain byte-identical. Strong-export comparison is a preliminary check, not an ABI proof.
6. Apply only the typed-macro patch to CodeQL source and rebuild the same target. Verify the sole tracked source difference and its exact hash before and after compilation. Relink its resulting C++ objects/libraries against each compiler archive using the frozen original linker inputs. The final argument template is recorded alongside the patches.
7. Match the distributed executable's macOS 11 deployment target. With the verified clang 21 host, use explicit `-lobjc` instead of `-fobjc-link-runtime`: the latter injected Foundation and mixed incompatible bundled/system Swift runtimes. Runtime paths must resolve to the matching packaged dylibs; the final template uses `@loader_path`. Retain the official launcher and its runtime-library lookup. Ad-hoc sign only disposable executable copies; do not alter Xcode or system libraries.
8. Run the differential controls below, then the complete Hop gate. A rebuilt executable is not accepted merely because it links, exits zero or has the expected exported symbol. Any changed compiler/source/input/output identity requires a new review and explicit manifest pin; do not automatically trust a newly calculated digest.

Build paths and toolchain versions can affect output bytes. The manifest pins the reviewed build, not every possible rebuild of these sources. A different host build must be authenticated and pass the same controls before its pin is deliberately updated.

## Required differential controls

The synthetic sources and real QL query are in `codeql-compatibility/fixtures`.

- The original extractor must reproduce the macro failure for both implicit and explicit isolation. An explicit `nil` control is clean but is not an application workaround: it changes actor semantics.
- A minimal Objective-C class/protocol collision with an identifier alias must compile natively. The rebuilt unmodified importer reproduces one extraction diagnostic; the patched importer produces none. Removing either the alias or the protocol is also clean in both controls. This checks that rebuilding the importer object itself did not conceal the defect.
- Create a real CodeQL database for `Aliases.swift` and `Isolation.swift`, using the packaged resources and matching macro plugin server. Check every nested extractor log before finalization. Run `Semantics.ql` and compare the exact 14 result rows, not just the row count: six isolation rows (`nil`, `self`, `shared`, each for implicit and explicit calls), three caller-default roots, the class and protocol, and three enum/global/function alias references. The macro-only control omits the collision alias; the combined fix retains it. Both must preserve the same 14 rows.

CodeQL's existing `DefaultArgumentExpr` model has no immediate AST-child edge to its caller-side expression. The regression therefore obtains implicit isolation through `getCallerSideDefault()` and binds ownership through the default argument itself. The production schema and query library are unchanged. Alias rows prove retained reference identities; they are not a general proof of every possible C/Objective-C alias behavior.

The release gate still requires a fresh complete Swift build, zero extraction errors, all production Swift sources successfully extracted, the original default 29-query suite and validated SARIF. Neither these synthetic controls nor a manually finalized database replace that gate.

## Reviewed reproduction on 2026-10-26

The manifest deliberately admits extractor SHA256 `1deb941ab2e04c9989e7599fdbdce4cad870d1d7eef774eee1c28c4dfbbc1781` (174,520,544 bytes) and derived SDK tree `9c8e21655746d647fed83e8bb28bac6ab59345e2a68d2236b5f07903c3e6a7cf`. It differs from the prior reviewed output (`ef2d1d6c…`, 174,520,624 bytes); the cause of that byte difference is not established, and byte identity with that output is not claimed.

Authenticated source, assets, both importer objects and the patched compiler archive match the recorded inputs. The final linker arguments match the frozen template. Comparison of all 7,761 SDK entries confirms that only the extractor executable changes from the authenticated upstream SDK. The reproduction used the recorded CLT clang, the Xcode host SDK for C++, and the installed CLT macOS 26.5 SDK for importer compilation and fixture extraction.

The original extractor reproduced six macro diagnostics; explicit nil was clean. The rebuilt unchanged importer reproduced the class/protocol ambiguity. Both importer variants passed controls with the collision alias removed and with the protocol removed, including nested-log inspection. Macro-only and combined real-database queries each returned the same exact 14 expected rows, including references to `FixtureNumberAlias`, `FixtureGlobalAlias` and `FixtureFunctionAlias`. Native Swift typechecking with the fixture-only alias feature also passed. An independent review verified these controls and approved the deliberate pin update. The complete production gate remains required for every application revision; these controls do not substitute for its result.
