# Contributing to Hop

Pull requests are welcome. This page lists what a change needs before it is
merged. The same rules apply to every commit in the repository.

## Before you open a pull request

- Branch from `dev` and open the pull request against `dev`. `main` holds
  released versions only.
- Run `./scripts/checks.sh`. It builds with warnings treated as errors, runs
  the tests and the self-tests, and checks the translations. CI runs the same
  script.
- Try the change in the dev build: `./scripts/build-app.sh --install --dev`
  installs `Hop Dev.app` next to the released app.
- Keep one topic per pull request. An unrelated fix goes into its own.

## Spec, tests and docs travel with the code

- `docs/spec.md` describes how the app behaves. Read the section of the module
  you are changing first. A change in behaviour updates the spec in the same
  commit.
- A bug fix comes with a test that fails without it. Logic that can be tested
  without a window goes into a small type of its own, the way
  `PanelHeightLimit` and `PanelSpaceHeightCache` do.
- Timer logic lives in `HopCore` and is covered by tests.

## Comments

The code is the description of what happens. A comment stays only when it
carries something the code cannot:

- `// WORKAROUND:` names a defect in the system or a library and says why the
  direct way fails.
- `// SPEC:` points to a section of `docs/spec.md` or to an external contract.
- A pointer to the test that holds an invariant.
- One line of contract on a public API.

Everything else is removed before review:

- a comment that restates the line below it;
- the story of the bug, the reasoning behind the design, or what the code
  looked like before. The reasoning belongs in the spec, the story belongs in
  the commit message;
- section dividers, commented-out code, and a `TODO` without an issue link;
- a doc comment of several lines on a private property or function.

A number that needs explaining becomes a named constant.

## Code

- Colours come from `Theme.*` tokens. Check UI changes in the dark and the
  light theme.
- A new UI string is added to every language in the `L10n` table in the same
  commit. `--l10n-check` has to pass.
- The repository is English only: code, comments, docs, commit messages and
  file names. The exceptions are the translation tables and the localized
  READMEs in `docs/readme/`.
- No new dependencies, install scripts, network calls or binaries without a
  discussion in an issue first.

## Commit messages

- The subject says what changed for the person using the app, starting with
  the area: `Panel: its height is capped by its own screen`.
- The body is plain English prose that explains why.
- A message ends with its last sentence. Trailers, tool signatures and
  generated footers are left out. CI rejects a commit with a `Co-authored-by`
  line.
- The author of a commit is the person who is responsible for it.
