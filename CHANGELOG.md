# Hop — version history

## 1.3.1 — 2026-07-18

- Torrents: enabling the module now downloads the engine right away — the
  what's-new card walks through it in two steps: an explicit enable with
  the honest ~26 MB cost, then live download progress with the follow-up
  choices (show the module when empty, make Hop the default for .torrent
  and magnet). Enabling from onboarding or settings prefetches the engine
  the same way. The download icon in a torrent row lights up only while
  bytes are actually flowing.
- Monitor: memory now matches Activity Monitor's Memory Used exactly
  (the old formula under-reported by gigabytes after days of uptime);
  disk shows decimal gigabytes like Finder; network speeds use decimal
  units like everywhere else in the app.
- Updates: leftover staging folders from past updates are swept at launch.
- What's new: releases are visually separated, and every screenshot uses
  unambiguously open content.

## 1.3.0 — 2026-07-18

- Torrents: a lite BitTorrent client built into the panel. Drop a .torrent
  file or paste a magnet link; pick individual files before and during the
  download; pause, resume and seed with an optional stop-at-ratio-1.0
  policy. The download engine is not bundled — it downloads on demand
  (~26 MB, signature-verified) the first time you enable the module, and
  talks only to the app over a local loopback port. Hop can optionally
  become the default app for .torrent files and magnet links. If a
  download's files are deleted from disk mid-download, Hop pauses the
  torrent and offers to re-download.
- Awake: keep-awake now keeps the display on by default (previously only
  the system stayed awake and the screen could still sleep); the lid
  button's one-time admin prompt actually appears now (it silently failed
  for everyone since 1.0.0), and lid mode verifies the real power state,
  re-requesting rights when the setup goes stale.
- Windows: the tiling hotkeys register at launch — they used to stay dead
  until the keep-awake hotkey was pressed once.
- Monitor: battery discharge wattage is computed correctly (some Macs
  showed absurd readings); power and battery-health icons no longer clash
  in the light theme.
- Updates: a found release now installs at the first idle moment, and the
  check runs hourly instead of every six hours.
- Internal: developer-only launch flags are compiled out of release
  builds; engine downloads require https and validate every member path
  inside a torrent.

## 1.2.0 — 2026-07-15

- Updates: the app relaunches itself after installing a release, and a
  found update also installs right after the Mac wakes from sleep. This
  fixes the broken Finder icon two live instances used to cause.
- Monitor: the memory row shows RAM and swap separately, and its color
  follows macOS's own memory-pressure signal — the manual "memory+swap %"
  threshold is gone.
- Panel: keyboard transparency — typing goes to the app underneath the
  open panel, except timer digit entry and the clipboard search field.

## 1.1.0 — 2026-07-15

- Clipboard history keeps images, with a setting for visible rows.
- Video conversion: format, resolution and compression are independent
  choices; whole-batch progress with percentage; sizes in decimal units
  matching Finder; battery health reads the calibrated figure.
- Monitor: redrawn charts with equal widths, a clearer download/upload
  pair, swap with its GB unit, chart window setting up to an hour.
- Awake: lid mode blanks the built-in panel while the lid is closed.
- Settings: module reordering is a hand-rolled drag with a live gap;
  dark and light app icon variants; opaque title bar.
- Help: a "what's new" tab, plain-language pass over all 18 languages,
  product-page and GitHub links in the footer.
- Fixes: window raising above the frontmost app, hotkey legend covering
  every zone, light-theme contrast, theme switch repainting open windows.

## 1.0.0 — 2026-07-13

First release. Timer with a dot-matrix display, cycle templates and a
stopwatch; no-sleep (including a closed-lid mode); system monitor with swap
and thresholds; clipboard history; file converter (images, PDF, video,
audio); window manager with zones and hotkeys; speed test; 18 languages;
safe mode on crash loop; auto-update with an Ed25519 signature.
