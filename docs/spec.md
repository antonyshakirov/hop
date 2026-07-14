# Hop — behavioral specification

Single source of truth for how the app behaves. Any behavior change =
an edit to this file in the same commit. Re-read a module's section
before working on it. Maintained since 2026-07-12, full revision 2026-07-13.

## What it is

Hop is a menu bar multi-tool for macOS: timer, no sleep, system monitor,
clipboard, file converter, window manager. Design in the spirit of interval
(supercommon systems): dark panel, dot-matrix display made of glowing
dots. Open source, fully local: no server, no telemetry, no external
dependencies (system frameworks only).

Name: "hop" — the little word that accompanies a quick, nimble move;
"one click — and everything you need is here, hop — done." The French
"allez hop!" origin is deliberately NOT mentioned in any copy
(Anton's decision). The logo is a glowing asterisk star. The bundle id
stays `com.antonshakirov.minimo` forever; the "Minimo Signing" certificate
and the `~/.minimo-release-key` key are never renamed (permissions and
signing would break).

## Hard invariants of the panel (violation = regression)

1. **The panel always fits on screen.** Any expandable content has
   a height ceiling + internal scrolling (clipboard: ≤430pt). If the panel
   grows taller than the screen, NSPopover relocates to the edge — that is
   the "panel on the right" bug.
2. **The panel does not jump.** The popover anchor is the icon zone
   (`iconAnchor` — the exact image frame from the button cell, so the
   arrow is dead-center on the star). If a menu bar manager (Ice,
   Bartender, Hidden Bar) hides the icon (zero width / off-screen
   window), the panel opens detached at the TOP-RIGHT corner of the
   screen instead of being clamped into the top-left. Re-pinning
   positioningRect: when the button's WINDOW moves (didMove) — always;
   on panel resize — ONLY if origin.x actually moved (>0.5pt).
   Unconditional re-pinning on every resize makes the panel twitch.
3. **The menu bar button width is frozen** while the panel is open —
   the countdown/stopwatch STAYS visible (Anton, 2026-07-15), the string
   is padded with spaces to the frozen length; if the digits outgrow the
   slot (stopwatch passing an hour) the freeze extends and the didMove
   observer re-anchors.
4. **No repeatForever animations** — they trigger NSHostingController
   size recalculation. Icon changes are an opacity crossfade in a
   fixed-size ZStack.
5. Content size is fixed BEFORE the popover is shown (layoutSubtreeIfNeeded
   + contentSize); windows are shown via presentCentered (layout BEFORE show).
6. popover.animates = false; the popover theme follows the setting/system.

## Modules

The main screen is a stack of modules in user-defined order (drag to
reorder in the "general" settings tab). All modules can be hidden;
visibility toggles live ONLY in "general" (do not duplicate them in module
settings). The divider between modules sits exactly in the middle:
top inset = bottom inset = 16pt.

### Timer

- Counts toward a target date (`Date`), not by decrementing: it doesn't
  drift and survives Mac sleep. The panel can be closed — the countdown
  continues (ticker in TimerEngine).
- Presets: user-defined, edited in settings ("N ×" chips). In idle a preset
  sets the duration; during a countdown it puts the active timer into the
  stash, and the ↩ button restores and resumes it. There is one stash slot
  and it gets overwritten; deliberately starting a new timer clears the stash.
  In the UI the feature is labeled "restore the previous timer" — the
  "pocket" metaphor was dropped as unclear (Anton, 2026-07-14).
- Work-rest cycle presets: "work/rest×rounds" (e.g. 25/5×4);
  the section header is "work-rest cycles"; cards and digits are the same
  size as the time presets (font 11, NumericField 44×24).
- Time input: scrubbing on the display and per-digit-group entry. Scrubbing
  works in ALL display styles (dots/text/units) identically: the digit-group
  zone is computed from the display's actual width, with the same ratchet
  tick sound; in the "units" style without hours the display splits in half
  (minutes/seconds). **The minimum is zero**: 0:00:01 is valid; "−5" and
  scrubbing clamp to zero; pressing play with an all-zero value is an
  instant finish. TimerEngine.minimumDuration = 0. Scrubbing is disabled
  during a countdown.
- ±5 ("min" capsules) work while running; "−5" while running drives to
  0 → finish; `targetDate` is @Published, the UI doesn't wait for the ticker.
- Finish: signal per setting (sound+banner / sound / silent), the display
  blinks zeros, a bell blinks in the menu bar — until reset or a new start.
  Play from finished restarts the same duration.
- Stopwatch: ⏱ icon to the right of the presets, counts up, also shown in
  the menu bar. Mode switching is allowed from idle/finished/PAUSED
  (paused = "already stopped", so discarding an unfinished timer is
  deliberate); while running — a pulsing hint "press pause first".
  The switch does NOT depend on preset row visibility: with the preset row
  hidden it lives as a thin row (in the compact layout — in the same row
  as the timer); hiding the presets doesn't change the display style.
- Insignificant leading digit groups are dimmed (like interval's "00:").
- Display formats (dots/text/units): previews in settings show digits of
  equal height; the "digit size" setting (large/small) applies to
  ALL formats and both layouts, small ≈ half the large size
  (full view: dots 7.0/3.6, text 40/21, units 34/18; compact
  row: dots 4.8/2.6, text 26/14, units 23/12.5). Digit-group gestures
  compute the cell from the actual size. The format setting is labeled
  "timer format".
- Dot glow is proportional to dot size; on small cells (dot < 3px,
  mini previews) the glow and the background grid of "off" dots are not
  drawn — otherwise everything smears into noise.
- Transport: stop and play are identical 42pt circles.

### No sleep (awake)

- Keeps the Mac awake: downloads/processes aren't interrupted. Options
  15/30 min, 1/2/4/8 h, ∞ (turning it on without an option = ∞); the hour
  letter in the chips is localized (key unitHour), the ∞ glyph is raised
  1pt toward the optical center. Yellow moon + compact remaining time
  (29m / 1h59m, unit letters localized); clicking the moon turns it off.
  In the menu bar — the moon + the remaining time as text
  (monochrome: color doesn't render in the macOS status bar).
- IOPM assertion: PreventUserIdleSystemSleep by default (the display may
  sleep); "display stays on" → PreventUserIdleDisplaySleep.
- Lid: an icon button next to the moon (while awake is active). Enabling
  runs `pmset disablesleep 1` via AppleScript with administrator privileges:
  **the administrator password prompt comes from macOS itself — it is
  a system requirement, independent of signing or Developer ID.** Turning
  awake off, quitting the app, and time expiry restore sleep
  (`disablesleep 0`).
- The module's localized display name has changed several times —
  check L10n for the current one; in new copy convey the meaning
  ("your Mac won't sleep") rather than the module name.

### Monitor

- Polling: while the tab is open — every 2 s; the rest of the time a light
  background tick every 5 s (feeds chart history and the red indicator).
  History is timestamped points, ~31-minute buffer, accumulating since launch.
- Rows: cpu (load+temperature), gpu, memory (like Activity Monitor),
  network ↓↑, disk, battery (charge/temperature), health (health/cycles),
  power (watts), uptime. Colored SF Symbols icons.
- Value highlighting: white/green — normal, yellow — borderline, red —
  problem. Thresholds are configurable (temperature, load, disk, battery;
  battery semantics are inverted — below the threshold is worse). °C/°F:
  auto by region, can be set explicitly. "Calm" mode is the default:
  color only for problems; the full rainbow via the "color accents" toggle.
- CPU/GPU temperatures come from the private IOHIDEventSystemClient via
  dlsym: if Apple breaks the API we show "—" and don't crash. No disk
  SMART (it requires privileged access).
- Charts ("detailed" mode): below the metric row, both lines are shades of
  the metric's color; geometry is IDENTICAL across all cards: the scale
  (100/0, network peak) sits to the LEFT of the chart, the 176×24 chart
  is right-aligned to the rows' value grid. Scale labels are centered on
  their gridlines. Below the chart: "−5m" (window) on the left, "now" on
  the right, and a worded legend underneath (memory "used", network
  "↓ download / ↑ upload"). The chart window is a setting: 5/10/30 min or
  1 hour, default 5 (history buffer 61 min); lines are laid out by the
  points' timestamps. In chart mode the rows are larger (12pt).
- A red "!" on the left of the menu bar icon during a red zone (same
  thresholds that color the values; a charging battery doesn't count).
  OFF by default, toggle in monitor settings.

### Clipboard

- Copy history: text, links, files. A copied file is stored as its FULL
  path (the file-url is read BEFORE the plain-text type: Finder also puts
  the bare file name as a string, which alone is useless). Clicking a row
  puts the entry back on the clipboard (its position doesn't change); a row
  that is a path to an existing file goes back as the FILE plus the path as
  text — Finder pastes the file itself, text fields get the path. Buttons:
  copy / paste into the last app. Confidential content (password managers) is not stored,
  and everything lives only on this Mac. The entry limit is in settings.
- Search: the search field appears when expanded (case-insensitive
  substring filter, clear button; collapsing resets the query).
- Collapsed — 5 rows, expanded — up to 20, but that is only the HEIGHT of
  the list window: the full history is reachable via internal scrolling in
  both views. The height ceiling is DYNAMIC:
  min(430, screen height − 560), then internal scrolling (invariant #1!).
  A constant ceiling has already broken twice — once when removed and once
  when the module count grew. The proper final fix is clamping the height
  of the WHOLE panel to the screen (see "Planned"). The expand icon is a
  crossfade, no "flight". With ≤5 entries the expander is hidden and its
  state resets.

### Converter

- Separate window (drag & drop from Finder), width 540, height stretches
  (resizable, min 360), content in a ScrollView, window size is remembered.
  The queue lives in the model: closing the window does NOT lose it; the
  converter row in the panel reopens the window (↗). Dropping onto the
  panel row also adds files and opens the window. Folders are expanded
  (up to 500 files), duplicates are skipped.
- Groups: images / PDF / video / audio / unsupported. Each file gets:
  a thumbnail (QuickLook), name, its own size "current → ~estimated";
  the circle turns into a green checkmark when done (converted files stay
  in the list). The group total shows only with >1 file.
- Images: input JPEG/PNG/HEIC/TIFF/GIF/RAW; output JPEG/PNG/HEIC + AVIF.
  **WebP is deliberately removed everywhere (Anton's decision 2026-07-13):
  macOS has no system WebP encoder in any version; WebP input still reads.**
  The AVIF chip is shown based on actual system support.
- Scale ×0.25/0.5/0.75/1 (default ×1, scale applies to images only).
  Quality: images and PDF have INDEPENDENT sliders (convQuality /
  convPdfQuality, default 55).
- PDF: page recompression (~150 dpi), text stops being selectable.
- Video: MP4/MOV/M4V → MP4/MOV (original/1080/720/540). Audio: → M4A.
  MP3/MKV/WebM output is not supported by the system; we don't embed ffmpeg.
- Estimates are honest: images/PDF — a trial conversion of the first file +
  a curve over reference quality points (interpolation, no recompute on
  every slider move); video/audio — the system encoder's forecast. Per-file
  estimates use the sample's compression ratio.
- Results: Downloads / next to the original / custom folder; originals are
  never touched; "-min" names with uniquification.

### Speed test

- networkQuality (Apple servers), live numbers during the run.
- Result in a row: "↓ 834 Mbps · ↑ 112 Mbps · 1,450 RPM" — every value
  carries its OWN unit (a bare number is ambiguous, and download/upload
  can differ: Kbit/s vs Mbit/s), separators use thin spaces and
  the icon↔label gap is 6pt: the module label must never be squeezed into
  an ellipsis in any language. The refresh icon is hidden in snapshots
  (product-page screenshots) so the row doesn't reach the panel edge. RPM
  (responsiveness: round trips per minute under full load,
  <100 is bad for calls, 800+ excellent) is visible right away, not only
  in the tooltip.
- A result older than 30 minutes or from a different network is faded
  (textTertiary 0.45).

### Window manager

- Lays out the active window of the last "regular" app via the
  Accessibility API (our own popup is excluded from the count). 18 zones.
  Layouts APPROVED by Anton 2026-07-13: short — ONE row of 8
  (halves, center, full screen, ⅔ left/right); full — TWO rows of 8
  (first row the same; second: quarters, vertical thirds, center-half).
  Rows must be strictly equal in length — unequal rows misalign.
- Glyphs 26×16, fill inset 1pt (any more and the "half" turns into
  a strip). The "center" fill is smaller than the real zone, otherwise
  it is indistinguishable from "full screen".
- Global zone hotkeys: a toggle in windows settings (OFF by default),
  a fixed ⌃⌥ scheme: arrows — halves, ↩ — full screen, C — center,
  U/I/J/K — quarters. Registered via the shared HotkeyManager (id 101+).
- The Accessibility permission is requested on the first action.
  **TCC gotcha:** if the toggle in System Settings is on but actions
  don't work and the prompt keeps repeating — the TCC record went stale
  (old signature/path). Fix: `tccutil reset Accessibility
  com.antonshakirov.minimo`, restart the app, grant again.
- If a window doesn't land in a zone exactly — the app has a minimum
  window size and macOS won't shrink it below that.
- **Frame on the first click:** order size→position→size; during layout
  AXEnhancedUserInterface is disabled for the target app (Raycast/
  VoiceOver enable it, and the frame lands wrong); after setting, the
  frame is re-read and corrected with retries (up to 3) — "click several
  times" must never be needed.

## Shared components

- **SettingChip (Controls.swift) is the ONLY chip toggle** in the entire
  app: height 28, corner radius 5, mono 10 / icon 13, padding 9,
  inactive border Theme.divider, hover hoverDim+pointer. All former
  local chips (settingChip/unitChip/themeIcon/alertMode/styleChip/
  bigToggleChip/displayStyleCard, onboarding and converter chips) are thin
  wrappers over it. A new chip = SettingChip only; copies are forbidden.

## Panel and navigation

- Header: tab segments (main / monitor), gear (settings),
  ⏻ (quit, with a confirmation dialog). Panel width 368.
- Settings tab order: general → timer → remaining modules → monitor.
  "Remaining modules" = awake/clipboard/converter/windows as sections with
  headers. The app version is shown next to the "check & update" button.
  Toggles are our own MiniSwitch (the system Toggle doesn't render in
  ImageRenderer).
- Info page: per-module tabs, "term — explanation" style
  (the term is bold up to the " — ").
- Languages in pickers use the standard order, like system lists:
  alphabetical by NATIVE names, Latin → Cyrillic → CJK (pickerOrder,
  localizedCompare). FINAL per Anton 2026-07-13; the "by English names"
  variant was tried and reverted. "Same as system" sits on top; there is
  search.
- Menu bar: asterisk (brand glyph, 8 rays); on the right — play/pause
  badges (bottom) and a yellow awake dot (top); on finish — a blinking
  bell; the countdown is monospaced and can be disabled in settings.
- **The panel does not steal keyboard focus when opening**
  (makeKey is never called): dictation and Cmd+V go to the app underneath;
  input inside the panel is enabled by clicking a field/display.
  Anton's decision 2026-07-13.
- Right-click on the icon — a system NSMenu in sentence case:
  DYNAMIC items on top based on active state ("Stop Timer"/
  "Stop Stopwatch" during a countdown, "Turn Off No Sleep" while awake is
  active — they act without opening the panel), then Open / About /
  Settings / Quit.
- Launch at login — SMAppService.mainApp.

## Localization

- 18 languages: en ru de es pt fr it zh ja ko tr uk pl id th vi hi nl —
  in this order in L10n.swift (th/vi/hi/nl restored 2026-07-13: old
  translations from 2042b22 + new keys retranslated). A new UI string =
  ALL 18 at once; `--l10n-check` must pass. Check long languages
  (de, fr, hi) for truncation.
- Inside the panel — brand lowercase; system surfaces (NSMenu,
  notifications) — sentence case (.capitalizedFirst).

- Copy style: lively, no officialese and no literalism ("the Mac keeps
  counting" — bad; "lets you close the lid without shutting the Mac
  down" — good).

## Architecture and build

- `HopCore` (library, no UI): TimerEngine — a finite state machine
  idle/running/paused/finished + cycles + stash + stopwatch; TimeFormatting.
  Timer logic lives only here and only with tests.
- `Hop` (executable): SwiftUI panel, 5×7 dot font on Canvas,
  settings in UserDefaults, signals (NSSound Glass + UNUserNotificationCenter,
  notifications only work from the .app bundle).
- Full cycle after EVERY change: `swift build` (0 warnings) →
  `swift test` → `--l10n-check` → `./scripts/build-app.sh --install`,
  check in both themes.
- `--snapshot out.png [--stats|--finished|…]` — renders the panel to PNG;
  Toggle/TextField/onDrop produce artifacts in snapshots — a rendering
  quirk, not a bug.
- Signing: a permanent self-signed "Minimo Signing" certificate —
  permissions survive reinstalls. Ad-hoc fallback only if the certificate
  is missing (undesirable — TCC gets dropped).
- Branches: development happens in `dev`; merge to `main` only on an
  explicit "publish" go-ahead. Version stays 1.0.0 until the first release.
- Download CDN: Bunny pull zone hop-dl (id 6152002), host
  https://hop-dl.b-cdn.net, origin www.antonshakirov.com — on poor routes
  (VPN, distant regions) files download in about a second instead of
  minutes. Landing page links:
  DMG for people — https://hop-dl.b-cdn.net/products/hop/Hop.dmg,
  zip — https://hop-dl.b-cdn.net/downloads/hop/Hop-X.Y.Z.zip.
  release.sh purges the zone cache itself (Hop.dmg is unversioned).
  The updater stays on the direct domain (latest.json is tiny; control
  over it is critical).
- Distribution formats: DMG — for people, from the landing page (the
  "drag to Applications" window); ZIP+sig — for the auto-update channel.
  Both are built by release.sh.
- Public copy (mirror README, release notes, landing page) — ENGLISH
  ONLY: the project is international.
- Release mirror: https://github.com/antonyshakirov/hop — a public repo
  (created 2026-07-13), Release v1.0.0 with zip+sig; the code is NOT
  published (README stub only) — it goes up on Anton's explicit
  "publish the code" (git remote add + push of the real history on top;
  the release stays). From most regions GitHub's CDN is orders of
  magnitude faster than the origin VPS; a "Download from GitHub" button
  is worth adding to the landing page. New releases are duplicated:
  `gh release create vX.Y.Z Hop-X.Y.Z.zip Hop-X.Y.Z.zip.sig -R antonyshakirov/hop`.
- The dev build (bundle id …minimo.dev) does NOT check for updates
  automatically — it makes no network calls and doesn't trip testers'
  firewalls; it updates by rebuilding.
- The "it just works for users" path: sign releases with Developer ID
  + notarization (Apple Developer Program, $99/year) — Gatekeeper
  warnings and "suspicious signature" flags from firewalls
  (LuLu/Little Snitch) disappear. The self-signed "Minimo Signing" is for
  local development only.
- Updater: watches the GitHub Release (the repo will be antonshakirov/hop),
  the Ed25519 signature is mandatory, disabled until the public key is
  embedded; a silent check every 6 hours, installs only when the timer
  and awake are inactive.

## Planned (approved by Anton, not done yet)

1. **Lid without a password every time — IN PROGRESS in a second working
   session** via sudoers: a one-time password entry installs the rule
   `/etc/sudoers.d/hop-pmset` (NOPASSWD strictly for `pmset disablesleep 0/1`,
   validated with visudo), after which `sudo -n` runs without dialogs.
   The alternative (an SMAppService daemon + XPC) is deferred to avoid
   maintaining two mechanisms. TODO for the sudoers path: remove the rule
   when the feature is disabled or the app is deleted — the file in
   /etc/sudoers.d won't disappear on its own.
2. (done 2026-07-13) Icons in the documentation: DocView renders SF
   Symbols inline via the `{sym:name}` token in the translation string
   (engine in DocView.rich); icons accompany the transport, the clipboard
   expander, and the lid; the lid wording was rewritten in plain language
   in 14 languages.
3. (done 2026-07-13) Clamping the whole panel's height to the screen:
   content is measured with a GeometryReader; when it exceeds the visible
   screen area, a shared fixed-height scroll kicks in.
4. Backlog: ffmpeg formats on user request; Arabic/Hebrew will require
   an RTL pass.

## Repo workflow

- **Exactly ONE working session edits the repo at a time.** A second
  session is read-only/consulting. Parallel edits have already caused
  regressions: one session's commits picked up the other's unfinished
  files, builds failed with "modified during build", and fixed things
  got overwritten (the clipboard height ceiling).
- A behavior change = an edit to this file in the same commit.
- One commit = one feature/fix; `git add` only with an explicit file list,
  never `git add -A` / `commit -am` — otherwise the commit drags in
  someone else's work.

## App icon (Finder)
Style: auto / dark / light (settings → general). Applied via
NSWorkspace.setIcon on the bundle; "auto" follows the system theme.
The menu bar icon is always a monochrome system template.

## Language picker
A dropdown with search (settings panel and onboarding): matches by native
name, English name, and code (e.g. typing "German" finds "Deutsch").
The list shows only the native names; "same as system" is written in the
system language. Order — alphabetical by native names.

## Speed test
A main-panel module (hideable/reorderable like the rest). The "test"
button → the system `/usr/bin/networkQuality -c` (Apple CDN servers,
~15–20 s) → a "↓ N · ↑ M Mbit/s · RPM" row. Repeat via the ↻ icon. No
custom servers and no third-party services.

## Memory (monitor)
The memory row color is driven by SWAP, not by "used": macOS deliberately
fills all RAM with cache, so full usage is normal. Metric = (used + swap) /
physical RAM × 100, and it can exceed 100%. A separate "memory+swap %"
threshold (default: yellow 110, red 150), maxValue 300 — you can set, say,
red at 1.5× RAM. Swap is shown in the row when > 50 MB.

## Safe mode (crash loop)

A bug that crashes the app on launch must not cut off the path to an
update containing the fix.

- Every launch increments the `launchAttempts` counter (UserDefaults)
  BEFORE the model and modules are initialized. The counter resets after
  30 seconds of stable operation and on a clean exit
  (`applicationWillTerminate`).
- Three unfinished launches in a row = safe mode: the model, modules and
  SwiftUI are not created at all. In the menu bar — a "⚠" icon with an
  AppKit menu: the title "Hop — safe mode", a hint, the check status,
  "check & update", "quit".
- On entering safe mode, an update is checked for and installed
  automatically (the manual UpdateChecker path, bypassing the timer
  restrictions).
- If safe mode crashes too, the counter keeps growing — the next launch
  is safe mode again.
- The counter logic is `LaunchGuard`, covered by tests.


## Parallel dev build (after the 1.0.0 release)

Anton's primary install must always remain fully functional.

- `/Applications/Hop.app` (bundle id com.antonshakirov.minimo) is the
  stable one, updated only by releases (after "publish") or by auto-update.
- Day-to-day changes go into the parallel "Hop Dev.app":
  `./scripts/build-app.sh --install --dev` — its own bundle id
  (…minimo.dev), its own name and its own settings; it doesn't touch the
  main install and doesn't kill its process (pkill only by its own
  bundle path).
- Until the first release, `--install` still updates Hop.app directly.

## Info window

- Free resizing in both directions: content scrolls vertically; on width
  changes the section tabs wrap onto new lines (FlowLayout, natural-width
  chips) and the text reflows. Minimum 480×300.
- The window size is set explicitly (sizingOptions=[]); .preferredContentSize
  is forbidden — it crashed AutoLayout on baseline views.

## Versioning (approved 2026-07-13)

Semver MAJOR.MINOR.PATCH, starting at 1.0.0. The version changes only at
release time (on "publish"); dev builds don't touch the number.

- PATCH (+0.0.1) — fixes with no new behavior: bugs, crashes, translations,
  cosmetics. Auto-update installs it silently.
- MINOR (+0.1.0) — anything new that is visible to the eye: a module,
  a setting, a noticeable behavior/design change. PATCH resets to 0.
- MAJOR (2.0.0) — rare, meaning "the app has been rethought": a big
  redesign, a paid version, a compatibility break (settings migration,
  dropping old macOS versions).
- A release = merge to main + git tag vX.Y.Z + a line in CHANGELOG.md
  (in plain language; it doubles as the release notes) + a zip with an
  Ed25519 signature.
- `[critical]` in the release description — crash/security: the updater
  installs it at the first opportunity.
- The next release number is suggested from the commits since the last tag:
  fixes only — patch; anything new — minor.
- Cadence (Anton's rule, 2026-07-13): the first week after 1.0.0 —
  releases may be more frequent (shakedown period); after that NO more
  often than once every two days, aiming for once a week — changes
  accumulate in dev and ship as a batch.
  Exception — critical issues (crash/security): publish immediately
  with the critical flag.

## Update channel (production path, since 1.0.0)

- Manifest: `https://www.antonshakirov.com/downloads/hop/latest.json`
  (version, zip, sig, critical, date); the archive and signature sit
  next to it.
- Release: `scripts/release.sh X.Y.Z [--critical]` → files go into the
  website repo `public/downloads/hop/` (the `/hop/*` path is taken by the
  landing redirect) → commit + site deploy → `git tag vX.Y.Z`.
- Installation only with a valid Ed25519 signature (the key is embedded
  in the app; the private half is `~/.minimo-release-key`, outside the repo).
- The production `/Applications/Hop.app` is updated ONLY through this
  channel; `build-app.sh --install` without `--dev`/`--prod` refuses
  to install.
- The test build is "Hop Dev.app" (`--install --dev`), living in parallel;
  its icon carries a gold "D" badge in the bottom-right corner so the
  production and test builds can't be confused.


## Converter: window height and audio

- Window height = content + title bar inset (fullSizeContentView), up to
  75% of the screen; content is measured directly with
  GeometryReader.onAppear/onChange (a PreferenceKey through ScrollView
  returned 0). Programmatic resizing is recognized by the expected height
  (converterExpectedHeight), not by a temporary flag: didResize arrives
  asynchronously and the flag didn't survive long enough.
- Audio: exactly one output format — M4A (AAC); macOS has no built-in
  MP3/FLAC encoders, and we don't embed ffmpeg. The UI shows the single
  active chip with an explanatory hint rather than an empty row.
- Video: the "compress" quality = HEVC at the source resolution (~−40%
  size); the file's resolution ("1080p"/"4K", by the short side) is shown
  in the row; during export — a linear bar and percentages straight from
  the encoder (session.progress, polled every 300 ms).
- Video size estimates are calibrated against the actual encoder:
  1080p ≈ 10.8, 720p ≈ 6, 540p ≈ 3.2 Mbit/s; "compress" ≈ 60% of the
  source; "original" — the source size. Estimates are marked "~" and
  never exceed the source size.

## Timer: "okay, got it" after the ring

Clicking the blinking digits in the finished state (full display and
compact row) mutes the repeating sound, stops the blinking (the bell in
the menu bar calms down too — the state leaves finished) and returns the
timer to the configured duration (engine.reset). Per-digit-group editing
by click becomes available from the next click, already in idle.

## Timer: pause media on finish

The "pause media on finish" toggle (timer settings, off by default).
When the timer finishes, BEFORE the signal: if anything is playing through
the output device (CoreAudio kAudioDevicePropertyDeviceIsRunningSomewhere),
we send a genuine MediaRemote "pause" (loaded dynamically, private API),
falling back to the ⏯ media key on failure. On silence we do nothing —
a toggle must never START music. The "got it" click does not resume
playback.

### Panel/help details pinned 2026-07-14

- Compact timer transport tracks the DIGIT SIZE setting, not the layout:
  small digits → play/pause 27pt (icon 10) and reset 21pt (icon 9);
  large digits → 34pt/26pt as before.
- Settings → windows → "zone hotkeys": under the toggle sits a two-column
  legend "zone glyph + ⌃⌥ key" (shared `snapHotkeyItems` list with the
  help tab legend), replacing the old cryptic symbols-only caption.
- Help → general no longer ends with the "hop — and it's done…" closing
  line: it duplicated the page (removed in all 18 languages).
