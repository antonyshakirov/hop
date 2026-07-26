# Hop

A macOS menu bar timer with a dot-matrix display in the spirit of
[interval](https://supercommon.systems) — dark, minimal, glowing dots.

The name comes from "hop" — the little word that accompanies a quick,
nimble move: one click and everything you need is here. Hop — done.

## Features

- Presets 5 / 10 / 30 / 60 minutes, ±5 min buttons (they work during a countdown too)
- A preset pressed during a countdown doesn't kill the timer: the active one
  goes into the stash, and the ↩ button next to the presets restores and resumes it
- Countdown right in the menu bar (can be disabled in the gear settings)
- Finish signal: sound + notification / sound only / silent
- Keep awake: prevents the Mac from sleeping — 15/30 min, 1/2/4/8 h or ∞, a moon in the menu bar
- System tab: cpu/gpu (load + temperature), memory, network ↓↑, disk,
  battery (cycles, health), adapter watts; polling only while the tab is open
- Counts toward a target date — doesn't drift, survives Mac sleep

## Build and run

```sh
./scripts/build-app.sh            # builds "dist/Hop.app"
./scripts/build-app.sh --install  # + updates "/Applications/Hop.app" and relaunches
```

Requires macOS 14+ and Xcode (or Command Line Tools with Swift 5.9+).

The installed app lives in `/Applications/Hop.app`: launch via
Spotlight (⌘Space → "Hop"), quit via gear → quit. No server is needed —
the app is fully self-contained.

Launch at login: the "launch at login" toggle in the app settings.

## Development

```sh
swift test        # core tests (HopCore)
swift build       # dev build
./.build/debug/Hop --snapshot out.png   # render the panel to PNG
```

Spec: [docs/spec.md](docs/spec.md)

## Release process

Development happens in the `dev` branch — all iterations, experiments and
intermediate states live there. Only what has been explicitly approved
for release lands in `main`:

1. `git checkout main && git merge dev`
2. a line in `CHANGELOG.md`
3. `./scripts/release.sh X.Y.Z [--critical]` — builds, zips, signs with
   Ed25519 and places `latest.json` + the archive into the website repo (`public/downloads/hop/`)
4. commit in the website repo + `./deploy.sh` — the update ships to users
5. `git tag vX.Y.Z` in this repo
6. after `Hop.dmg` is attached to the immutable GitHub release, update
   `version` and `sha256` in
   [`Casks/hop.rb`](https://github.com/antonyshakirov/homebrew-tap/blob/main/Casks/hop.rb),
   then commit and push the tap

Production-cask validation runs only in the disposable macOS runner defined
by the tap's `.github/workflows/test.yml`. The workflow audits the cask,
installs it under the runner's temporary directory, launches it briefly,
terminates that exact process, and uninstalls it without `--zap`.

Never install or launch the production cask on the development Mac: a
temporary copy has the same bundle identity as `/Applications/Hop.app` and
can start a second production instance. Local app verification uses only
`./scripts/build-app.sh --install --dev` and `/Applications/Hop Dev.app`.
`zap` is also forbidden during verification because it intentionally removes
Hop's saved preferences and Application Support data.

Auto-update watches `antonshakirov.com/downloads/hop/latest.json`
(silently, every 6 hours; installs only when the timer and awake are inactive;
can be disabled in settings, or trigger an update manually with the button).
Installation is possible only with a valid Ed25519 signature of the archive.
