<div align="center">

<img src="assets/icon/hop-icon-app.svg" width="96" alt="Hop app icon — four-line asterisk">

# Hop

**A tiny menu bar companion for macOS: timer, keep-awake, system monitor,
clipboard history, file converter and window manager. One click — and
everything you need is right there.**

[![Latest release](https://img.shields.io/github/v/release/antonyshakirov/hop)](https://github.com/antonyshakirov/hop/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/antonyshakirov/hop/total)](https://github.com/antonyshakirov/hop/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
![Platform](https://img.shields.io/badge/macOS-14%2B-black)
[![Stars](https://img.shields.io/github/stars/antonyshakirov/hop?style=social)](https://github.com/antonyshakirov/hop/stargazers)

[Bahasa Indonesia](docs/readme/README.id.md) · [Deutsch](docs/readme/README.de.md) · **English** · [Español](docs/readme/README.es.md) · [Français](docs/readme/README.fr.md) · [Italiano](docs/readme/README.it.md) · [Nederlands](docs/readme/README.nl.md) · [Polski](docs/readme/README.pl.md) · [Português](docs/readme/README.pt.md) · [Tiếng Việt](docs/readme/README.vi.md) · [Türkçe](docs/readme/README.tr.md) · [Русский](docs/readme/README.ru.md) · [Українська](docs/readme/README.uk.md) · [हिन्दी](docs/readme/README.hi.md) · [ไทย](docs/readme/README.th.md) · [한국어](docs/readme/README.ko.md) · [中文](docs/readme/README.zh.md) · [日本語](docs/readme/README.ja.md)

<img src="https://www.antonshakirov.com/products/hop/screens/en/panel.png" width="420" alt="Hop panel — menu bar timer with dot-matrix display, presets and work-rest cycles">

</div>

Hop lives in your Mac's menu bar and replaces half a dozen small utilities:
a Pomodoro-style timer, a caffeinate-style sleep blocker, a system monitor,
a clipboard manager, a drag-and-drop file converter and a window snapper —
one lightweight native app instead of six.

## Download

- **[Hop.dmg](https://github.com/antonyshakirov/hop/releases/latest/download/Hop.dmg)** — open and drag `Hop.app` into Applications (recommended)
- `Hop-x.y.z.zip` — the same app as a plain archive (used by the built-in updater); see the [latest release](https://github.com/antonyshakirov/hop/releases/latest)
- Fast mirror: [hop-dl.b-cdn.net/products/hop/Hop.dmg](https://hop-dl.b-cdn.net/products/hop/Hop.dmg)

First launch: right-click `Hop.app` → **Open** → confirm
(the app is not notarized yet). Requires macOS 14 or newer.

## Features

### Timer & cycles

A dot-matrix countdown you set in one gesture: drag the digits, type the
time like on a microwave, or pick a preset. Work-rest cycles (25/5 Pomodoro,
52/17, 90/15 — or your own), a stopwatch, a stash that keeps a running timer
while you try another one, and a finish alert that can also pause your media.

### No sleep

Keep the Mac awake for 15 minutes, 8 hours or forever — one click, no
password. Optionally keep the display on, or keep working with the lid
closed (handy for downloads, long builds and external displays).

### System monitor

CPU and GPU load and temperature, memory and swap, network, disk, battery
health and power draw — live values with sparkline charts, color thresholds
you set yourself, °C/°F, and an uptime line. Readings come straight from
macOS and update only while the tab is open.

### Clipboard history

The last 100 (up to 300) things you copied, one click to copy back or
paste straight into the previous app. Passwords and other concealed input
are never stored.

### File converter

Drop a batch of images, PDFs, videos or audio onto the panel: JPEG, PNG,
HEIC, AVIF and WebP out; PDF compression; HEVC video shrinking with a live,
honest size estimate before you convert. Everything is processed locally.

### Window manager

Snap windows to halves, quarters, thirds and center with a click on a zone
glyph or a ⌃⌥ hotkey — no extra app needed.

### And the rest

Built-in speed test (Apple's networkQuality), dark and light themes with a
film-grain texture, global hotkeys, launch at login, and a safe mode that
recovers the app from a crash loop.

<div align="center">
<img src="https://www.antonshakirov.com/products/hop/screens/en/system.png" width="280" alt="Hop system monitor — CPU, GPU, memory, network, disk, battery charts">
<img src="https://www.antonshakirov.com/products/hop/screens/en/converter.png" width="280" alt="Hop file converter — batch image, PDF, video and audio conversion">
<img src="https://www.antonshakirov.com/products/hop/screens/en/settings.png" width="280" alt="Hop settings — themes, modules, hotkeys, 18 languages">
</div>

## 18 languages

Bahasa Indonesia, Deutsch, English, Español, Français, Italiano, Nederlands, Polski, Português, Tiếng Việt, Türkçe, Русский, Українська, हिन्दी, ไทย, 한국어, 中文, 日本語 — the app follows your system language out of
the box.

## Privacy

Everything runs locally: no server, no analytics, no accounts. The app only
touches the network to check for updates and when you run the built-in speed
test. Updates are delivered as signed archives and verified with an Ed25519
signature before installing.

Website: [antonshakirov.com/products/hop](https://www.antonshakirov.com/products/hop)

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

If Hop saves you a click or two, **[star the repo](https://github.com/antonyshakirov/hop/stargazers)** —
stars are how other people find it. Bug reports and feature ideas are
welcome in [Issues](https://github.com/antonyshakirov/hop/issues).

## Author & license

Made by [Anton Shakirov](https://www.antonshakirov.com/en). Released under
the [MIT license](LICENSE): use and modify freely, keep the copyright
notice — passing the app off as your own work is a license violation.
