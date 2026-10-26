# Hop 2.4 offline acceptance — 26 October 2026

The user deferred listening, microphone and physical laptop tests. No publication
or replacement of installed Hop is part of this pass.

## Corrected behavior

`AppIcon.apply()` updates the running application's Dock image through
`NSApplication.applicationIconImage`. It no longer writes into its signed bundle.
The saved light/dark preference remains; Finder uses the packaged icon. The setting
now names the Dock in all22languages. The menu-bar icon is independent.

## Checks executed

- Icon runtime regression: failed before correction (1test,3assertions), passed
  afterward for both styles. TextKit checked actual label lines in22languages
  at148/196/244pt. The full typography check also passed after binding short
  words in RU/PL/SR.
- Fresh audio controller/session restored saved gain, mute, outputUID, pinned
  offline apps and manual ordering. No audio hardware was touched.
- A real `SoundOutputHandoff` driven by an injected routing session gated playback
  on explicit-device loss, kept its source guard across a default-output change,
  and resumed only for the same UID. This is an integration test with fake devices,
  not a physical AirPods disconnection test.
- The SwiftUI one-tab/four-module→VPN→four-module natural-height regression ran
  without skipping. Anchoring, stale height-cache rejection, screen bounds,
  Sound content height, tab states and standard window Zoom tests passed.
- Active/paused timers, timed awake, torrents and other work defer installation.
  The existing busy-policy and handoff lifecycle tests passed.
- A standalone harness compiled with the actual `AwakeUpdateHandoff.swift` tested
  real IOKit assertions across separate old/guard/new processes: old+guard overlap,
  old exit with guard retained, new+guard overlap, guard release with new retained,
  then full cleanup. It did not install an update, close the lid or induce sleep.
- Final available native checks:1950tests,0failures; build, canvas/export/live
  self-checks, all22translations and preparing version2.4.0 passed.
- Verification-infrastructure self-tests:100Node tests and13SDK-setup tests passed.
  The initial nested sandbox failed7environment cases; rerunning under system
  execution passed without weakening the tests.

## Remaining acceptance

- Real listening: Mac keys and Hop top control across default/explicit devices,
  app gain/mute, background behavior and Output on/off handoff quality.
- Voice+application audio through Hop Mix in a target app, cleanup on close,
  AirPods stem mute/status, physical disconnect/reconnect.
- A real app update and physical lid/external-display/battery/timer scenarios.
- Full source-bound release gate needs pinned CodeQL2.27.2, currently unavailable.
  No SDK/tool download was performed. Local native checks do not replace this gate.
- A local signed candidate must pass deep/strict verification after launch without
  runtime metadata cleanup; its artifact receipt records that separate result.
