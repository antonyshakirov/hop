<div align="center">

<img src="assets/icon/hop-icon-app.svg" width="96" alt="Hop app icon — four-line asterisk">

# Hop

**A tiny menu bar companion for macOS: timer, time tracker, to-dos,
keep-awake, system monitor, clipboard history, file converter, window
manager and a lite torrent client — arranged across up to four tabs on
the icon. One click, and everything you need is right there.**

[![Latest release](https://img.shields.io/github/v/release/antonyshakirov/hop)](https://github.com/antonyshakirov/hop/releases/latest)
[![Installs](https://img.shields.io/endpoint?url=https%3A%2F%2Fwww.antonshakirov.com%2Fapi%2Fhop%2Finstalls&color=ffd60a)](https://www.antonshakirov.com/api/hop/installs)
[![CI](https://github.com/antonyshakirov/hop/actions/workflows/ci.yml/badge.svg)](https://github.com/antonyshakirov/hop/actions/workflows/ci.yml)
[![CodeQL](https://github.com/antonyshakirov/hop/actions/workflows/codeql.yml/badge.svg)](https://github.com/antonyshakirov/hop/actions/workflows/codeql.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
![Platform](https://img.shields.io/badge/macOS-14%2B-black)
[![Stars](https://img.shields.io/github/stars/antonyshakirov/hop?style=social)](https://github.com/antonyshakirov/hop/stargazers)

[Bahasa Indonesia](docs/readme/README.id.md) · [Deutsch](docs/readme/README.de.md) · **English** · [Español](docs/readme/README.es.md) · [Français](docs/readme/README.fr.md) · [Italiano](docs/readme/README.it.md) · [Nederlands](docs/readme/README.nl.md) · [Polski](docs/readme/README.pl.md) · [Português](docs/readme/README.pt.md) · [Tiếng Việt](docs/readme/README.vi.md) · [Türkçe](docs/readme/README.tr.md) · [Русский](docs/readme/README.ru.md) · [Українська](docs/readme/README.uk.md) · [עברית](docs/readme/README.he.md) · [اردو](docs/readme/README.ur.md) · [العربية](docs/readme/README.ar.md) · [فارسی](docs/readme/README.fa.md) · [हिन्दी](docs/readme/README.hi.md) · [ไทย](docs/readme/README.th.md) · [한국어](docs/readme/README.ko.md) · [中文](docs/readme/README.zh.md) · [日本語](docs/readme/README.ja.md)

<img src="https://www.antonshakirov.com/products/hop/screens/en/overview.png" width="360" alt="Hop panel — menu bar timer with dot-matrix display, presets and work-rest cycles">

</div>

Hop lives in your Mac's menu bar and replaces a handful of small utilities:
a Pomodoro-style timer, a time tracker with a to-do list, a caffeinate-style
sleep blocker, a system monitor, a clipboard manager, a drag-and-drop file
converter, a window snapper and a lite torrent client — one lightweight
native app, with the modules you use arranged across up to four tabs on the
icon.

## Download

- **[Hop.dmg](https://github.com/antonyshakirov/hop/releases/latest/download/Hop.dmg)** — open and drag `Hop.app` into Applications (recommended)
- Homebrew: `brew install --cask antonyshakirov/tap/hop`
- `Hop-x.y.z.zip` — the same app as a plain archive (used by the built-in updater); see the [latest release](https://github.com/antonyshakirov/hop/releases/latest)
- Fast mirror: [hop-dl.b-cdn.net/products/hop/Hop.dmg](https://hop-dl.b-cdn.net/products/hop/Hop.dmg)

First launch on macOS 15 or newer: try to open Hop once, then go to
**System Settings → Privacy & Security → Open Anyway** and confirm **Open**.
Hop is not notarized because Apple Developer Program membership is
unavailable to the author. The source is public, and built-in updates are
verified with Ed25519. Requires macOS 14 or newer.

## Features

### Spaces

The icon holds up to four tabs, and you drag each module into whichever tab
you like — the timer on one, the monitor on another, the things you rarely
open tucked away. An "inactive" shelf keeps anything you've set aside without
deleting it.

### Timer & cycles

A dot-matrix countdown you set in one gesture: drag the digits, type the
time like on a microwave, or pick a preset. Work-rest cycles (25/5 Pomodoro,
52/17, 90/15 — or your own), a stopwatch, a stash that keeps a running timer
while you try another one, and a finish alert that can also pause your media.
When the countdown ends it plays a single sound and the digits pulse until
you reset it.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/timer.png" width="420" alt="Hop — Timer & cycles">
</div>

### Time tracker & to-dos

Track time against a flat list of tasks — each row shows today's time and a
running total, and you can correct today's figure by hand. Leave one running
too long and a banner reminds you after eight hours. A separate to-do list
sits alongside, with finished items sinking to the bottom.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/tracker.png" width="420" alt="Hop — Time tracker & to-dos">
</div>

### No sleep

Keep the Mac awake for 15 minutes, 8 hours or forever — one click, no
password. Optionally keep the display on, or keep working with the lid
closed (handy for downloads, long builds and external displays).

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/awake.png" width="420" alt="Hop — No sleep">
</div>

### System monitor

CPU and GPU load and temperature, memory and swap, network, disk, battery
health and power draw — live values with sparkline charts, color thresholds
you set yourself, °C/°F, and an uptime line. Readings come straight from macOS
and update only while the tab is open. The memory row also speaks up when a
lot of memory has gone to disk, and not only when macOS itself reports being
short.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/system.png" width="420" alt="Hop — System monitor">
</div>

### Clipboard history

The last 100 (up to 300) things you copied — text, images and files — one
click to copy back or paste straight into the previous app. Copied files are
kept by name (several at once show as "name +N"), and pasting puts the actual
file back. Passwords and other concealed input are never stored.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/clipboard.png" width="420" alt="Hop — Clipboard history">
</div>

### File converter

Drop a batch of images, PDFs, videos or audio onto the panel: JPEG, PNG,
HEIC, AVIF and WebP out; PDF compression; HEVC video shrinking with a live,
honest size estimate before you convert. Everything is processed locally.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/converter.png" width="480" alt="Hop — File converter">
</div>

### Window manager

Snap windows to halves, quarters, thirds and center with a click on a zone
glyph or a ⌃⌥ hotkey — no extra app needed.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/windows.png" width="420" alt="Hop — Window manager">
</div>

### Torrents

A lite BitTorrent client in the same panel: drop a .torrent file or paste a
magnet link, pick exactly which files to download — before or even during
the download — pause, resume and seed, with an optional stop at ratio 1.0.
The module is off by default; enabling it fetches the open-source engine as
a small separate download (~26 MB, signature-verified) that talks only to
Hop over a local port. Hop can also become the default app for .torrent
files and magnet links.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/torrents.png" width="420" alt="Hop torrents — lite BitTorrent client in the menu bar panel">
</div>

### File archives

The module's row opens a window, and that window is where you drop things —
⌘V works too, several files at once. What you add waits in a list until you
press the button: archives are unpacked, anything else is packed into one
archive. Results land on the Desktop by default, or next to the original, or in
any folder you choose. zip, rar, 7z, tar, tar.gz, tar.bz2, tar.xz and gz are
covered; rar and 7z fetch a small signature-verified helper (~6 MB) the first
time one turns up. Hop unpacks rar but never creates it — the format is
proprietary. "Hop as the default for archives" in settings offers only rar when
no Apple app owns it, and can take rar back from third-party apps; zip, 7z and
the native formats stay with Archive Utility. It works with the module hidden, and the card
shows the real state, so it can never claim a default Finder has given away. Double-clicking an archive in Finder unpacks it right beside the file, in a small progress window of its own, and a failed job leaves nothing hidden behind. Files Hop opens carry its own icon with the format written across it, so a folder of them reads at a glance.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/archives.png" width="480" alt="Hop — File archives">
</div>

### Documents

The converter learned documents: markdown to PDF laid out by Hop itself, Word
files (.docx, .doc, .rtf) to PDF or markdown, and a PDF's text pulled out as
markdown — a scanned page is read with Apple's Vision. Native and offline,
with no office suite bundled and nothing to download.

### Color picker

Pick any color on screen with the system loupe and it stays in a list, each row
carrying hex, rgb and hsl in its own column — click one of the three and that
notation is copied. The order never changes under the cursor, the list length
and its visible rows are settings, and no screen-recording permission is
needed: the loupe hands back one color and nothing else.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/colors.png" width="420" alt="Hop — Color picker">
</div>

### Text recognition

Frame an area of the screen, or drop a picture into the window and paste one
with ⌘V: the text and any QR codes inside come out in a window you can read,
edit and copy from, and land in the clipboard history at the same time. Line
breaks are kept, so a table or a code snippet stays readable. Recognition is
Apple's Vision, entirely on this Mac.

A reading that holds a web address gets an "open link" button, so the link
inside a QR code on a bill opens in your browser without reaching for a phone.
Web addresses only: a scanned code is untrusted input, so a phone number, a
Wi-Fi password or a contact card stays plain text.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/recognition.png" width="480" alt="Hop — Text recognition">
</div>

### Keyboard lock

Tap 1, 5 or 15 minutes — or ∞ — and the whole keyboard stops responding, so it
can be wiped without shutting the Mac down or closing the lid. A cover explains
what is happening and the menu-bar icon turns into a keyboard. Four ways out:
the cover's button, the panel's button, opening the panel, or holding esc + shift for
five seconds. A short press of the power key is swallowed too; holding it
still forces the Mac off, because that is handled in hardware.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/keyboard.png" width="480" alt="Hop — Keyboard lock">
</div>

### And the rest

Small status badges on the menu bar icon — time, keep-awake, alerts and
torrent activity, colored or monochrome — a built-in speed test (Apple's
networkQuality), dark and light themes with a film-grain texture, global
hotkeys, launch at login, and a safe mode that recovers the app from a crash
loop. Hop's own windows — the converter, archives, recognition, settings —
show up in the Dock while they are open, so a click on the icon brings one
back instead of opening the panel first; the icon leaves with the last window.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/system.png" width="280" alt="Hop system monitor — CPU, GPU, memory, network, disk, battery charts">
<img src="https://www.antonshakirov.com/products/hop/screens/en/converter.png" width="280" alt="Hop file converter — batch image, PDF, video and audio conversion">
<img src="https://www.antonshakirov.com/products/hop/screens/en/settings.png" width="280" alt="Hop settings — themes, modules, hotkeys, 22 languages">
</div>

## 22 languages

Bahasa Indonesia, Deutsch, English, Español, Français, Italiano, Nederlands, Polski, Português, Tiếng Việt, Türkçe, Русский, Українська, עברית, اردو, العربية, فارسی, हिन्दी, ไทย, 한국어, 中文, 日本語 — the app follows your system language out of
the box.

## Support the project

Hop is free and always will be. If it earns a place in your menu bar, a
voluntary contribution keeps new features coming and the existing ones
polished — it pays for the time this takes, nothing else.

**[→ Support Hop](https://web.tribute.tg/d/Nvk)**

## Privacy — and why the permissions are safe to give

**Hop collects nothing. Not now, not later.** No server of its own, no
analytics, no telemetry, no accounts, no crash reports. Every permission below
is asked by macOS only when the feature that needs it is actually used, and each
one exists so that feature can work — nothing is collected on the side. You do
not have to take this on trust: the app is open source, so the code that would
do the collecting simply is not there. Search this repository for a tracking SDK
or an analytics call and you will not find one.

Everything runs locally: no server, no analytics, no accounts. The app only
touches the network to check for updates, when you run the built-in speed
test, and — if you enable the torrent module — to fetch the engine once and
move the torrent traffic itself. That update check sends the version you are
running, and nothing that identifies you or your Mac. Updates and the
torrent engine are delivered as signed archives and verified with an Ed25519
signature before installing.

## Permissions

Hop asks for a permission only when the feature that needs it is actually used,
and the app's info window lists them all with their current state:

- **network — antonshakirov.com** — update checks and downloads, plus the two
  optional helpers (the torrent engine and the 7-Zip archiver)
- **network — torrents, speed test** — peer traffic while the torrent module is
  on; the speed test runs macOS's own networkQuality against Apple's servers
- **accessibility** — pasting into the app underneath, the window manager and
  the keyboard lock
- **screen recording** — the text recognition module only, and only when it
  frames an area; the color picker does not need it
- **notifications** — the timer's alert and a finished torrent
- **administrator password** — once, for the closed-lid mode (pmset is root-only)
- **launch at login** — off unless you turn it on

Nothing is requested at launch, and nothing is asked for a module you have not
turned on. There is no analytics, no telemetry, no account and no crash
reporting: antonshakirov.com is contacted only to ask whether a newer version
exists — and to download it, or one of the two optional helpers, if you say yes.
Everything else stays on this Mac: the clipboard history, tracked time, the
to-do list, recognized text and picked colors.

Every permission above exists so a feature can work, and for nothing else. You
do not have to take that on trust: Hop is open source, so the code that would
have to do the collecting simply is not there — read it in this repository. The
app's info window has an "app permissions" tab with the same list and each
permission's current state.

Website: [antonshakirov.com/products/hop](https://www.antonshakirov.com/products/hop)

## Free, and why

Hop is completely free — no trial, no pro tier, no in-app purchases. No ads,
no data collection, no accounts: there is nothing to monetize and nothing to
sell. It is a personal project — I built Hop for myself, use it every day, and
share it. If it is useful, pass it on. And if you'd like to chip in, there is
now a way to support Hop — purely a gift, with nothing locked behind it.

## Building from source

Swift Package Manager, macOS 14+, no external dependencies:

```bash
git clone https://github.com/antonyshakirov/hop.git
cd hop
swift build
./scripts/build-app.sh
```

Dev workflow, release pipeline and the behavioral spec live in
[docs/development.md](docs/development.md) and [docs/spec.md](docs/spec.md).

## Support the project

Three ways, all of them welcome:

- **[Support Hop with a contribution](https://web.tribute.tg/d/Nvk)** — it goes
  straight into new features and fixes. Voluntary, no perks, no paywalled
  anything: every module is the same for everyone.
- **[Star the repo](https://github.com/antonyshakirov/hop/stargazers)** — stars
  are how other people find it.
- **[Open an issue](https://github.com/antonyshakirov/hop/issues)** — a bug
  report or an idea is worth as much as either of the above.

## Author & license

Made by [Anton Shakirov](https://www.antonshakirov.com/en). Released under
the [MIT license](LICENSE): use and modify freely, keep the copyright
notice — passing the app off as your own work is a license violation.
