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
3. **The menu bar button width AND the SET of readings are frozen** while
   the panel is open (Anton, 2026-07-15; the set generalised from a single
   bool 2026-08-04). Whichever clocks were speaking at open keep speaking
   until the panel closes, padded with spaces to the frozen length; if the
   digits outgrow the slot (stopwatch passing an hour) the freeze extends
   and the didMove observer re-anchors. **A clock stopped from the panel
   keeps its slot** and shows what it stopped at — a reset timer shows its
   configured duration, a stopped task the total it reached — because the
   space was already padded for it and a vanished reading leaves that
   space standing empty. Figures stay live inside their frozen slots.
   Hidden at open → a clock started from the panel does NOT surface until
   the panel closes; on close the bar reflects reality.
4. **No repeatForever animations** — they trigger NSHostingController
   size recalculation. Icon changes are an opacity crossfade in a
   fixed-size ZStack.
5. **Hover highlights bleed outward, they do not inset the content.** A
   full-width row (the "new task" footers) starts on the panel's own inset, so a
   highlight drawn on the row's exact bounds lands on the first glyph and on the
   panel's border at once. `hoverHighlight(_:bleed:)` grows the shape sideways in
   the BACKGROUND — the layout never moves — instead of padding the row, which
   would push its text off the shared left line (Anton, 2026-07-29).
6. **One horizontal inset for the whole panel.** The container pads 14pt
   left and right and modules add NOTHING of their own: labels, rows,
   cards, dividers and the edges of pill rows all start on the same line.
   Text INSIDE a pill is indented by that pill's own padding, which is the
   only allowed exception. Four modules used to add 2pt for themselves and
   sat two points to the right of every pill above them (fixed 2026-07-29).

5. Content size is fixed BEFORE the popover is shown (layoutSubtreeIfNeeded
   + contentSize); windows are shown via presentCentered (layout BEFORE show).
6. The popover size is rounded UP to whole points (IntegralSizeHostingController
   + integral fittingSize, content top-aligned): fractional SwiftUI text
   heights otherwise land the frame on a half pixel and the header icons
   jiggle 1px between tabs. The header is also STRUCTURALLY immovable: the fixed
   chrome (the "what's new" and 8-hour overrun banners + the header) is a sibling ABOVE the scroll
   region, never inside it, and ONLY the active space's module stack (or the
   settings/about overlay body) scrolls. Chrome and content heights are measured
   separately AND ROUNDED UP to whole points; the scroll region's fixed height is
   `min(contentHeight, maxPanelHeight − chromeHeight)`, so it flexes and clamps
   the whole panel to the screen while the chrome stays put. Whole-point rounding
   matters: the window size is a ceil of the natural panel height, so a
   fractional content height left chrome + content a sub-point shorter than their
   own ceil'd window, and that per-space leftover surfaced as a persistent 1px
   vertical shift of the fixed chrome (the header sat a point lower on taller
   spaces). Feeding whole-point heights makes chrome + content equal the window
   exactly — no leftover to place. Switching to a taller/shorter space changes
   the content height instantly and the measurement trails by one runloop, but
   the header is out of the scroll, so only the scroll region's bottom edge moves
   — the header cannot bob, nor be dragged by a leftover scroll offset (each
   space/overlay gets a fresh scroll identity that starts at offset 0).
6. popover.animates = false; the popover theme follows the setting/system.

## Menu bar icon — corner badges

**The icon's colour follows the MENU BAR, not the app.** A decorated icon is a
bitmap with its glyph colour baked in, drawn from `button.effectiveAppearance` —
the bar can be dark while the app is light (over a full-screen window, or the
instant the system flips), and reading `NSApp` instead left the icon in whichever
colour the bar had when it was last drawn, invisible on the other one (fixed
2026-07-29). A KVO observer on that appearance redraws it. The countdown beside
it never had the problem: AppKit colours a title itself.

The status-item star carries small badges in its four corners, on a fixed
22×17 canvas so the icon never changes width. The composition (which badge,
where) is a pure HopCore function — `IconBadges.compose(IconState) →
IconComposition` — with no AppKit, fully unit-tested (`IconBadgesTests`); the
renderer `MenuBarIcon.compose` only draws what it returns. Corner assignment is
spatial: attention top-left, awake dots top-right, time wedges bottom-right,
torrent arrows bottom-left. **Colours are the documented exception to the
Theme-token rule** — the badges use the fixed Apple system palette so they read
identically on every user's bar.

- **Bottom-right — time wedges.** A green `PlayGlyph` wedge (systemGreen) =
  the ENGINE's time is running — either a countdown timer OR a stopwatch; the
  two are mutually exclusive (one engine slot), so the star never distinguishes
  them (the title's digits already show whether the value falls or climbs).
  A dark-green wedge (opaque `#159E46`, a saturated ~40%-darker systemGreen) =
  a TASK is tracking. A wedge is drawn only while its clock is actually RUNNING
  (a play triangle means "running" — a PAUSED engine shows no wedge) AND only
  when that clock's value is NOT already spelled out as digits in the title (the
  digits are the wedge's redundant twin). So with the countdown ON (default) a
  running timer shows digits and no green wedge, while a tracking task still
  shows its dark-green wedge in the corner. With the countdown OFF both wedges
  can share the corner: green (engine) then dark-green (task), each a squat,
  seated, rounded triangle. The pair reads as a TIGHT pair with only a slight
  overlap (~0.8pt) and the LEFT (engine) wedge drawn on top, so its thin pointed
  tip merely grazes the right wedge's wide base — both stay visually equal and
  full-size (a bigger overlap, or drawing the right one on top and covering the
  left one's apex, made one read smaller). The pair is centred under the awake-dot
  columns within their footprint, and its stride is a whole point so the twins
  rasterise identically. A lone wedge is drawn larger, in the far-right column
  like a lone dot. The impossible "timer + stopwatch" combo cannot be expressed
  (the engine is one value), so a triple never occurs.
- **Top-right — awake dots.** Yellow (systemYellow) = no-sleep active; orange
  (systemOrange) = lid mode applied. They are independent, not a priority — BOTH
  dots can show, a dense row with a light overlap (in 1x they melt into one
  two-colour blob, accepted). A single dot sits in the far corner; a pair grows
  leftward.
- **Top-left — attention "!".** A saturated deep red (`#D81C0C`). Two sources:
  the monitor red zone (opt-in `menuBarRedAlert`) burns STEADILY; a task left
  running past 8h (`TrackerOverrun.isBannerVisible`, same episode/ack logic as
  the panel banner) BLINKS 1s-on/1s-off off the tracker heartbeat. If both are
  active the steady source keeps it lit. Tick-driven only — no `repeatForever`.
- **Corner-dot geometry.** Every corner dot is 5.0pt and hangs off the icon's
  CENTRE by the same distance in every direction (±8.0 across, ±5.5 down), so a
  dot in one corner is the exact mirror of a dot in another. The numbers are the
  only set where all four boxes also land on whole half-points (16.5 / 0.5 and
  11.5 / 0.5), so mirrored dots rasterise identically at 2x instead of one of
  them catching an extra half-pixel of antialiasing. Before this the awake dot
  was 5.2pt and sat 0.4pt further out than the 4.4pt VPN dot below it, which read
  as a crooked pair whenever both were lit (Anton, 2026-07-29).
- **Top-left — reminder dot.** A small `systemBlue` disc beside the "!" (in the
  corner itself when the "!" is dark), steady, never blinking: it reports
  something waiting rather than something wrong. Monochrome renders it as an
  outline ring, so it stays distinct from the filled "!". Visible while any to-do
  has an unacknowledged firing. One of the TWO badges with an off switch
  (`todoRemindMark`) — a documented exception to the rule below, because a
  reminder is a one-off user event whose signal belongs to the same family as the
  timer's finish signal, not an app state that is simply true or false.
- **Bottom-left — torrent arrows.** ↓ downloading, ↑ seeding (a FINISHED torrent
  actively uploading), or both side by side — the two can co-occur (one fetching
  while another seeds). Always the star's glyph colour (white/85%-black), the one
  bottom badge that is not green. `TorrentController.menuBarTransfer` supplies the
  two independent booleans. This REPLACES the old ↓/↑ glyph that lived in the
  title (which no longer carries transfer, so it can never shift the panel).
- **Colour vs monochrome.** The `colored indicators` setting (general, default
  ON) colours the badges. OFF renders every badge in the glyph colour and tells
  the three same-corner pairs apart by SHAPE: no-sleep = filled dot, lid = outline
  ring; engine = filled wedge, task = outline wedge (same outer size as filled);
  a live tunnel = filled dot, a stalled one = outline ring; the "!" and arrows
  stay their single shape. Per-badge on/off switches were
  rejected — a badge always shows while its state is active; only colour is a
  setting. Exactly two badges are exempt and both are named where they are
  described: the reminder dot (`todoRemindMark`) and the VPN dot
  (`vpnMenuBarMark`, in the VPN settings section, ON by default — and gone
  entirely while the VPN module is hidden). A tunnel is
  held by somebody else's app, so whether it is worth a mark is the user's call
  (Anton, 2026-07-29). There is NO on-screen symbol legend — a badge-meaning legend once
  lived in the info window's general tab but was removed (the icon is meant to be
  self-evident; the `colored indicators` toggle is the only badge-related
  surface there).
- **Retired indicators** (absorbed by the above): the yellow moon in the title,
  the hand-drawn tracking mini-stopwatch badge, the stopwatch title glyph, and
  the purple task-time idea (dark-green won). The finish **bell** is unchanged
  (base symbol, still blinks until acknowledged). The dev **"D"** mark
  (bottom-left, suppressed under `--snapshot`) and the template fast path for the
  calm undecorated star both survive. The template path is used only when the
  composition is empty; any badge routes through `compose`.

## Modules

The main screen shows the modules of the selected space (tab) as a stack,
in the order the user set. **A module always sits on exactly one space and
carries a `hidden` flag there** (`PanelTabsModel.hidden`): hiding it changes
nothing about where it lives, only whether the panel draws it. The eye in
"modules & tabs" and the "hide" item in a module's right-click menu are the
same switch. A hidden module is also switched off — it does not run and its
hotkey is handed back to other applications, unless
`hiddenModulesKeepHotkeys` says otherwise.

Older versions spelled hidden differently: the module was parked in an
"inactive" bucket off the spaces. That bucket is still decoded and
`liftInactiveIntoHidden` puts its contents back on the first space as hidden —
exactly what the user saw before the update. The conversion runs on every load
rather than behind a one-shot flag, so it cannot be missed or replayed, and
nothing is ever written back into the bucket.

The settings window is a 220pt sidebar and a page (`SettingsSidebar`,
`SettingsSelection`). The sidebar lists the sections first — "general" (theme,
language, launch, sounds, app icon, the `colored indicators` toggle for the
menu-bar badges, the Dock switch), "modules & tabs" for the panel layout,
"hotkeys", "app permissions" and "updates" — then every module of
`ModuleCatalog` in panel order, each with its icon and name
(`ModulePresentation`). A row wraps onto a second line rather than truncating:
the longest module names in German and French do not fit 220pt on one. A module's page carries its heading with a one-line
"what it is for" (`purpose*`, ×22 — the onboarding cards will read the same
keys), its own options (`moduleSettings`, keyed by the same identifier), the
hotkey of its "open" action — but only when something answers that key, since a
recorder for an action with no handler would promise what it cannot do — and a
link to the guide on the site. That link carries `?m=` with one letter per
module the user still sees (`ModuleCatalog.guideCode`, letters fixed forever by
`hop-website/docs/guide-code.md`, tested), and the site's own language when it
has one, so the page shows their Hop rather than every module there is. Two settings stayed off
the module pages because they are not about one module: the grids of apps (made,
renamed and removed on "modules & tabs", the only module a person creates
themselves) and "the converter and the archives in one row", which says how the
panel draws three modules rather than what any of them does. The window is 940×640,
resizable, minimum 820×480; the sidebar scrolls with the page. The section ids
of the old chip switcher still work in `--settings-section`: "timer" and
"monitor" open those two module pages. The "modules & tabs" section is
ONE combined table, a single row of columns: the space columns in order, then a
compact square "+" add-tab tile aligned to the TOP of its slot while under the
space cap (it was a full-height dashed column before — the stretch was dropped;
the revert is a one-liner noted in `addColumnStub`). Module chips (name,
lowercase) stack vertically in every column; a hand-rolled drag moves a chip
between columns and within a column (`move`/`reorder`) — placement only, since
the eye on the chip is the visibility control. A hidden chip is dimmed and its
eye is crossed out. While a chip is dragged, a live insertion
indicator marks exactly where it will land: a 2pt horizontal line with rounded
caps in the shared `Theme.editing` accent (the same yellow/goldenrod token the
timer digit-group highlight uses) between the rows of the target column
(top/bottom for first/last, and centred in an empty column); the target column
also tints while hovered. The indicator's position is read from the SAME
resolver that commits the drop (`insertIndex(for:in:at:)` → `SettingsDropGeometry`,
ONE shared stacked resolver for every column), so line and landing can never
disagree. Which column a point falls in is `SettingsDropGeometry.columnID(at:)`
(containment wins, else nearest by X), tested in `SettingsDropGeometryTests`. Each space column header carries
the space icon (a padded icon+chevron control with breathing room around the
hover highlight — tap it or its rotating disclosure chevron to open the icon
picker), "#N", and a hover-only delete xmark that opens a delete confirmation
(`delete this tab? its modules move to the first one and are hidden` +
delete/cancel); confirming moves them to the first remaining space and hides
them there, so a deleted space never makes a module appear somewhere the user
did not put it. The icon picker is an anchored popover under the header
control (the settings window is a real NSWindow, so a popover is safe here,
unlike the status-bar panel): a scrollable grid, ~7 columns, capped ~320pt
tall, of the curated SF Symbols catalog (`IconCatalog`, 200+ symbols grouped
by theme — home, time, work, media, and so on — with each group set off by
extra vertical spacing rather than a label to avoid a per-group translation;
every name resolves on macOS 14). It dismisses on outside click, Escape, or a
pick, and never reflows the table; a drag in progress cannot open it. The
delete confirmation is an overlay ON the table — a dimmed scrim plus a
centered card — so the columns never reflow beneath it; the scrim tap or
Escape cancels. Dragging a space column header horizontally reorders spaces
(`moveTab`, committed on release against the measured column frames), with a
vertical `Theme.editing` insertion line marking the landing slot while dragging
(read from the same `columnID(at:)` target the move commits to). Column-drag
and chip-drag never fight: the header and the chips are separate grab zones.
The page beside the 220pt sidebar is 720pt wide, so the space columns and the
"+" tile read comfortably across one row; chips truncate with `lineLimit(1)` in
every column. Under the table sits an airy tertiary caption
(`modulesTableHint`, ×22) stating what the eye does — the module keeps its place
and stops showing in the panel — and that both columns (to reorder tabs) and the
chips inside them (between/within columns) are draggable. Below the caption sit
the grids of apps (rename, the icon-name switch, ✕) and the
"converter and archives in one row" switch. The in-panel
`.settings` screen is unreachable (never set outside `init`, which always
pairs it with the standalone window), so the table is designed for that
window only. A module can also be re-homed from the panel: right-click it for
"move to" (one item per OTHER space, omitted when there is no other) and "hide".
A hidden module is simply not rendered, so there is no inverse "show" context
menu — that is the eye in settings. The divider between
modules sits exactly in the middle: top inset = bottom inset = 16pt.
- **The rule is `HopCore.ModuleVisibility`** and takes exactly three inputs: the
  hidden set, the torrent count, and the "show the card without downloads"
  preference. Torrent is the one module with an extra condition — with zero
  torrents its row is hidden unless the preference keeps it — and that condition
  used to ALSO require the engine installer to be exactly `.installed`. That made
  the user's answer conditional on machinery they never asked about: on the first
  launch after an update, while the engine downloaded, or after a failed fetch,
  the row returned to a panel where it had been switched off (Anton, 2026-07-27,
  straight after updating to 1.5.1). The engine no longer gets a vote — "do not
  show this without downloads" is an answer about the row.

### Timer

- **The clock never moves.** Presets and cycle templates sit BELOW the display
  and the play button, and the timer ↔ stopwatch toggle is always at the trailing
  edge of the clock row. They used to sit above, with the toggle travelling in the
  presets row, so switching to the stopwatch — which has no presets — dragged the
  clock, the play button and the toggle upward at once (Anton, 2026-07-29). In the
  large layout the toggle rides at the end of the transport row, mirrored by an
  invisible copy on the left so the play button stays centred; that copy is
  `allowsHitTesting(false)`, since an invisible live button is a trap.

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
  zone is computed from the display's actual width (`TimerDigits`, tested), with
  the same ratchet tick sound — TEN a second at most, because at thirty a fast
  drag turned the ratchet into a high whine (Anton, 2026-07-30). A brighter,
  denser ratchet (Tink at twenty) was tried on 2026-08-31 and rejected: the
  original Pop click is the ratchet. In the "units" style without hours the
  display splits in half (minutes/seconds).
- **The selected digit group lights up** (dots style, idle or finished, timer
  only): a click or a drag selects a group and its DOTS turn yellow — in both
  themes, with no plate and no tinted background behind them (Anton,
  2026-08-31). That glow is the only thing saying the keyboard now types into
  that group. Hovering does not select anything: a pale hover plate was tried
  the same day and rejected. The selection does outlive the pointer by ONE
  second after it leaves the digits (two felt slow — Anton, 2026-08-31), and
  every typed digit or backspace starts that second over, so a number being
  entered from the keyboard never loses its group mid-word. Esc and Return still
  end the entry at once. **The minimum is zero**: 0:00:01 is valid; "−5" and
  scrubbing clamp to zero; pressing play with an all-zero value is an
  instant finish. TimerEngine.minimumDuration = 0. Scrubbing is disabled
  during a countdown.
- ±5 ("min" capsules) work while running; "−5" while running drives to
  0 → finish; `targetDate` is @Published, the UI doesn't wait for the ticker.
- Finish: signal per setting (sound+banner / sound / silent). Every banner in
  the app goes through `Alerts.fire`, and every caller supplies BOTH a title and
  a body. The helper still owns a default pair for the timer, but a caller that
  passes only a title inherits it: that is how a finished torrent came to
  announce itself with "the timer has finished" over the torrent's own name
  (Anton, 2026-07-26). Torrent banners are built from `HopCore.TorrentBanner`,
  a value with no unset case — the title is the torrent's name and the body is
  one of three: "%@ downloaded · sharing continues" while it keeps seeding,
  "%@ downloaded" when it is already paused, and "sharing finished · %@ given
  back" the once the seeding policy stops it at ratio 1. The size quoted on
  completion is `progressBytes`, what actually landed on disk, since a partial
  file selection makes the nominal total a different number from the one the
  user can find in Finder. The finish
  sound plays EXACTLY ONCE (no repeat). The zeroed digits blink and a bell
  blinks in the menu bar — opening the panel acknowledges it
  (`TimerEngine.acknowledgeFinish`): the bell settles to a steady lit bell, but
  the zeroed digits keep a subtle pulse (`isFinishSettled`) as a "reset me" cue
  until a reset or a new start ends the finished state. Play from finished
  restarts the same duration.
- Stopwatch: ⏱ icon to the right of the presets, counts up. In the menu bar it
  shares the engine's green wedge with the timer (see "Menu bar icon — corner
  badges") — no separate stopwatch glyph. Mode switching is allowed from idle/finished/PAUSED
  (paused = "already stopped", so discarding an unfinished timer is
  deliberate); while running — a pulsing hint "press pause first".
  The switch does NOT depend on preset row visibility: with the preset row
  hidden it lives as a thin row (in the compact layout — in the same row
  as the timer); hiding the presets doesn't change the display style.
- Insignificant leading digit groups are dimmed (like interval's "00:").
- Display formats (dots/text/units): previews in settings show digits of
  equal height; the "digit size" setting (large/small) applies to
  ALL formats and both layouts, small ≈ half the large size
  (full view: dots 8.6/5.6, text 62/33, units 52/29; compact
  row: dots 5.3/2.9, text 29/15.5, units 25.5/13.7). The compact sizes are
  capped so the worst-case row — [start · reset · spacer · display ·
  stopwatch] with `00:00:00` at "large" — fits the 340pt content width with
  a few pt of margin (39 dot columns × 5.3 ≈ 207 + ≈122pt of chrome ≈ 329);
  the full display sits alone in its row at the panel-width ceiling. Digit-
  group gestures compute the cell from the actual size. The format setting
  is labeled "timer format".
- Dot glow is proportional to dot size; on small cells (dot < 3px,
  mini previews) the glow and the background grid of "off" dots are not
  drawn — otherwise everything smears into noise.
- Transport: the play/pause button is a circle; play draws the house rounded
  `PlayGlyph` (see "Play glyph"), pause SF `pause.fill`.

### No sleep (awake)

- Keeps the Mac awake: downloads/processes aren't interrupted. Options
  15/30 min, 1/2/4/8 h, ∞ (turning it on without an option = ∞); the hour
  letter in the chips is localized (key unitHour), the ∞ glyph is raised
  1pt toward the optical center. In the panel: a moon that turns yellow while
  active + compact remaining time (29m / 1h59m, unit letters localized);
  clicking the moon turns it off. In the menu bar it shows as a yellow corner
  dot (see "Menu bar icon — corner badges"), not a title glyph.
- IOPM assertion: PreventUserIdleSystemSleep by default (the display may
  sleep); "display stays on" → PreventUserIdleDisplaySleep.
- Lid: an icon button next to the moon (while awake is active). Enabling
  runs `pmset disablesleep 1` via AppleScript with administrator privileges:
  **the administrator password prompt comes from macOS itself — it is
  a system requirement, independent of signing or Developer ID.** Turning
  awake off, quitting the app, and time expiry restore sleep
  (`disablesleep 0`); switching duration options keeps lid mode. Lid mode
  never outlives the awake session — without it a closed lid would block
  sleep forever.
- While lid mode is active, closing the lid blanks the built-in panel:
  `disablesleep` keeps the backlight powered, so LidDimmer polls the
  clamshell state (1 s) and sets the built-in display's brightness to 0
  on close, restoring the saved value on open (persisted in defaults so
  a crash while dimmed is undone at next launch). External displays are
  untouched; the Mac keeps running unlocked.
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
- Units follow the system's own conventions (audited against Activity
  Monitor/Finder 2026-07-18): memory and swap in BINARY GB (Activity
  Monitor reports RAM that way — 24 GB of chips reads 24, not 25.8);
  disk in DECIMAL GB (Finder/About This Mac — a 1 TB drive reads ~995,
  the old binary formatter showed a phantom "926"); network speeds in
  DECIMAL units (1 MB/s = 10^6 — same as the torrent rows and converter).
  CPU load = (user+system+nice)/total ticks, the same figure as top's
  user+sys; GPU = IOAccelerator "Device Utilization %".
- Battery health = NominalChargeCapacity / DesignCapacity, capped at 100 —
  the same calibrated figure System Settings shows. The raw
  AppleRawMaxCapacity (fallback only) drifts with temperature/charge and
  showed 95–97% on brand-new machines next to the system's 100%.
- Value highlighting: white/green — normal, yellow — borderline, red —
  problem. Thresholds are configurable for load, disk and battery (battery
  semantics are inverted — below the threshold is worse). °C/°F:
  auto by region, can be set explicitly.
- **TEMPERATURE HAS NO THRESHOLD** (Anton, 2026-07-27), for the same reason
  memory has none: the system's verdict is the honest one. Apple publishes no
  thermal limit, and Apple Silicon sits at 90-100 °C under sustained load by
  design — the old fixed pair (yellow 70, red 90) called a healthy machine
  broken under any real workload, and said nothing about a fanless Mac
  throttling quietly in a warm room. Every temperature on the tab (cpu, gpu,
  ssd, battery) now takes its colour from `ProcessInfo.thermalState` through
  `HopCore.ThermalLevel`: nominal and fair are NORMAL — fair only means the
  fans have picked up — serious is yellow, critical is red, and an unknown
  future state never alarms. The number in degrees is still shown; only the
  verdict changed hands. A caption in monitor settings says so, and the two
  stored keys are swept on reset so an upgraded machine keeps no dead
  defaults. "Calm" mode is the default:
  color only for problems; the full rainbow via the "color accents" toggle.
- CPU/GPU temperatures come from the private IOHIDEventSystemClient via
  dlsym: if Apple breaks the API we show "—" and don't crash. No disk
  SMART (it requires privileged access).
- Charts ("detailed" mode, iStat style — Anton, 2026-07-15): below the
  metric row, a full-width filled area (gradient of the metric's color)
  with NO scale, legend or time labels — the row above already carries
  the current value, the shape shows the trend. The first series is the
  filled primary; secondary series (cpu temperature) are thinner plain
  lines in a shade of the same color. Network is TWO identical stacked
  areas (download/upload, shared scale) with tiny ↓/↑ corner markers.
  The window is clamped to the collected history — right after launch
  the areas otherwise started mid-chart and read as different widths.
  The chart window is a setting: 5/10/30 min or 1 hour, default 5
  (history buffer 61 min); lines are laid out by the points' timestamps.
  In chart mode the rows are larger (12pt). The GPU row carries the same
   two-series card as the CPU (load filled, temperature as the thin line) —
   added 2026-07-29, it was the one metric with a number and no trend — and
   the card is drawn ONLY when this Mac reports a GPU load or a GPU
   temperature: an empty chart is worse than no chart.
- A red "!" (top-left of the menu bar icon, steady) during a red zone (same
  thresholds that color the values, and for heat the system's own critical
  state; a charging battery doesn't count). OFF by
  default, toggle in monitor settings. It shares the top-left "!" with the
  tracker's 8-hour blink — see "Menu bar icon — corner badges".

### Clipboard

- Copy history: text, links, files, images. Capture ORDER is decided by a pure
  rule in HopCore (`ClipboardRules.classify`): a copied FILE beats image data,
  image data beats bare text. Files win FIRST because Finder ships the file's
  icon/thumbnail preview on the pasteboard next to the file URL — reading the
  file URL first stops a copied file (e.g. a 1024×1024 icon) from landing as a
  "1024 × 1024" image row. A copied file becomes a FILE entry showing the file
  NAME (small `doc` glyph); several files copied at once show `name +N`. The
  paths are stored, not the contents. Clicking a row puts the entry back on the
  clipboard (its position doesn't change); a FILE entry goes back as the file
  URL(s) plus the path text — Finder pastes the file itself, text fields get the
  path (vanished files are skipped). File entries never take part in text dedup.
  Buttons: copy / paste into the last app. Confidential content (password
  managers) is not stored, and everything lives only on this Mac. Pruning a file
  entry off the history never deletes the file on disk. The entry limit is in
  settings.
- Images: raw clipboard image data (a screenshot copied straight to the
  clipboard via ⌃⇧⌘4, "copy image" in a browser) is stored as a PNG in
  Application Support (per bundle id); the row shows a small thumbnail and
  the dimensions ("1280 × 800"), clicking puts the picture back. Own cap
  of 20 image entries (plus the shared limit) — the files of everything
  pruned are deleted; entries whose file vanished are dropped at launch and
  orphan files are swept. Images over 25 MB are skipped. Image entries
  never take part in text dedup.
- Search: the search field appears when expanded (case-insensitive
  substring filter, clear button; collapsing resets the query).
- Collapsed — a user-chosen number of rows (settings, 1...10, default 3),
  expanded — up to 20, but that is only the HEIGHT of
  the list window: the full history is reachable via internal scrolling in
  both views. The height ceiling is DYNAMIC:
  min(430, screen height − 560), then internal scrolling (invariant #1!).
  A constant ceiling has already broken twice — once when removed and once
  when the module count grew. The proper final fix is clamping the height
  of the WHOLE panel to the screen (see "Planned"). The expand icon is a
  crossfade, no "flight". With ≤5 entries the expander is hidden and its
  state resets.

### Clipboard: an entry as a file (1.7.0)

- OFF by default (`clipboardToFile`). When on, every TEXT row grows one more
  icon, LEFT of copy and paste: it acts on the entry rather than on the
  pasteboard, so it comes first. An image, a copied file or a colour has no
  document in it and shows no icon.
- **The format is a setting** (`clipboardToFileFormat`, default `txt`): txt, md,
  pdf or docx, offered as chips labelled with the extensions themselves — the
  converter's chips do the same, and "pdf" needs no translation. txt and md are
  the text as it stands; pdf and docx are RENDERED through the document module's
  own writers, so a copied markdown snippet comes out formatted instead of
  showing its asterisks, and the pdf carries Hop's typography. An unknown stored
  value falls back to txt rather than refusing to save.
- The file lands on the DESKTOP, named after the text itself:
  `ClipboardDocument.fileName(for:)` takes the first LINE (not the first
  characters — a paragraph should be named after its opening sentence, not
  trail into the second), strips what a file name cannot hold, collapses the
  whitespace, cuts to 40 characters and refuses to start with a dot. Text that
  survives none of that is saved as `clipboard.txt`.
- A name already taken gets Finder's own treatment — ` 2`, ` 3`… — so saving
  the same entry twice never overwrites the first file
  (`uniqueName(_:ext:taken:)`, both in HopCore with tests).
- **A written file says so in the row**: the save icon becomes a green tick for
  four seconds and then comes back. Longer than the copy tick (one second) on
  purpose — copying is confirmed by whatever you paste a moment later, while a
  file written to the Desktop gives no other sign that it exists. A cancelled
  save panel writes nothing and shows no tick.
- `clipboardToFileAsk` swaps the silent Desktop save for the system's save
  panel, the one place where the name can be retyped and the folder chosen in a
  single step. The panel opens on the Desktop with the generated name already
  filled in and the chosen format's type set, so "ask" costs one Return.

### Converter

- Separate window (drag & drop from Finder), width 540, height stretches
  (resizable, min 360), content in a ScrollView, window size is remembered.
  The queue lives in the model: closing the window does NOT lose it; the
  converter row in the panel reopens the window (↗). Dropping onto the
  panel row also adds files and opens the window. Folders are expanded
  (up to 500 files), duplicates are skipped.
- Paste feeds the clipboard into the converter exactly like a drop, ingesting
  EVERYTHING it supports at once: every file URL on the pasteboard
  (`readObjects(forClasses: [NSURL.self])` returns all items, so a multi-file
  Finder copy adds them all), or a raw image with no backing file (a screenshot
  copied to the clipboard) written to a temp file first — both routes end at the
  same `addToBatch` path. In the panel, ⌘V / ⌘⇧V ingest ONLY when the converter
  is on the active space and no field is being edited (a focused tracker/to-do
  field or timer-digit entry keeps the keys); otherwise the keys pass through,
  and the clipboard module's own paste is untouched. In the standalone window ⌘V
  works regardless of click-focus — Hop is an accessory app with no Edit menu, so
  there is no Paste key-equivalent to drive SwiftUI's `onPasteCommand`. The
  primary route is a local keyDown monitor installed with the window: it fires
  before `NSApplication`'s key-window routing, so paste does NOT depend on the
  window being `NSApp.keyWindow`. Paste chords are matched by the PHYSICAL V key
  code (kVK_ANSI_V = 9), never by the produced character — `charactersIgnoringModifiers`
  is layout-dependent, so ⌘V on a Russian layout arrives as a Cyrillic character
  and a character check would silently drop the paste. Both the panel and the window use the pure,
  tested `KeyChord.isPasteChord` (⌘ held, ⇧ allowed, ⌃/⌥ absent), so paste is
  keyboard-layout-independent. This matters because the window is often opened
  from a background state (the user copied files in Finder, then triggered Hop),
  and `NSApp.activate` is asynchronous — on macOS 14+ cooperative activation it
  can lag or be denied — so `keyWindow` can be nil at the moment ⌘V is pressed;
  a plain key-equivalent would then reach no window and the paste would be
  silently dropped. The monitor ingests ⌘V only when the converter window is the
  intended target — visible AND (already key, or no window has claimed key yet) —
  so it never steals ⌘V from another window that owns key (the gate is the pure,
  tested `ConverterPaste.shouldIngest`). `ConverterWindow.performKeyEquivalent`
  (which calls `super` first) is retained as a harmless fallback, but the monitor
  is the actual route: it fires first and consumes ⌘V, so nothing double-adds
  (and `addToBatch` dedups by path regardless). The converter window has no
  editable field, so the monitor claiming every ⌘V while the window is the target
  is safe. An empty or text-only clipboard is a silent no-op; an unsupported file
  lands in the "unsupported" group, same as a dropped file of that type.
- Groups: images / PDF / video / audio / unsupported. Each file gets:
  a thumbnail (QuickLook), name, its own size "current → ~estimated";
  the circle turns into a green checkmark when done. Finished files
  auto-hide by default (the "auto-clear" setting, ON since 2026-07-15);
  with it off they stay in the list with the checkmark. The group total
  shows only with >1 file.
- Images: input JPEG/PNG/HEIC/TIFF/GIF/RAW; output JPEG/PNG/HEIC + AVIF.
  **WebP is deliberately removed everywhere (Anton's decision 2026-07-13):
  macOS has no system WebP encoder in any version; WebP input still reads.**
  The AVIF chip is shown based on actual system support.
- Scale ×0.25/0.5/0.75/1 (default ×1, scale applies to images only).
  Quality: images and PDF have INDEPENDENT sliders (convQuality /
  convPdfQuality, default 55).
- PDF: page recompression (~150 dpi), text stops being selectable.
- Video: MP4/MOV/M4V/AVI/MPG → MP4/MOV. Audio: → M4A. MP3/MKV/WebM output is
  not supported by the system; we don't embed ffmpeg.
- **iWork documents are exported by iWork** (`IWorkExport`, tested; Anton
  2026-08-28). Pages, Numbers and Keynote files form a group of their own:
  `.pages`, `.numbers`, `.key` in; PDF out, or each document's own Office format
  — docx, xlsx, pptx — chosen by one switch, since a mixed batch needs one
  setting to serve three kinds of document. Hop does not read these formats at
  all: they are undocumented protobuf containers whose third-party readers break
  on every major release, formulas first. It sends the application an Apple
  Event to run its own "Export to…", so the result is exactly what doing it by
  hand produces, and there is nothing of ours to go stale.
  - **Nothing is required up front** (Anton, 2026-08-28). A `.pages` file joins
    the queue whether or not Pages is installed; only THAT file fails if it
    turns out not to be, and the rest of the batch carries on. The Automation
    permission is likewise asked for by macOS at the first export — there is
    nothing to grant until something is actually being converted. The row says
    so before the button is pressed.
  - The document is opened, exported and closed WITHOUT saving: a batch must
    never modify what it was handed. Failures are read apart — permission
    refused (-1743), application missing (-600 / -10814), or the document
    itself — because the first two are fixable and say different things.
  - No size forecast: the output is another application's work, so the group
    shows what it weighs now and nothing more.
  - Dev entry point: `Hop --iwork-selftest <file> <out dir> [pdf|office]` runs
    one export through the app's own path.
- **What counts as convertible is asked of the system**, not kept as a list
  (`systemCanRead`, 2026-08-04). MKV, WebM, WMV and FLV all classify as movies
  and AVFoundation cannot open ANY of them; they used to land in the video group
  and fail at convert time with nothing said in advance. WMV and FLV are named
  unsupported on arrival now, in the drop itself. AVI and MPG do open, subject
  to the codec inside them (a modern AVI yes, an old DivX one no). The same
  check covers audio, where WMA is the one that cannot be read.
- **MKV and WebM are repacked rather than refused** (`RemuxRules`, Anton
  2026-08-28). Their container is the whole problem: the picture inside is
  usually h264 or hevc, which MP4 holds perfectly well, so swapping containers
  is a COPY — a second of work, nothing lost, and what comes out is an ordinary
  MP4 the normal pipeline reads. They therefore classify as video, and the
  repack happens first inside `convertVideo`; every setting then applies to the
  result exactly as it would to any mp4. When nothing else was asked for (no
  compression, no reframing, mp4 out) the repacked file IS the answer and is
  moved into place rather than copied through a passthrough export.
  - The copy is done by a downloaded helper — a minimal LGPL ffmpeg built by
    `scripts/build-remuxer.sh` (Matroska in, MP4 out, no encoders, no GPL
    parts), installed through the same `ToolInstaller` mechanism and Ed25519
    gate as the torrent engine and 7-Zip. Hop bundles no third-party binaries.
  - **The button fetches it, not the drop** (the archive module's rule): the
    helper downloads when convert is pressed on a batch that contains one of
    these files, and the batch then starts by itself. Before that, a line under
    the video settings says a small helper will download once; during, it shows
    the percentage; a failed fetch says so rather than failing file by file.
  - The first video and (if present) the first audio track are copied;
    subtitle and data tracks are dropped, since MP4 cannot hold them the way
    Matroska does and re-encoding them is not what a repack is.
  - **What it will not do is re-encode.** A webm carrying the classic vp8 +
    vorbis pair cannot go into MP4 at all, and that file fails rather than
    quietly becoming a re-encode nobody asked for.
  - No forecast and no resolution chip transition are shown for these files
    until they are repacked: both are read from the asset, and until the
    container is swapped there is no asset to read.
- Resolution chips ALWAYS all show; the ones above the source's short side are
  dimmed and unclickable (`SettingChip.enabled`). They used to be hidden, and a
  row that changes shape as its neighbour is clicked reads as a bug — picking
  540p made 1080p and 720p vanish (Anton, 2026-08-04).
- Video settings are four independent rows (Anton, 2026-07-15; the dial added
  2026-08-04): "format: MP4 / MOV" — two chips, and until the user picks one
  the HIGHLIGHTED chip is the container the pending files already have, so an
  mp4 stays an mp4 (`highlightedVideoFormat`). There is no "original" chip: the
  row should read as the answer, not as a setting that stands for one (Anton,
  2026-08-04). A format the system cannot write (avi, mkv) highlights mp4,
  which is what it becomes. Changing the container does nothing for size — "resolution: original / 4K / 1080p / 720p /
  540p", "frame" + "fit" (see the reframing entry below), and "compression" —
  a toggle (HEVC instead of H.264, ON by default) plus, when it is on, a
  1…100 slider (`convVideoQualityLevel`, default 55) saying HOW HARD to squeeze.
  The legacy single "quality" value migrates into the pair on first launch
  ("hevc" → original + compress).
- **One label column for every group** (Anton, 2026-08-28): images, PDF, video,
  audio and documents all start their values on the same line, 104pt in, so the
  window reads as one table rather than five. A per-group grid was tried first
  and only lined a group up with itself. The image and PDF quality dial is an
  ordinary labelled row now too — it used to float alone on the far right of its
  card while everything else began at the left.
- **The dial shows the bitrate it means** — "55  ≈ 3.7 Mbps" — computed for the
  first video in the queue at the frame the settings will give it and at that
  file's own frame rate (`projectedBitrateText`). A percentage says nothing
  about what is kept or lost; megabits are the figure every platform states its
  own guidance in, and the one a person can hold a floor under (Anton,
  2026-08-28). Hidden with compression off, where nothing sets a bitrate.
- **The fit row draws what it does** (`FitGlyph`): the CHOSEN FRAME with a
  source-shaped picture inside it — filling it and cut by its edges (crop),
  whole between empty bars (bars), or whole over a filled ground (blur). It
  follows the frame row, so picking 9:16 turns the diagram vertical. Three words
  are three guesses until you see them, and a diagram that ignored the frame
  said even less.
- **An image conversion that asks for nothing is a COPY** (`ImagePassthrough`,
  tested; Anton 2026-08-28): same format, full scale, quality at the top — the
  file itself is the answer, and it is copied rather than re-encoded. Asking a
  JPEG encoder for 100 is not "leave it alone": the original was written at some
  ordinary quality with subsampled colour, and the best-quality write keeps full
  colour and barely quantises, so a grainy photo came back four times heavier
  for a picture nobody can tell apart. The quality row says "original" while
  that is what will happen, and the size forecast follows, since the estimate
  runs the same conversion.
- **"Off" and "the dial at 100" are different things**, so the row says which is
  which: with compression off it reads "original", because the tracks are then
  copied across untouched — no encode at all. At 100 the file IS re-encoded, at
  the top of the dial's bitrate. The switch also keeps its distance from the
  dial: side by side they read as one control.
- **Platform presets** (`VideoPlatform`, Anton 2026-08-28) sit ABOVE those rows
  as a shortcut across three of them: "for: reels / feed / tiktok / shorts /
  youtube". Somebody about to post is thinking about where it goes, not in
  ratios and megabits, and the platforms publish both. A preset writes the same
  settings a person would write by hand — shape, resolution 1080 and the
  compression dial — and stores NOTHING of its own, so changing any of those
  afterwards simply unlights it. The figures are the platforms' own published
  recommendations at 1080p30: 5 Mbps for the two Meta frames (9:16 and 4:5),
  8 Mbps for YouTube, Shorts and TikTok; all five ask for 1080 across the SHORT
  side, and only the shape differs. The dial position comes from
  `VideoBitrate.quality` — the inverse of the bitrate formula — so **the target
  is the file's WEIGHT, not the codec's quality**: the leaner codec is asked for
  the same megabits and spends more of its dial to get there, which buys a
  better picture at the size the platform wanted. A preset always turns
  compression ON: with it off nothing controls the bitrate and the platform's
  number is not what comes out. `fit` is deliberately left alone — crop, bars or
  blur is a taste question the platform has no opinion on. More than one chip
  can light at once and that is the truth rather than a clash: TikTok and Shorts
  ask for the same file. A source smaller than 1080 is never upscaled (the frame
  shrinks instead, per `VideoFrame.layout`), so the preset stays honest on small
  footage even though the 1080p chip in the resolution row is dimmed there.
- **Hop drives the video encode itself** (`encodeVideo`, 2026-08-04). The system
  export presets take no bitrate, and their "highest quality" re-encoded most
  footage back to roughly its original size: the converter looked like it was
  doing nothing, whatever the settings said. An AVAssetReader feeds an
  AVAssetWriter with `AVVideoAverageBitRateKey` set from `VideoBitrate`
  (bits-per-pixel-per-frame interpolated over the dial, squared so the travel
  sits where the eye notices, HEVC at 0.65 of H.264, floor 120 kbps; audio
  re-encoded to 128 kbps AAC). Key frames every 2 s. With compression OFF and no
  reframing to do, the tracks are copied across with `AVAssetExportPresetPassthrough`
  instead — a container change costs a second, not a re-encode.
- The video forecast is arithmetic, not a trial encode: bitrate × duration + 2%
  container overhead, and never more than the original (a re-encode that would
  come out heavier keeps the original size in the forecast). Measured against
  real encodes it lands within 2-12%, the widest gap at the bottom of the dial
  where key frames weigh most. The old path encoded eight seconds and
  extrapolated — slow, and with the old presets it forecast the original size no
  matter where the settings stood.
- Downscaling is hop's own videoComposition targeting the SHORT side,
  aspect ratio and orientation preserved — a vertical 1244×1664 at
  "1080p" becomes 1080×1444. The system resolution presets fit into a
  LANDSCAPE box (807×1080 for that source) and were dropped. Never
  upscales; dimensions are rounded to even for the encoders.
- Estimates are honest: images/PDF — a trial conversion of the first file +
  a curve over reference quality points (interpolation, no recompute on
  every slider move); video — bitrate arithmetic (above); audio — the system
  encoder's forecast. Per-file estimates use the sample's compression ratio.
- All converter sizes use decimal units (1 MB = 1,000,000 bytes) — the same
  scale as Finder, so the promised and the delivered numbers match; binary
  MiB read ~5% smaller and made every result look heavier than estimated.
- Each group card carries an honesty note "output size is approximate"
  (convApproxNote) while files are pending; during conversion the card
  shows a whole-batch progress bar, a percentage and "converting… i/n".
- **A video row reads "718p → 404p"**: the source resolution and what the
  current settings will actually produce, worked out through `VideoFrame`. It
  showed only the source before, so picking 540p left "718p" standing over it
  (Anton, 2026-08-04). The two agree — and only the source shows — when nothing
  about the frame changes. The result can differ from the chosen resolution: a
  718p landscape clip asked for a 540-wide reel comes out 404p, because the
  frame shrinks rather than upscale.
- **The bar is weighted by BYTES, not by file count** (Anton, 2026-08-04).
  Counting files made a batch of one jump from nothing to everything, and a
  large file among small ones sat still and then leapt. Each file's share of the
  bar is its size; inside a file, video reports its own fraction from the
  encoder and PDF compression reports one per page. Publication is THROTTLED to
  ten a second: the encoder reports every sample, thirty times a second, and a
  bar told to animate to a new value that often never finished a move — it sat a
  few percent in while the percentage beside it ran to a hundred. The end of
  every file publishes regardless of the throttle, so the bar never stops short,
  and a 0.12 s linear ease covers the gap between publications. The bar itself
  is TWO CAPSULES drawn by hand, not a `ProgressView`: AppKit's own animates to
  its own schedule and, fed several values a second, was a fifth of the way
  along while the percentage beside it read 100. The fill is exactly as long as
  the number says, with NO animation on it: the reports are already ten a second,
  and an animated subtree made the fill lag its own colour, so the percentage
  went green while the bar was still orange. Bar, percentage and label all turn
  green together at 100% — orange is for work in progress.
- A finished batch plays its own sound (`Sounds.converted()`, "Ping"), not the
  timer's alarm: "your time is up" and "your files are ready" are different
  messages. It obeys the single app-sounds switch like every other cue.
- **Where it landed is one click away**: once anything has been converted the
  footer carries a folder button naming the destination folder, which reveals
  the last output IN Finder with the file selected (`activateFileViewerSelecting`).
  It follows wherever the files actually went — Downloads, the source folder or
  a custom one — because it is built from the produced file's own URL rather
  than from the setting.
- Clicking the menu bar star brings already-open auxiliary windows
  (converter/settings/about/torrent add) back to the front together with the
  panel — they sink behind other apps on deactivate and looked "closed".
  The raise PRESERVES their mutual stacking order (it walks the current
  front-to-back order in reverse), so the user's arrangement is not reshuffled
  on every summon (Anton, 2026-07-19). Miniaturized windows stay in the Dock.
- Panel z-order: the panel is a transient popover on an elevated level. It is
  above OTHER apps' windows only while explicitly summoned (status-item click,
  the show-panel hotkey, or the right-click "open" item). App activation alone
  — clicking one of Hop's own real windows, cmd-tab — never shows or raises the
  panel. If the panel is open when the user clicks one of Hop's own windows,
  the panel closes (like any outside click), so it cannot resurface above that
  window on the next activation (Anton, 2026-07-19).
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
- Global zone hotkeys: a toggle in the window-manager section of the "other
  modules" settings tab (moved out of "general" 2026-07-21; ON by default —
  Anton, 2026-07-15), a fixed ⌃⌥ scheme
  covering ALL 18 zones:
  arrows — halves, ↩ — full screen, C — center, U/I/J/K — quarters,
  D/F/G — vertical thirds, E/T — two-thirds, S — center column,
  O/L — top/bottom thirds. Registered via the shared HotkeyManager
  (id 101+). The settings label reads "resize windows with hotkeys"
  (not the old "zone hotkeys").
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

### Tracker

- Time tracker over tasks that can be grouped into PROJECTS (dissolved in 8.14,
  brought back in 1.9.0 — Anton, 2026-08-28 — because the week figures below
  are only worth reading per project). All
  logic lives in HopCore (`TrackerEngine`, persisted to `tracker.json` via
  `TrackerController`); the view is glue. Labels tick off `tracker.heartbeat`
  (1/s while a task is tracking). Active by default — unlike torrents it has no
  engine to download, so it isn't opt-in; hidden or shown like every other
  module by its eye in the "modules & tabs" table. The module title (`trackerLabel`) is "time tracker" — it
  names the feature in settings and in the always-on subheader above the list.
- **Two levels, three orders.** `TrackerTask.projectID` is the single source of
  BELONGING — nil for a task at the top level, a project's id for one inside it.
  `TrackerData.rootOrder` says what the top level looks like: project ids and
  project-less task ids, mixed, each exactly once. Every project's `taskOrder`
  says the same for its own tasks. The orders never decide whose a task is; they
  only say where among its siblings it sits. `normalizeStructure` repairs all of
  it on load — a task pointing at a project that is not there comes back to the
  top level, listed ids that are not real are dropped, and anything missing is
  appended in the arrays' own order. Each mutation fires `onChange` once.
- **The period switch** (`TrackerPeriod`, stored in `trackerPeriod`, default
  "total") sits on the subheader line and picks what EVERY figure in the module
  covers: today, this week, or all time. One switch rather than three columns —
  three numbers per row in a 360-point panel is a spreadsheet, not a list. It
  drives the task figures, the project sums, the scrub and the typed edit alike:
  editing while "week" is showing sets the week. A task in the middle of a RUN
  shows the run instead of its period figure (see "A run, and the ✓ that ends
  it") — project sums are unaffected, since a run's time is counted from its
  first second. Every edit lands as a
  correction dated TODAY whatever the period, because today sits inside this
  week and inside all time, so the three stay consistent with each other.
  The week is cut by `Calendar.dateInterval(of: .weekOfYear)` on the engine's
  calendar, whose `firstWeekday` is the user's own setting (the same one the
  reminder weekday row uses); changing that setting recuts the figures live
  (`TrackerController.refreshWeekStart`).
- The disclosure triangle is the house play glyph in SOLID ink under an
  explicit opacity (`Theme.glyphInk` + `compositingGroup`), not a translucent
  colour: that glyph is a fill under a round-join stroke, and with a translucent
  colour their overlap is denser than the edges — which reads as an outline
  drawn around the triangle (Anton, 2026-08-28).
- **Projects on screen:** a DISCLOSURE TRIANGLE folds and unfolds (`isExpanded`,
  stored — a folded project stays folded across restarts), the name is semibold,
  and the trailing figure is the sum of its tasks over the current period. A
  FOLDED project whose task is running carries a small green dot, since its play
  glyph is not on screen. Hovering reveals a "+" (add a task straight into it,
  the same 10pt glyph the footer's own add uses) and the delete ✕. Contents are
  indented 16pt.
- **Renaming lives on the NAME, not on the row** (Anton, 2026-08-28). With the
  whole row taking the tap, the triangle's own click was swallowed by it: folding
  a project started a rename instead. The row keeps only the drag; the name has
  the tap.
- **The add row carries both** — "new task" at the left, "new project" pushed
  out to the RIGHT, onto the column the times line up in (Anton, 2026-08-28).
  Side by side, the project button read as trailing the task one; on the time
  column it reads as belonging to the list.
- **An open task keeps its own row above the card** (Anton, 2026-08-28). The
  card used to REPLACE the row, which left a form with no subject: nothing said
  whose name was being edited, or whose history sat below it. The row stays —
  name, star, play button and figure — and tapping it again closes the card,
  which is how it is dismissed besides its own ✓/✕.
  While the card is open the row MIRRORS THE DRAFT: the name being typed and the
  star being flipped show in the row as they change. Showing the stored values
  there instead made the pair read as two different tasks — the row said one
  name while the field said another. An emptied field falls back to the stored
  name rather than blanking the row.
- **A task's history, under its open card** (Anton, 2026-08-28). Tracking
  already recorded every stretch of time as an interval; the card now SHOWS
  them, newest first, with the task's total above. Each line can be edited
  (tap the row), deleted (hover ✕), and a session that was never tracked can be
  added by hand ("add time").
  - **A line's editor holds both halves of it**: WHEN it started — day, month,
    year, hour and minute, each a small bordered MENU, the three date parts in
    the order this locale writes them (`TrackerMoment.order`, tested) — and HOW
    LONG it ran, in a field showing `0:00:00` as its placeholder rather than
    sitting empty. **A duration is always written and read in full**
    (`DurationField`, tested): `h:mm:ss`, hours uncapped — "11:00" for eleven
    hours flat read as eleven MINUTES just as easily (Anton, 2026-08-28). Parts
    are counted from the right, so a lone number is seconds, and over-large
    parts simply add up (90:00 is an hour and a half) rather than being
    refused. Both halves are filled in before it opens: from the line for
    an edit, from the clock on the wall for a new one, so "add time" says what
    it is logging against.
  - **Each part opens a SHORT scrolling list UNDER the editor**, in the flow —
    not a system menu and not a popover (Anton, 2026-08-28). A menu grows to fit
    its items, so sixty minutes became a column down the whole screen; a popover
    brings macOS's own large corner radius, which sat oddly against the panel's
    4–6pt corners. The list is 132pt tall, scrolls, highlights the current value
    and opens scrolled TO it — a decade of years starts where the year already
    is. One list at a time; the open chip carries the editing outline, picking
    closes it, and so does closing the editor.
  - **The date parts are lists, not typed numbers** (Anton, 2026-08-28). Typing
    left no way back out of a half-entered year, and a bare "08" said nothing
    about which month it was. Months are NAMED in the app's own language
    (`shortStandaloneMonthSymbols`), the day list offers only the days the
    chosen month has, and picking a shorter month or a non-leap year pulls the
    day down with it — pick the 31st in March, switch to February, and the
    choice follows to the 28th instead of quietly meaning something else. Years
    run a decade back and one ahead.
  - **A typed date is always a real one.** A day its month does not have is
    pulled to that month's last — 31 April is the 30th, and 29 February exists
    in 2028 but not in 2026 (`TrackerMoment.clampedDay`).
  - `addSession` starts the session at the given moment (now minus its length
    when none is given, i.e. work that has just finished), so it lands on the
    day it belongs to. Moving a line keeps its length; editing the length keeps
    its start. An adjustment moves to that day's midnight, the only precision a
    correction has.
  - **A session keeps its START and moves its end** when edited. The moment work
    began is a fact; its length is what gets misremembered.
  - **The RUNNING session refuses to be edited** — its end is the clock's to
    write. Deleting it stops the clock, since an open interval with nothing on
    screen is worse than either.
  - **Adjustments are in the list too**, labelled and dated, negative ones with
    a minus. They are what the scrub and the typed total write, and together
    with the sessions they ARE the total — a list that quietly omitted them
    would not add up to the number above it.
  - **The list scrolls, cut THROUGH a line** (Anton, 2026-08-29). A long-lived
    task holds hundreds of sessions, so the block is a window seven lines tall
    plus half of the eighth: `(20 + 2) × 7 + 10 = 164pt` against a line's 16pt
    of content, its 2pt of padding each side and the list's own 2pt gap. Ending
    on a whole line read as the end of the list, and the earlier "+N" beneath it
    was a count rather than a way in. Under eight lines nothing scrolls, and the
    cap is LIFTED while a line is being edited — the editor's own date list is
    taller than the window.
  - **The total is the block's headline**, not another line of it: 13pt semibold
    in primary ink against a 9pt tertiary label, sharing a baseline, with room
    under the pair (Anton, 2026-08-28 — at matching sizes he read the label as a
    button and the figure as a row).
  - **Deleting a line asks first**, the same two-step the rows use: the hover ✕
    swaps the line for a delete/cancel pair, and only that deletes (Anton,
    2026-08-28). The ✕ here is 16pt rather than the row's 22 — a history line is
    shorter than a task row, and the full-size button grew the line the moment
    the pointer arrived. The line is pinned to that height, so nothing under it
    shifts as the pointer crosses the list.
  - The edit field sits FLUSH RIGHT, on the column the durations line up in,
    with the same filled background the row's own total edit uses: floating a
    bare cursor beside a ✓/✕ pair read as two icons and no field at all (Anton,
    2026-08-28).
  - `TrackerInterval` and `TrackerCorrection` therefore carry an `id`. A file
    written before they did gets fresh ones on load (tolerant decode); they are
    stable from the first save after that, which is all editing needs.
- **Deleting a project deletes its tasks and their history** (Anton,
  2026-08-28). The confirm keeps the row's silhouette and puts a list glyph with
  the task count next to the delete/cancel pair — a count of tasks would need a
  plural form in 22 languages and the glyph needs none. Deleting the project of
  the running task stops the clock, the same way deleting that task alone does.
- **Dragging with two levels** (`TrackerDrop`, pure and tested): a drop is a
  parent AND an index now, and the two cannot be decided separately — the same
  pointer height means "last in this project" or "first after it" depending on
  what sits above it. A project only ever lands at the top level and travels
  with its own tasks (they are excluded from the landmarks). **A task dropped ON
  a project's own row goes INSIDE it, at the top** — the only way into a FOLDED
  project, since none of it is on screen to aim between, and the same gesture
  works when it is open, so there is one rule rather than two (Anton,
  2026-08-28); the drop maths is given each row's measured height for it.
  Otherwise a task takes the
  level of the row above the pointer: inside a project when that row is one of
  its tasks or its unfolded header, otherwise at the top level — so a task
  leaves a project by being dropped above it, or below a row that belongs to
  nobody, a folded project included. "Important on top" clamps the index within
  the destination's own siblings, exactly as it did on the flat list.
- **What a 1.3.x file does now:** nothing special. Its projects and nested tasks
  load as what they always were — the flatten migration is gone. A file from the
  flat years has no projects and needs no conversion either. Both decode
  tolerantly: `taskOrder` and `rootOrder` default to empty and are derived, so a
  file written before either key existed is not rejected over it.
- **Single active task:** at most one task is ever tracking. Tapping play on
  task B while A runs stops A first — the engine closes the open interval itself
  (`start(taskID:)`), the UI never juggles two. Deleting the active task stops
  tracking (its open interval is dropped with it). `activeIntervalStart` exposes
  the open interval's start so the view can flag a long run (see 8-hour warning).
- **A run, and the ✓ that ends it** (Anton, 2026-08-29). Pause used to be the
  only way out of a stretch of work, and nothing on screen said what had been
  recorded or when: the row went on showing the period's sum, so it never came
  back to zero and the next play simply continued the same number. Play now
  opens a RUN — `TrackerInterval.committed` is false while an interval belongs
  to one, `currentRun(taskID:)` is what those intervals add up to, and the row
  shows THAT figure, counting from zero, in primary ink.
  - **Pause holds a run; the ✓ ends it.** play → pause → play is ONE run made of
    several intervals. `commitRun(taskID:)` stops the clock if it was this
    task's and files every interval of the run, after which the row goes back to
    the period's figure and the next play counts from zero again.
  - **Committing moves no figure.** A run's time is inside `today`/`week`/`total`
    from its first second — the ✓ decides only WHICH number the row shows, never
    how much time exists. That is why a project's sum is unaffected by whether
    its tasks are mid-run.
  - **A run owns the figure while it is open**: no tap-to-type and no scrub
    (`hasOpenRun` gates both), because typing over the run would silently mean
    the period's sum. Correcting a paused run's stretches is what the card's
    history is for.
  - **The ✓ is always visible while a run is open** (`RunCommitButton`,
    accent-green checkmark in the row's own 22pt button box) — it is also the
    row's only sign that a run IS open. It sits to the RIGHT of the hover ✕, so
    a pointer arriving on the row inserts the ✕ beside it instead of sliding the
    ✓ out from under the cursor.
  - In the card's history, the run's own lines are drawn in primary ink until
    the ✓ files them (`TrackerHistoryEntry.isOpenRun`).
  - `end == nil ⟹ committed == false`, repaired on load: a file written before
    runs existed decodes every interval as filed, and an open one would leave a
    ticking row with no ✓ to close it. A hand-added session (`addSession`) is
    filed on arrival — it is work already finished, never part of a run.
  - The agent bridge's `tracker.stop` stops AND commits: an agent has no ✓ to
    press afterwards, and a run left open would keep the row counting it forever.
- **Menu-bar indication:** while a task is tracking, a dark-green wedge sits in
  the icon's bottom-right corner (see "Menu bar icon — corner badges"), next to
  the engine's green wedge when both run. It is suppressed only when the task's
  own `today` value is spelled out as digits in the title (the opt-in below);
  otherwise it shows whether or not a timer is also running. It lives on the
  FIXED 22×17 icon canvas, so tracking has ZERO effect on the status-item width
  and cannot shift the attached panel (this replaced an earlier in-title glyph
  that widened the button — Anton, 2026-07-20). Tracking is a decoration, so it
  drops out of the plain-template fast path and the icon goes through `compose`.
  An opt-in `show task time in menu bar` setting (`trackerTimeInBar`, OFF —
  on the time tracker's own settings page, NOT the timer's: the two clocks
  are independent and either can hold the bar alone, so a switch placed in the
  timer's section read as belonging to the timer, Anton 2026-08-05; same rule as
  the VPN mark, which lives with the VPN settings)
  additionally shows the active task's ticking `today` value as the bar title;
  when those digits show, the dark-green wedge is dropped (the digits are its
  redundant twin). **When a countdown is running too, the two SHARE the title**
  (`MenuBarCycle`, Anton 2026-08-04): each holds it for 5 seconds and hands over
  through a half-second fade to nothing and back, and while they take turns each
  reading carries a glyph of its own in front of the digits (`timer` /
  `stopwatch` for the engine, `record.circle` for the tracked task) — two numbers
  in one slot are ambiguous without one. A single reading is drawn exactly as
  before, digits only and no glyph. Whose turn it is and how far through a
  handover the label is are both computed from the clock, never stored, so a
  redraw arriving late or twice cannot desynchronise the rotation. The label
  otherwise redraws once a second off the heartbeat, which is too coarse for a
  fade, so a 0.05 s ticker is spun up for the length of one handover and
  invalidated as soon as the digits are legible again. Across a handover the
  title's colour is set explicitly (white or black by the BAR's appearance, at
  the fading opacity); at rest it is left to AppKit, which inverts the title
  itself when the status item is highlighted. `today(taskID:)` stays in the engine for
  this figure and for corrections math; the panel shows whichever period its
  own switch is on. The wedge toggles immediately on start/stop off `tracker.heartbeat`; the
  opt-in bar time ticks 1/s. The wedge never touches the title, so it plays no
  part in the width-freeze — only the `trackerTimeInBar` digits (a deliberate,
  opt-in width change of the same class as the countdown) ever change the title
  width. A task left running past 8h also raises the blinking top-left "!".
- **Flat rows** (no card fills — TorrentView-style): regular weight everywhere;
  the ACTIVE task is emphasized by COLOR only (its total label
  `Theme.textPrimary`). Rows sit FLUSH LEFT — there is no reserved drag-handle
  gutter; the play/stop button is the leading element at the 2pt row inset,
  LEFT-ALIGNED (not centered) in a shared 22pt gutter (`RowCircle.gutter`) so its
  visible edge sits exactly on the row inset line — the same line the
  `time tracker` subheader and the `+ new task` footer text start on — and lines
  up with the to-do checkbox on the same left column when the two modules stack
  on a space. The play/stop circle and the checkbox are ONE control at ONE
  visible diameter (`RowCircle.diameter`, 18pt — between the old transport 22 and
  checkbox ~13), both drawn by the shared `TransportCircle`. Delete xmarks are
  hover-only (`HoverDeleteX`); in the tracker one is inserted IN FLOW right
  before the total time, only while the row is hovered, eating into the row's
  flexible spacer instead of overlaying the time — the row's normal 6pt HStack
  spacing separates it from the time on one side and the spacer on the other, so
  the time never moves, is never covered, and a non-hovered row reserves no
  width at all. Vertical rhythm matches the to-dos list verbatim (VStack
  spacing 3, `.padding(.vertical, 2)`); the 8-hour warning row and the inline
  new-task field carry the same tight padding.
- **Subheader:** a compact `time tracker` sublabel sits above the list at all
  times (mono 10 semibold, `Theme.textTertiary`, lowercase — the settings
  section-header treatment), so the tracker and to-do lists are distinguishable
  at a glance when the two modules stack on one space.
- **Task row:** a play/PAUSE button in the main timer's transport family
  (`TransportCircle`: the house rounded-corner play triangle (`PlayGlyph` — see
  "Play glyph" under shared components; not SF's sharp `play.fill`) filled when
  idle = "start"; `pause.fill`
  bordered when this task is active), the name, then ONE time — the all-time
  TOTAL (mono 11, `TimeFormatting.short`, ticking while active) — and the hover
  xmark. Clicking the xmark switches the row into an IN-ROW delete confirm rather
  than deleting on the spot: the play/stop circle, the name AND the far-right time
  all stay exactly where they are — only the hover ✕ gives way to two labelled
  buttons rendered just left of the (now inert) time. `cancel` (tertiary) takes
  the ✕'s EXACT slot (6pt left of the time, the ✕'s own gap), and `delete`
  (destructive `Theme.accentRed`, the torrent confirm's token) sits 12pt further
  LEFT — so a reflexive repeat click at the ✕ point lands on cancel, never delete
  (`RowDeleteConfirm`, shared with to-dos, whose ✕ was already rightmost so cancel
  sits flush-right there). The time label is INERT while confirming (no
  tap-to-edit / scrub until the confirm resolves). There is no question line — the
  two labelled buttons are the whole prompt. Escape cancels (`.cancelAction`);
  starting a row drag or closing the panel clears the confirm
  (`clearConfirms`/`onDisappear`); the row height and silhouette are unchanged in
  confirm mode. The today/Σ pair from earlier versions is gone: the row shows the
  total only. The active task's total label uses `Theme.textPrimary`.
- **Editing the total** (only while the task is NOT active — the engine refuses
  otherwise and the UI hides the affordance): the manual edit targets the TOTAL.
  `setTotal(taskID:to:)` appends a correction = target − rawTotal (the UNCLAMPED
  total — mirroring `setToday`'s raw-baseline lesson, so an over-corrected task
  can still reach a positive target in one edit), dated the start of today,
  clamped ≥ 0, refused while active, `onChange` once. Scrub the total label
  (horizontal drag, 8pt = ±1 min, a scrub tick per step) with a live local
  preview committed as ONE correction on gesture end (a no-op drag back to origin
  writes nothing); or click the label to type into an inline field that reads
  `H:MM:SS`, `H:MM` or bare minutes — 1 number = minutes, 2 = `H:MM`, 3 =
  `H:MM:SS`, parsed leniently. `.help` carries the hint. `setToday(taskID:to:)`
  remains for the menu-bar path and is unaffected.
- **Mutator guards (engine invariants):** every id-taking mutator no-ops on an
  UNKNOWN task id rather than recording inconsistent state — `start(taskID:)`
  opens no orphan interval, and `setToday`/`setTotal` return false and add no
  orphan correction. A ZERO-DELTA edit (the total/today already equals the
  target) writes no correction and fires no `onChange`, so re-setting a value —
  including dragging left while already at zero — never leaves an empty record
  or triggers a redundant save.
- **8-hour warning:** when the ACTIVE task's current open interval has been
  running for over 8 hours (`activeIntervalStart` vs now, recomputed off
  `tracker.heartbeat` — no timer of its own, no repeatForever), a warning row
  appears directly under that task: `t(.trackerLongRun)` (en: `still tracking —
  over 8 hours. forgot to stop?`, `Theme.accentYellow`) with a small stop button
  that calls `stopActive()`. The row appears and disappears off the heartbeat. No
  system notification in this pass (a possible follow-up). Normally it sits inline
  under its task; when the task list is capped and scrolls (see 8.21) it is PINNED
  directly below the scrolling list instead, so the "forgot to stop?" alert is
  never scrolled out of view.
- **8-hour overrun banner (panel-wide):** the same 8-hour crossing also raises a
  dismissable banner ABOVE the space tabs, on the same chrome surface as the
  "what's new" banner (`overrunBanner`, `Theme.rowBg` card, rounded, an
  `accentYellow` warning glyph + hairline stroke). Copy `t(.trackerOverrunBanner)`
  ("a task timer has been running for over 8 hours" direction, house lowercase,
  ×18) with ONE button, `t(.trackerOverrunDismiss)` ("ok", ×18), that only
  dismisses — the user navigates to the tracker themselves. The episode logic is
  pure in `HopCore.TrackerOverrun` (`TrackerOverrunTests`): visibility keys off
  the open interval's START; dismissing records that start
  (`trackerOverrunAckStart`, a `timeIntervalSinceReferenceDate` Double persisted
  like other banner dismissals) so the banner stays gone for the rest of that
  continuous run, and stopping then starting again — a NEW start — makes the next
  8-hour crossing a fresh episode the stale ack can't suppress. Recomputed off
  `tracker.heartbeat` (no timer of its own); stopping the task removes it (no
  active start). The in-module long-run warning row above is unchanged and
  independent. The menu-bar alert icon is deliberately NOT part of this — it
  ships with the corner-system redesign.
- **Visible rows (8.21):** a per-module `visible rows` cap
  (`trackerVisibleRows`, the tracker's settings page): an ALWAYS-active number 3…15,
  default 10 (`VisibleRowsField`, a single numeric field — the "all"/unlimited
  option was dropped; a stored 0 from the old "all" default reads as 10 on load,
  no migration). When the TASK count exceeds
  the cap, the task list scrolls inside a fixed height of exactly `cap` rows plus
  their inter-row gaps — `29·cap − 3` (26pt row + 3pt spacing, the last gap
  dropped) (`RowCap.listHeight`, INTEGRAL); the subheader, the pinned 8h warning and the
  `+ new task` add row stay OUTSIDE the scroll. While scrolling, the whole-row
  reorder drag stands down (`including: .subviews`) so the pan scrolls, while the
  horizontal total-scrub and the play/stop taps keep working. Snapshots never
  scroll. Shares `RowCap` + `VisibleRowsField` with the to-do module.
- **Drag to reorder:** grabbing ANYWHERE on a row moves it (see "Dragging with
  two levels" above for where it lands) — the
  reorder gesture lives on the row container (`minimumDistance` 3), not a handle.
  It DISAMBIGUATES BY AXIS against the total label's horizontal scrub: on the
  first move past the threshold, a vertically dominant drag (`|dy| > |dx|`) lifts
  the row, while a horizontally dominant one stands down (latched for the rest of
  the gesture) and falls through to the scrub; the scrub mirrors the test (it
  engages only when `|dx| > |dy|`). The two gestures sample at different
  `minimumDistance`s (reorder 3, scrub 4), so the axis test alone is not enough —
  a drag that lifts the row vertically then curves horizontal could otherwise
  scrub on top of the reorder; the scrub's engage branch therefore also refuses
  once a reorder already owns the drag (`guard dragTask == nil`), which is what
  guarantees the two never fire together. Inner controls
  keep their taps — a tap never crosses `minimumDistance`, so the play/stop
  button, the hover xmark and the ✓/✕ field buttons win by SwiftUI's inner-gesture
  precedence. On macOS a click-drag never fights the panel's wheel/trackpad
  scroll. Drop resolution uses a frame-preference resolver (the 8.2 settings-table
  pattern): every row reports its frame in the `trackerList` coordinate space, and
  the pointer's y counts how many other rows sit above it. The dragged row dims
  and follows the pointer; a 2pt accent line marks the insertion point. One
  `moveRootItem(from:to:)` commits per completed drag.
- **Adding / renaming:** a single `+ new task` footer row swaps into an inline
  TextField (lowercase placeholder = the label), committed on Return (empty =
  cancel), Escape cancels. Double-clicking a name opens the same inline field to
  rename. Every inline field (new/rename/total-edit) shows explicit ✓ (commit) /
  ✕ (cancel) buttons right of it (`FieldCommitButtons`, house hover style) — the
  mouse equivalent of Return/Escape.
- **Empty state:** with the always-on subheader naming the module, an empty list
  shows ONLY the subheader and the `+ new task` add row — no placeholder line.
  Adding the first task or deleting the last never shifts the subheader or the
  add row (both keep their heights); the list simply grows or shrinks by one row.
- **Snapshot rule:** every focused-field state is gated off `Snapshot.active`,
  so `--snapshot` renders never show an editing TextField (yellow artifact).
  The tracker AND to-do LOAD paths are gated on `Snapshot.active` too: a
  snapshot/demo render starts from empty and never reads the real
  `tracker.json`/`todos.json` (belt-and-suspenders over the bundle-less `.cli`
  sandbox), so `--tasks` stages its own deterministic content — three tasks (one
  running), three to-dos (one done) — localized per screenshot locale in
  `Snapshot.demoTasks` (a sanctioned per-locale string site covering all 22
  locales — English via the `default` case).

### To-dos

- A flat checklist. Logic lives in HopCore (`TodoList` + `TodosStore`,
  `todos.json`, atomic write, tolerant decode of a missing `items` key);
  `TodosController` mirrors `TrackerController` minus the ticker (a checklist
  has nothing that ticks). Both stores (`TodosStore`, `TrackerStore`) move an
  unusable file aside to `.bak` before the next save can overwrite it — not
  only a file that fails to DECODE (corrupt), but one that EXISTS yet cannot be
  READ (permissions, transient IO, not a regular file); a missing file is the
  normal first-run case and is left alone. A save or backup failure logs ONE
  line (no per-mutation spam). Model API: `add(text:)` trims and
  APPENDS at the bottom (empty = no-op), `toggle(id)` flips `done` IN PLACE
  (completed items keep their position), `delete(id)`, and `move(from:to:)`
  reorders (clamped; `from` out of range is a no-op) — the order persists through
  the store. `TodosController.reorder(dragging:toDisplayInsertion:)` saves like
  every other mutation.
- **Completed items sink to the bottom (8.20):** the list DISPLAYS as active
  items (in stored order) first, then completed items (in stored order) —
  `TodoDisplay.order` (pure HopCore, tested). Completing an item animates it DOWN
  into the completed pile; the STORED order is NOT mutated by toggling, so
  unchecking animates it back to its original slot among the active items for
  free. The sink/return is a finite `withAnimation` on toggle (`.easeInOut` 0.22,
  no repeatForever). Drag reorder is CONSTRAINED to a group: an active item can't
  be dragged below the first completed one and a completed item can't rise above
  the last active one — `TodoDisplay.clampedInsertion` clamps the insertion (the
  indicator line stops at the boundary) and `TodoDisplay.reordered` translates the
  display-order drop back to a MINIMAL stored move so every untouched item keeps
  its stored slot (only the dragged item relocates). Reordering completed items
  among themselves is allowed, clamped within the completed group. All of it —
  order, clamp, minimal-move, the toggle/uncheck slot invariant, and the all-done
  / all-active edges — is covered by `TodoDisplayTests`.
- **Row:** a circle checkbox — the shared `TransportCircle` in muted tokens (an
  empty ring when open, a filled `Theme.textTertiary` disc with a knocked-out
  check when done) — the text (mono 12; done = `Theme.textTertiary` +
  strikethrough), and a hover-only xmark. Clicking the xmark switches the row
  into the SAME in-row delete confirm as the tracker (`RowDeleteConfirm`: `delete`
  on the left, `cancel` rightmost in the ✕'s slot, ~12pt gap, Escape cancels via
  `.cancelAction`); the checkbox and text stay put and only the ✕ swaps for the
  two buttons, so the row keeps its silhouette and height. Starting a drag,
  opening the add field, or closing the panel clears the confirm
  (`clearConfirms`); a new confirm on another row closes the previous one (single
  `confirmingDelete`). It works for done and active items alike. Rows sit
  FLUSH LEFT (no handle gutter): the checkbox is the leading element at the 2pt
  row inset, LEFT-ALIGNED (not centered) in the 22pt `RowCircle.gutter` — its
  visible edge sits exactly on the row inset line, the same line the `to-dos`
  subheader and the `+ new task` footer text start on — the same control family as
  the tracker's play/stop, so the two line up on the same left column when the
  modules stack on a space. The hover xmark
  (`HoverDeleteX`) is inserted IN FLOW right after the row's flexible spacer,
  only while hovered, same mechanism as the tracker: no reserved width on a
  non-hovered row, and a long already-truncated todo text yields room to the
  xmark on hover instead of running under it. The checklist rhythm (VStack
  spacing 3, `.padding(.vertical, 2)`) is shared verbatim with the tracker — the
  two near-twin modules read identically; the 8-hour warning and inline-edit
  rows adopt the same tight vertical padding.
- **Subheader:** a compact `to-dos` sublabel (`todosLabel`) sits above the list
  at all times, same treatment as the tracker's; an empty list shows ONLY the
  subheader and the `+ new task` add row — no placeholder line — and adding the
  first item or deleting the last never shifts either.
- **Drag to reorder:** grabbing ANYWHERE on a row reorders — the same whole-row,
  container-level gesture as the tracker (`minimumDistance` 3, engaging only on a
  vertically dominant drag) and the same frame-preference resolver (rows report
  their frame in the `todosList` coordinate space; the pointer's y counts the
  other rows above it, in DISPLAY order). The checkbox and hover xmark keep their
  taps by inner-gesture precedence. The dragged row dims and follows the pointer;
  a 2pt accent line marks the (group-clamped) insertion point; one
  `reorder(dragging:toDisplayInsertion:)` commits per completed drag.
- **Visible rows (8.21):** a per-module `visible rows` cap
  (`todosVisibleRows`, the to-do settings page): an ALWAYS-active number 3…15,
  default 10 (`VisibleRowsField`, the clipboard's `NumericField` alone — the
  "all"/unlimited option was dropped; a stored 0 from the old default reads as 10
  on load). When the COMBINED
  displayed list (active + completed scroll together) exceeds the cap, the item
  list scrolls inside a fixed height of exactly `cap` rows plus their gaps —
  `29·cap − 3` (26pt row + 3pt spacing) (`RowCap.listHeight`,
  INTEGRAL — no fractional-height header jump); the subheader and the `+ new task`
  add row stay OUTSIDE the scroll (always visible). Scroll indicators are hidden,
  matching the clipboard. While the list scrolls the whole-row reorder drag stands
  down (`including: .subviews`) so the pan drives the scroll — reorder is for the
  short, fully-visible list. Snapshots never scroll (flat render). `RowCap` +
  `RowCapTests` hold the cap/height math.
- **Adding:** a `+ new task` footer row (placeholder `todosNew`, "new task")
  opens an inline field with the same ✓/✕ buttons and `Snapshot.active` gating as
  the tracker; Return/✓ append, Escape/✕ cancel, empty = cancel.
- **Task card (expanded row):** clicking a row expands it into a card and
  collapses whatever was open — ONE card at a time, so the panel cannot grow
  without bound. The card is shaped like a note rather than a form: the task text
  is simply the first line (no caption — a line at the top of a card is its
  title), a hairline separates it from a `description` field below, and BOTH are
  `TextEditor`s rather than `TextField`s — a macOS field treats Return as submit
  no matter what, so the text refused to wrap. Return therefore adds a line, ✓ or
  ⌘Return commits, Escape abandons.
  Beneath them, the reminder group sits on the LEFT (bell, day chip, time, and
  the weekday row under it, captioned `repeat` in words — a glyph there read as
  one more button) and the favourite star on the RIGHT, next to ✓/✕: between the
  bell and the day chip the star looked like part of the reminder.
  Once a reminder exists it shows its day chip and `HH:MM` fields
  (`NumericField` with `padTo: 2`, so a clock reads `22:00` rather than `22:0`;
  the field carries NO focus offset — the old ~1.5pt compensation for AppKit's
  field-editor lift now IS the jump). The day menu reaches a month out. An earlier cut labelled every line
  (`task`, `note`, `remind`, `important`) and paired the star with a toggle; it
  was rejected as too much furniture for one decision and because plain labels
  next to tappable text were indistinguishable (Anton, 2026-07-28). Opening a
  card closes any pending delete confirm and the add field; starting a reorder
  drag collapses it (its fields own the pointer); closing the panel collapses it.
  In a capped list the card lives INSIDE the scroll — the list keeps its
  `29·cap − 3` height. The tracker gets the same card minus the reminder rows,
  and its double-click-to-rename now opens the card instead of a separate inline
  field: ONE editing route.
- **Comment:** `TodoItem.note` (and `TrackerTask.note`), free text. A collapsed
  row with a non-empty note shows a small `text.alignleft` glyph after the
  spacer — the only hint that there is something inside. Inert: the row itself
  opens the card.
- **Favourites:** `important` on both models. The card's star sets it; the
  collapsed row shows the same star. It is the house `StarGlyph`, not SF's
  needle-sharp `star.fill`, and its rounded outline is baked into ONE path —
  filling and stroking separately made a translucent token pile up along the rim
  and read as a glow. A coloured frame was tried
  first and rejected — it read as a warning rather than "this one matters"
  (Anton, 2026-07-28). Per-module `important tasks on top` settings
  (`todoImportantOnTop` OFF; `trackerImportantOnTop` **ON since 2026-08-28** —
  a star that moved nothing was a mark with no consequence, and everyone who
  used one expected it to lift the task) turn the mark into a
  DISPLAY sort: important actives first, then ordinary actives, then the
  completed pile. In the tracker a star lifts a task WITHIN ITS OWN LIST — the
  top level for a loose task, its own project for one inside — and projects
  never move for it (`TrackerDisplay.order(topLevel:)`). Display-only, exactly like the completed sink — the stored
  order is never mutated, so unmarking returns an item to its slot and switching
  the setting off restores the hand-built order. Drag is clamped to the dragged
  item's group (`TodoDisplay` over three groups, `TrackerDisplay` over two).
- **Reminders (to-dos only):** `remindAt`, `repeatDays` (arbitrary weekdays, 1 =
  Sunday), `snoozedUntil`, `firedAt`, `firedUnseen` — every one decoded
  leniently, so a `todos.json` from before the feature loads untouched. The
  tracker has none: its time already means "how long I worked". All arithmetic is
  pure in `HopCore.RemindSchedule` (`RemindScheduleTests`): the next firing for a
  weekday set, DST gaps via `matchingPolicy: .nextTime`, and `reconcile`, which
  fires a past one-shot EXACTLY once (`firedAt` older than `remindAt` is the
  test) and collapses a week of missed repeats into ONE unseen firing. A firing
  rolls a repeating task forward and UN-TICKS it — a task that repeats is not
  finished because last week's instance was ticked.
- **Firing:** three independent settings, all ON (`todoRemindBanner`,
  `todoRemindSound`, `todoRemindMark`). The banner is a `UNCalendarNotificationTrigger`
  with two actions, `snooze` (+10 min) and `done`; ONE pending request per item,
  always for its next firing only, so a weekday repeat costs one slot rather than
  seven and 60 items fit under the system's 64-request ceiling (a drop past the
  cap is logged, never silent). The banner is SILENT (`content.sound = nil`) and
  the alert sound is played by the app's own 15s reconcile tick instead, so sound
  works with banners off and can never double up. The tick, plus a wake observer
  and a recompute on panel open, is what makes a reminder land at all when
  notifications are switched off.
- **After a firing:** the row's time stays visible and STRUCK THROUGH once it is
  in the past (a repeating task never shows one — it has already rolled forward),
  and on the next panel open the row blinks three times (finite, no
  `repeatForever`) before `firedUnseen` clears. So a banner that went unseen
  still leaves a trace in the list.
- **Week start:** the weekday squares run in the user's own week order —
  `firstWeekday` (`auto` follows the system region, or Sunday/Monday explicitly),
  since the US counts a week from Sunday and most of Europe from Monday and
  people move without changing habits.
- Registration is by membership like every module (key `"todos"`, title
  `todosLabel`); it captures the keyboard while its field is focused (same
  `onEditingChanged` path as the tracker) so digits don't leak to the timer.
  Fresh installs pair it with the tracker on the "clock" space; existing
  users get it paired with the tracker on the same space by the canonical
  layout repair described under "Default spaces" below.

- **The checkbox is drawn 2pt SMALLER than the tracker's play/stop** (`RowCircle.checkboxDiameter` 16 against `diameter` 18): a RING reads bigger than a disc of the same size, and at equal diameters it looked like a different control (Anton, 2026-07-28). The ring is a `strokeBorder`, not a `stroke`, for the same reason — a centred stroke straddles the path and grows the circle by its own 1.5pt.

### VPN

- Every VPN macOS knows about — a client's own configuration, a corporate IKEv2
  profile, a WireGuard tunnel — with a switch per row. Read and driven through
  `scutil --nc` (list / start / stop), the same door the system's own menu-bar
  switch uses. NOT `NEVPNManager`: it only sees configurations the calling app
  created itself, and reaching another app's tunnel needs an entitlement that
  comes with a paid developer account.
- **Nothing is added by hand.** The list IS the system's list: install a client
  and its configuration appears, remove it and the row goes. There is no "add"
  button in Hop and there should never be one. A second server shows up as a
  second row only if the vendor's app creates a second CONFIGURATION for it —
  macOS's own `+` can only make L2TP, Cisco IPSec and IKEv2, so it cannot add a
  server to a client that speaks its own protocol.
- **The row** is the app's name, then in brackets whatever the configuration adds
  beyond it — a country, a profile. Repeats of the app's own name are stripped,
  and so are protocol words (`OpenVPN`, `IKEv2`, `WireGuard`…): a protocol tells
  the user nothing they can act on. So `hidemy.name VPN` shows nothing in
  brackets, while a configuration named after its country shows `Client (Germany)`.
  No indicator light in the row — the switch already says on or off.
- **Off stays off.** A configuration with on-demand rules is back within seconds
  of being stopped: the rules reconnect it the moment anything asks for a `.com`,
  which is how they are meant to work and why Hop's switch looked broken (Anton,
  2026-07-30). So switching a row off does two things — `scutil --nc stop`, and,
  only when `scutil --nc show` reports `OnDemandEnabled : TRUE`, it also takes
  the service out of the network set (`networksetup -setnetworkserviceenabled …
  off`). A service that is not in the set cannot be started by a rule. Switching
  the row back on puts it in the set first and then starts it, and so does
  opening the vendor's own window: a client that could not connect from its own
  screen would look broken, with Hop as the reason. The list still shows a
  held-off configuration — `scutil` prints it without its `*` and calls it
  `Invalid`, which is read as off rather than as a fault. Configurations without
  on-demand rules are only stopped; nothing is taken out of the set that did not
  need to be.

  It needs no per-vendor support and no per-configuration setting: `OnDemandEnabled`
  is a property of a NetworkExtension CONFIGURATION, not of a client, so the same
  read and the same lever work for every VPN on every Mac — what differs is only
  whether a given configuration has rules at all (Anton asked whether this could be
  unified, 2026-07-30). One switch covers the module: **"keep it off until i switch
  it on"** (`vpnHoldOff`, VPN settings, ON by default). Turned off, Hop only stops
  the tunnel and leaves the network set alone — for someone who WANTS on-demand to
  bring it back, or whose configuration is managed by an employer.
- **The country is NEVER guessed from the server's address** (settled 2026-07-29
  after trying it). The system knows the address and nothing else: no hostname,
  no reverse DNS. Asking the address registry does return a country — but it is
  the country the RANGE IS REGISTERED IN, and on the very first live test it said
  Germany for a server the user had set to the Netherlands. A wrong country
  stated confidently is worse than no country, and the alternatives cost more
  than they are worth: a geolocation service would be the first request Hop ever
  makes to a third party, and an offline database would nearly double a 3.7 MB
  app. Only what the vendor itself names is shown.
- **Menu-bar light:** a dot in the bottom-left corner while any tunnel is
  up — GREEN while traffic is going through it, ORANGE while one is carrying
  nothing (see the next bullet) — beside the torrent arrows when those are there,
  the state worth seeing with the panel closed, the exact mirror of the awake dot
  in the opposite corner. When the torrent arrows share that corner THEY keep it,
  nudged 0.6pt further left, and the dot steps to their right: moving the arrows
  inward instead put them under the star's rays, where they stop reading as
  arrows. One value (`VPNMark`), not two flags, so "up AND stalled" cannot be
  expressed; in monochrome the stalled one becomes a ring at the same outer size,
  since there is no colour left to carry the difference.
  It can be switched off (`vpnMenuBarMark`, VPN settings,
  ON by default — the label is about the STATUS, not about a green dot, since the
  dot has had two colours since 2026-07-31); the module and the switch go on
  working without it. HIDING the
  module takes the dot with it — the badge is the module's voice in the menu bar,
  and a module that is on no space has nothing to say there (Anton, 2026-07-29).
  Hiding does not touch the setting, so putting the module back on a space brings
  the dot back too.
- **A tunnel that is up and carrying nothing.** `scutil` reports the state of the
  SESSION, not of the traffic: a tunnel whose server has gone quiet stays
  `Connected` while nothing comes back through it — the switch is green and the
  internet is dead (Anton, 2026-07-31). The evidence is the tunnel interface's own
  counters. `scutil --nc status <id>` names the interface
  (`InterfaceName : utun4`, cached while the tunnel stays up since looking it up
  costs a process launch), and `getifaddrs` reads its counters — NOT a command:
  this runs every two seconds for as long as a tunnel is up, and launching a
  process on that cadence to learn two numbers would cost more than the rest of
  the module put together.

  **PACKETS, not bytes.** Measured against `netstat -ibn` on 2026-07-31: the
  packet counters `getifaddrs` reports agree to the unit, while its BYTE counters
  are rounded down to a multiple of 1024 and lag behind. On a quiet but healthy
  tunnel that rounding can swallow a whole exchange, which would read as a tunnel
  bringing nothing back — the one mistake this module must not make. A single
  packet is unambiguous. Do not "improve" this back to bytes.

  The verdict (`TunnelLiveness`, HopCore, pure and fully tested): stalled when
  nothing has come back for **6 seconds** AND at least **3 packets** went out
  during that silence. Both halves are load-bearing. Without the silence a
  connection that drops and returns — how a flaky link behaves all day — would
  have the icon blinking between two colours; without the packet floor a Mac left
  alone at night, where nothing is asking for anything, would read exactly like a
  dead tunnel. So the verdict only ever appears when something wanted an answer
  and did not get one. Deliberately asymmetric: a single returning packet clears
  it on the sample that carries it, while making it takes those 6 seconds. A
  counter that goes BACKWARDS is an interface replaced under the same name (or the
  32-bit value wrapping) and re-baselines instead of accusing.

  Several tunnels can be up at once and ANY stalled one turns the light orange: a
  tunnel is only ever called stalled while something is actively pushing bytes
  into it and getting nothing back, which is broken whichever it is. Which one it
  is, the panel says — that row's switch takes the same orange (`MiniSwitch`
  already takes a tint, so no new element and no new string).

  Known limit, accepted: with no network at all, bytes still pile into the `utun`
  and nothing returns, so a Wi-Fi outage reads as a stalled tunnel for the few
  seconds before the system moves the session out of `Connected` itself. What is
  NOT detected — and cannot be, without asking a third party — is a live tunnel
  whose traffic flows while particular hosts stay unreachable.
- **The watch runs whether or not the panel is open.** It has to: the menu-bar dot
  is the whole point of the light, and until 2026-07-31 polling started on the
  list's `onAppear` and stopped on `onDisappear`, so with the panel closed the dot
  showed whatever was true when it last closed. Counters are sampled every tick
  and cost microseconds. The whole thing idles when nobody can see it — the module
  on no space, or `vpnMenuBarMark` off — which is exactly the pair of conditions
  the icon itself is drawn under.
- **The system says when the network moves; the timer is only the floor**
  (`NetworkChangeWatcher`, `VPNWatchCadence`, Anton 2026-08-30). Until then the
  list was re-read every **30 s** with the panel closed, and that was the whole
  latency of the dot: a tunnel brought up outside Hop — from the vendor's own
  window, or by its on-demand rules — took up to half a minute to turn the dot
  green, and one the system dropped took the same whenever its `utun` stayed
  standing behind it, since the free `getifaddrs` check only ever sees an
  interface leave.

  So the module now watches `SCDynamicStore` — the same subsystem `scutil` reads,
  taken from the other end. The keys are the SERVICE entities (`IPv4`, `IPv6`,
  `PPP`, `IPSec` under `State:`, any service) plus global `State:` IPv4 for the
  default route and global `Setup:` IPv4 for the service order, which is what
  moves when a service leaves the network set — including when Hop moves it.
  Services rather than interfaces, because publishing addresses against the
  service is the one thing true of every configuration whatever the vendor built
  it on, and because it is the only signal that survives a `utun` outliving its
  session. Read-only and unentitled: it asks the user for nothing. It is also
  cheaper than the poll it replaces, since a quiet network wakes nobody.

  A signal does not mean the tunnel has arrived — the route change is published
  first and the session then walks `Connecting → Connected` over a few seconds —
  so a signal opens an **8 s window at 1 s** during which the list is re-read
  every tick, and a further signal inside it restarts the window. Signals arriving
  together (a tunnel moves several keys at once, each its own callback) ride on
  one reading: another within **0.3 s** of the last does not order its own. The
  window is also what covers a client whose own state never lands under a watched
  key, since some neighbouring change reaches us and the window then reads until
  the truth shows up. Outside it, the old cadence stands unchanged: **2 s** with
  the panel open or a tunnel up, **30 s** otherwise, the list re-read every tick
  with the panel open, on a vanished interface, and on the 30 s floor. That floor
  is deliberate — a configuration the system announces under nothing at all
  degrades to the behaviour of 2026-07-31 rather than to no watch. Flipping a
  switch in Hop opens the window itself, without waiting to be told.

  `scutil` is run **off the main thread** from here on. It used to run inline on
  the main actor, which was survivable at one launch per tick and is not once a
  network change can order a reading; a reading in flight blocks another, unless
  it has been in flight 10 s and looks wedged, because a module that has stopped
  reading is worse than two readings at once.
- **The vendor's window on demand:** the app is not running at all while Hop
  drives the connection, so it sits in neither the Dock nor the menu bar.
  Clicking the name launches it, and Hop quits it again once its last ordinary
  window closes — three quiet ticks and never within two seconds of the window
  appearing, because a window blinks out of the window-server list during its own
  startup and the first cut killed the app right after it opened. The connection
  survives, since the tunnel is held by the system extension rather than the app.
- Opt-in module (key `"vpn"`, title `vpnLabel`), hidden on a fresh install like
  the eyedropper and recognition: a Mac with no VPN configured would otherwise
  get an empty section it never asked for.

### Apps (launcher)

- Grids of apps kept at hand: NINE across, up to eight rows (72 icons), 32pt
  icons with the name under each. Clicking an icon launches it. The model is
  `HopCore.AppShelf` / `AppShelves` with tests; the store is
  `app-shelves.json` beside the other module files.
- **The ICON is drawn larger than its cell, optically** (Anton, 2026-08-28). An
  app icon is a rounded tile inside a transparent square, so at exactly cell
  size its visible edge stands in from the module's line while every label sits
  on it. The image is drawn ≈9% bigger (capped at 4pt a side) inside a cell of
  the old size, which puts the TILE on the line and leaves the layout — and the
  names under it — untouched. Pulling the whole row out instead was tried first
  and pushed the names past the line the other way.
- **Several grids.** This is the ONE module that exists in copies, so its module
  key carries an id (`apps:<uuid>`) instead of a bare word. A key is matched to
  its shelf by that ID, never as text (`AppShelves.moduleKeys(for:in:)`):
  `moduleKey` writes an uppercase uuid, a key stored lowercase names the same
  shelf, and string equality deleted the shelf while leaving its chip behind as a
  ghost nobody could remove (fixed 2026-07-29). A key whose shelf is gone is an
  ORPHAN (`orphanedModuleKeys(in:)`) and the panel drops it on appear, so a ghost
  left by an older build clears itself. Settings lists the
  grids that exist — each with its name and how many apps it holds, and a ✕ that
  deletes it — plus the `+` that makes another and drops it on the first space.
  Deleting a grid calls `PanelTabsModel.remove(module:)`, which forgets the key
  rather than hiding it: hiding is for a module that still exists, and this one
  is gone.
- **A grid's own name.** Blank by default, in which case the header shows the
  generic `apps` label; typed in the header while editing. The name is also what
  the layout settings show for that grid's chip, so three grids on one space can
  be told apart.
- **The grid's name is typed in a FIELD that looks like one**: a rounded
  `fieldBg` box with a pencil in front of it and a placeholder that asks —
  "type a name", not "name". The first cut was a bare line of text with the noun
  as its placeholder, and it read as a column heading rather than something to
  click into (Anton, 2026-07-30).
- **Icons per row, 3...9, per grid** (`columns`, EIGHT by default — nine fit, but
  nine is the ceiling rather than the starting point, and a row one short of full
  can be widened as easily as narrowed; Anton, 2026-07-30). How many fit
  across and how big they are is the SAME question — the module is as wide as the
  panel either way — so the number is the setting and the size follows from it:
  nine are small, three are enormous (Anton, 2026-07-30). The control lives in
  the grid's EDIT mode, beside the name field and the reordering, because that is
  where everything belonging to this one grid is edited; the ends of the range
  grey out. The gap between icons stays 6.5pt at every width, and a grid holds
  eight rows of whatever its width is (eight across = 64, three across = 24). Narrowing a grid does
  NOT throw away the icons that no longer fit: they stay in the file and come
  back when it is widened again. A grid written before the setting existed loads
  at the default.
- **Names under the icons** can be switched off per grid (`showsLabels`, on by
  default), leaving bare icons for someone who recognises them by sight. The
  switch lives in SETTINGS, one row per grid, not in the module's header: as the
  word "names" it read as a second name field, and as a glyph it was an
  unexplained "Aa" (Anton, 2026-07-29 and 2026-07-30). A settings row has space
  for the whole label — "names under the icons". Both
  fields decode leniently, so a file written before they existed still loads.
  Those rows live in `AppShelvesSettingsView`, which OBSERVES the shelves
  controller: reading `model.appShelves` from the settings screen renders the
  switch but never redraws it, so it looked dead however often it was clicked
  (Anton, 2026-07-30). A nested `ObservableObject` publishes nothing to the
  parent's view — it has to be observed where it is read.
- **Two visible affordances in the header**: `+` picks apps from disk
  (`NSOpenPanel`, restricted to `.application`, starting in Applications), and
  the second button opens edit mode. The first build had adding behind a Finder
  drag and editing behind a 0.6s long press, and Anton found neither
  (2026-07-29) — a mode that cannot be discovered does not exist. Dropping from
  Finder still works and is still documented; anything that is not an `.app` is
  ignored rather than parked as a dead icon.
- **Edit mode** wobbles the icons ±1.8° with a 0.36s half-period, neighbouring
  icons leaning opposite ways. The first attempt (±1.4° at 0.14s) read as
  flicker rather than sway. Driven by a `Timer` that is started on entry and
  invalidated on exit — NOT `repeatForever`, which is banned panel-wide because
  it makes the hosting controller recompute its size forever. Each icon carries a
  ✕ drawn as a muted circle with the glyph knocked out; a bright badge on a
  moving icon reads as blinking.
- **Flush edges AND equal gaps.** A row is eight fixed 30pt slots with `Spacer`s
  between them, not a `LazyVGrid`: the spacers carry all the slack, so the first
  icon sits on the module's left inset, the last on its right one, and the seven
  gaps are identical. Two earlier cuts each failed one half of that — centring
  every grid cell indented the whole row by half the column's slack, and aligning
  only the outer two cells to the edges left the outer gaps 3.6pt wider than the
  inner ones (Anton, 2026-07-29 and 2026-07-30). A half-filled last row keeps the
  pitch with invisible slots, and the drag maths reads the measured pitch instead
  of a guessed cell width.
- **Dragging** reorders the grid: the dragged icon follows the pointer, scaled
  1.08 and above the rest, and a YELLOW LINE marks the GAP it would drop into —
  2pt wide, sitting in the middle of the 6pt column gap. Highlighting the target
  cell instead was the first cut and read as "swap with this one" (Anton,
  2026-07-29). Which gap the line marks follows the direction: dragging forward
  lands the icon AFTER the cell at the drop index (removal shifts the rest back),
  dragging backwards lands it BEFORE that cell. The destination is worked out
  from the travelled distance in cells (36pt across, 44pt down with names, 36pt
  without), so it does not depend on the panel's width, and it clamps rather than
  crashes. The grid only reshuffles on drop.
- **A moved app heals itself**: the path launches it, the bundle id finds it
  again if it moved house, and the shelf quietly rewrites the path.
- **A new grid is empty and says so** — "no apps yet, press + or drag one from
  finder" — rather than showing an unexplained blank strip.
- Opt-in: a fresh install has no grid unless onboarding was asked for one, since
  an empty launcher says nothing. Grids are made in two places, both of which the user reaches while
  arranging modules: the apps section of settings, and under the module/space
  table itself, where the chips are dragged. A grid chip drags between spaces and
  hides under its eye like any other module. It is also the ONLY chip with a
  ✕ — every other module can be hidden but never deleted — and that ✕ asks first,
  with the same scrim + card the tab delete uses, saying that the apps themselves
  are untouched. The apps section of settings deletes a grid too.

### Color (eyedropper)

- Opt-in module (key `"color"`, title `colorLabel`): a hotkey or the panel's
  `pick` button opens macOS's own loupe (`NSColorSampler`); the clicked pixel
  becomes a COLOR entry in the clipboard history AND goes onto the pasteboard in
  one step — "press, then paste" is the whole feature. Escape cancels and writes
  nothing. **No Screen Recording permission**: the system loupe returns one
  color, no bitmap of the screen ever reaches Hop (that permission belongs to the
  separate text-recognition module).
- Notation: all three at once. Every row in the list carries `hex`, `rgb` and
  `hsl` in FIXED-WIDTH columns (48 / 92 / 104), and each one is its own copy
  button — a chip that switches a global notation was rejected, because the ask
  is "give me this color as rgb", not "change my mode" (Anton, 2026-07-25).
  Fixed widths mean a short value in one row cannot shift the next row's columns.
  `colorFormat` survives only as the notation written to the pasteboard at pick
  time (default `hex`). The pure conversion (including HSL, hue never rounding to
  360°) lives in `HopCore.ColorFormatting` with tests.
- History: a color IS a clipboard entry — `ClipboardItem.colorHex` holds the
  canonical `RRGGBB` (the row's swatch is drawn from it, so the swatch survives a
  notation change) and `text` holds the pasteable notation. Color entries take no
  part in TEXT dedup, so copying the literal characters "#336699" never swallows
  the color row; re-picking the same color in the same notation changes nothing,
  in another notation it rewrites the top entry in place, and an older entry for
  that color moves up as a fresh pick (`ClipboardRules.remembering(color:text:in:)`,
  tested). A color needs no file on disk, so pruning one deletes nothing.
- Picking CLOSES the panel (a popover would cover the pixel being aimed at) and
  brings it back on the eyedropper's own space once a colour is stored
  (`AppModel.reopenPanel`, wired to the status item's `togglePopover`). A cancel
  reopens nothing: there is no result to look at (Anton, 2026-07-26).
- The module's own mark is a PALETTE, not an eyedropper: the same glyph on both
  ends of the header read as two pick buttons (Anton, 2026-07-25). It is drawn
  small and tertiary like every other module's mark, while the action keeps the
  eyedropper at full weight. The what's-new checklist uses the same palette.
- Module list: the header is one line (name + an icon-only pick action), and
  under it the picked colors as ROWS — swatch plus the three notations. Clicking
  a notation copies exactly it and shows an OPAQUE "copied" badge on the row's
  trailing edge (a translucent one let the numbers show through). Copying goes
  through `putOnPasteboard`, which does NOT re-remember: the list keeps the order
  the colors were picked in and never reshuffles under the cursor. Swatches carry
  a 1px `controlStroke` border — a white swatch would otherwise vanish in the
  light theme.
- Two settings, the same pair the clipboard has: how many colors to keep
  (`maxColorsKey`, 3…100) and how many rows to show before scrolling
  (`colorRowsKey`, 1…10), on the eyedropper's settings page. Colors are pruned by
  their own cap (`ClipboardRules.pruned(…, maxColorItems:)`), so a busy clipboard
  cannot evict them.
- Modules that produce clipboard content enter it through
  `ClipboardController.remember(external:)` / `remember(color:text:)`, which also
  stamp the pasteboard change counter, so Hop's own write never comes back a
  second later as a foreign copy and a duplicate row.
- Hotkey `⌃⌥P` (the "open" action of the `color` module in `ModuleCatalog`). A
  combo is claimed ONLY while its module is visible (`HotkeyActivation` +
  `refreshModuleHotkeys()`, called at launch and after every layout change):
  taking a global shortcut away from other apps for a hidden module would be
  rude. Its settings row appears on the same condition.
- Ships HIDDEN: it serves designers and developers, so `optInModules` +
  `SettingsKey.optInModulesSeeded` set its hidden flag exactly once; the
  fresh-migrate path hides it deterministically on every recompute and claims
  the flag itself.

### Text recognition (OCR + QR)

- Opt-in module (key `"ocr"`, title `ocrLabel` — "text recognition"; the old
  "screen text" read as a place, not an action). ONE panel line: the name plus
  two icon actions — "select on screen" (`ocrSelect`) and "paste picture". Text
  and barcodes become ONE clipboard-history entry, already on the pasteboard.
  Escape cancels and writes nothing. The panel closes before the crosshair
  appears (a popover would cover what the user is framing).
- The action's glyph is `square.dashed` — a marquee, the shape the user drags
  across the screen, in the same dashed family as the Screen Recording
  permission's mark. A bare `viewfinder` read as "enter full screen" and
  `camera.viewfinder` fixed the meaning at the cost of the ink: its camera body
  packed a dark clot into a 12pt glyph (Anton, 2026-07-27). The marquee keeps
  the meaning with an empty middle. It is the SQUARE marquee rather than
  `rectangle.dashed` because the row's icons have to match each other: a
  landscape marquee tall enough to match the boxed arrow beside it ran half
  again as wide, and width is what reads as "bigger". At 12.5 the square one
  draws 11.3 × 12.0 pt — the arrow's own box. Same glyph in the panel row and in
  the window's button.
- **Languages: Vision detects the script itself** (fixed 2026-07-28). The
  request used to name the INTERFACE language plus English and nothing else, so
  anything not written in Latin came back as garbage — the Mori Art Museum's
  opening hours read as `4829 8238(` instead of `森美術館`. Measured on macOS 26
  before choosing the fix: on a six-script image (Japanese, Russian, English,
  Korean, Arabic, Thai) `automaticallyDetectsLanguage` returned ALL SIX in 488 ms,
  while naming those same six languages explicitly LOST the Russian, Arabic and
  Thai lines in 167 ms, and `en-US` alone garbled the Japanese and missed the
  rest. On Latin pages detection matched the explicit list exactly, including the
  mixed Latin/Cyrillic screen an older comment cited as the reason to avoid it.
  So detection is ALWAYS on and there is deliberately NO language setting: an
  earlier cut shipped one and Anton removed it the same day — nobody would find
  it, and naming languages makes recognition worse, not better. Two findings are
  load-bearing and
  must not be re-litigated without new measurements: Vision's CONFIDENCE cannot
  judge a reading (a wrong-language pass over Chinese reported 1.00 while
  producing nonsense), so no scoring or threshold decides anything here; and
  naming many languages HURTS, so the setting must never be described as making
  recognition "more multilingual". `RecognitionPlan` (pure, tested) maps the
  selection onto what the machine supports — a tag Vision does not list makes the
  WHOLE request fail.
- **A second pass repairs a line carrying two distant scripts** (2026-07-28).
  Detection picks ONE model per text region, and a line IS a region, so a line
  holding `Hello 世界` plus two Cyrillic words came back as `Hello 世界 门puBeT
  MMp` — the ideographs right, the Cyrillic noise. Asking for Russian instead
  flips the damage. The fix
  is a rule rather than a better guess: **a pass may only be trusted on the
  scripts it was actually reading** (`HopCore.ScriptMerge`, pure, tested).
  - The TRIGGER is a word that mixes two scripts inside itself — no real word
    does, so it is the signature of a wrong-language reading. Only lines carrying
    such a word are touched, and a picture without one never runs a second pass
    at all (measured: plain Latin and a Japanese page cost exactly what they did
    before; the mixed picture costs ~+75 ms).
  - The SECOND PASS asks for the ALPHABETS on the picture, not "everything the
    first pass missed": the damage always runs one way — a CJK model swallows the
    alphabet beside it, while an alphabetic model merely drops ideographs. Two
    tags at most, since naming many languages makes Vision worse. The reader's
    own script is the last resort, for a page whose alphabet was mangled so badly
    it left no trace to detect.
  - The MERGE takes each word from whichever pass had the competence to read it,
    matching words by the box Vision reports for the substring. Word ORDER always
    comes from the first pass, never from the x coordinate — sorting by x
    reversed an Arabic line.
  - Verified end to end through `Hop --ocr-selftest <image> [--verbose]`, which
    prints the passes and the merge for the reference pictures.
- **A reading that holds a web address can be FOLLOWED** (Anton, 2026-07-27):
  the window shows an "open link" button that hands the address to the default
  browser. This is the point of reading a QR code on the Mac rather than
  pointing a phone at it — a bill's payment link opens in the browser that is
  already signed in. The rule is `ScreenTextRules.link(in:)`:
  - `http` and `https` ONLY. A scanned code is untrusted input, and every other
    scheme is a lever for whoever printed it: `file://` reaches the disk, a
    custom scheme reaches whatever app claimed it. `mailto:`, `tel:`, `WIFI:`
    and vCard payloads stay plain text in the history, with no button.
  - The whole reading is searched, not just barcodes, so an address printed in
    a screenshot opens the same way. An address must spell its scheme out —
    `.md` and `.js` are real top-level domains, so a looser match would offer
    to open `readme.md`. The one exception is a reading that is NOTHING but a
    bare host (`example.com/menu`, the shape of a printed QR code), which is
    promoted to `https://`; a bare host inside a sentence never is.
  - The first address wins, sentence punctuation glued to it is trimmed
    (`see https://example.com.`), and brackets the address opened itself are
    kept (`.../Hop_(tool)`).
  - Where a link is present, open takes the accented button and copy steps back
    to the quiet one. The address is not repeated on the button — it is in the
    text field above, in full, so the destination is read before the click.
- **The result is SHOWN, not filed away silently** (Anton, 2026-07-25): a
  recognition window opens with the text in an editable field, a drop plate for
  images and a copy button. It is a `ConverterWindow` subclass so ⌘V reaches it,
  and the paste monitor stands down while it is key — a picture pasted there is
  input for recognition, not a clipboard entry. The drop plate is generously
  sized (padding 48) and the window sizes to it.
- **The reason this module exists**: the result is a HISTORY entry, searchable
  next to everything else copied. Live Text and the standalone grabbers hand the
  text over once and forget it — without the clipboard link this would be a clone
  with no reason to prefer it (Anton, 2026-07-15).
- Area selection is `/usr/sbin/screencapture -i -x -o -t png` into a temp file,
  NOT a hand-rolled overlay: the system tool brings the real crosshair
  (magnifier, live dimensions, space to reposition) and is the UI users already
  know. A cancelled selection leaves no file, which is exactly how cancel is
  detected; the temp file is deleted right after recognition.
- Recognition: one `VNImageRequestHandler` pass with `VNRecognizeTextRequest`
  (accurate, language correction on) AND `VNDetectBarcodesRequest` — same walk
  over the same pixels, so QR/barcodes cost nothing extra. Runs off the main
  thread. Languages are the app's own plus English, prefix-matched against
  `supportedRecognitionLanguages()` (an unsupported tag fails the whole request);
  automatic detection is deliberately NOT used — it guesses badly on mixed
  Latin/Cyrillic screens, and the UI language is the better hint.
- Assembly is a pure rule in `HopCore.ScreenTextRules` with tests: a barcode WINS
  over text (framing a code is an unambiguous ask; its caption would be noise),
  several codes join deduplicated, otherwise text lines join with **newlines
  kept** — a table or code snippet must not collapse into one run-on line.
  Repeated text lines are never deduplicated (a column really can hold the same
  value twice). `readingOrder` sorts observations top-to-bottom then
  left-to-right, quantizing rows to 1/200 of the height so a hair of vertical
  noise cannot interleave one visual line, with the index as the final tiebreak
  (a valid strict ordering for any input).
- Permission: **Screen Recording**, checked with `CGPreflightScreenCaptureAccess()`
  BEFORE the crosshair and requested with `CGRequestScreenCaptureAccess()` —
  without it the capture would come back as a black rectangle, which reads as a
  broken feature. The denied state shows a line plus a button that deep-links to
  System Settings → Privacy → Screen Recording. Hop reads only the rectangle the
  user draws, only when asked.
- States (`ScreenTextController.State`): idle → selecting → reading → done(count)
  / empty / denied / failed. A receipt or complaint clears itself after three
  seconds — nothing here is worth a dialog.
- A dropped or pasted picture skips the crosshair entirely and therefore needs
  NO permission at all: recognition runs on the image handed over, not on the
  screen.
- Hotkey `⌃⌥R`, module-gated exactly like the eyedropper's; ships hidden via
  `optInModules`. Snapshot flags: `--ocr`, or `--tools` for both new modules.

### Archive (drag & drop)

- Module key `"archive"`, title `archiveLabel` ("file archives"), with EVERY
  format spelled out on its own line under the name — "zip · rar · 7z · tar ·
  tar.gz · tar.bz2 · tar.xz · gz" — so the module reads as ZIP files rather than
  "putting something away in an archive" (Anton, 2026-07-25). An ellipsis was
  rejected: it leaves the reader guessing which formats it hides, and on the
  name's line the longest translations pushed the tail off. The list is built
  from `ArchiveFormat.allCases` via `displayName`, so a new case cannot go
  unlisted (tested both ways: named, and recognized back).
- **Adding is not starting** (Anton, 2026-07-25): a drop — or ⌘V, several files
  at once — fills a QUEUE (`pending`), and the work runs when the button is
  pressed. The queue decides which button that is (`plannedKind`): NOTHING BUT
  archives unpacks each one, anything else — files, folders, a mixed set — packs
  the whole queue into ONE archive, because collecting several things together
  reads as "make this one archive". A row can be taken back out; the list can be
  cleared.
- Results land on the DESKTOP by default (`archiveDestination`, `.desktop`): an
  unpacked folder has to appear where the user is already looking. `.alongside`
  keeps the old "next to the original" behaviour and `.custom` is any chosen
  folder (`archiveDestinationPath`, falling back to the Desktop if it has since
  gone missing). The pack format is a chip row (zip / tar.gz / 7z, stored in
  `archivePackFormat`, default zip) shown ONLY when the queue is going to be
  packed — an archive being opened comes out as whatever it already is, so the
  format has nothing to say about it.
- A write macOS refuses (the Desktop, Documents and Downloads folders are gated)
  is reported as `.denied` with its own row text, never as a generic failure:
  "nothing appeared" is the worst way to learn a folder needs consent. The
  usage-description strings ride in `Info.plist`.
- **Unpack layout**: the tool extracts into a hidden staging folder INSIDE the
  destination, then the result is lifted out: exactly one top-level item keeps
  its own name, several items go into one folder named after the archive. That
  gives both "no pointless wrapper" and "nothing scattered over the desktop"
  without listing the archive first, and the move is instant (same volume).
  Names never overwrite: `ArchiveRules.uniqueName` numbers them Finder-style
  ("photos 2.zip"), comparing case-insensitively because the default macOS
  volume is.
- **Staging lifecycle**: new folders are named
  `.hop-unpack-<launch UUID>--<job UUID>`. Before extraction, Hop removes only
  managed staging directories from older launches (including the legacy
  `.hop-unpack-<UUID>` form), preserving current-launch jobs so concurrent
  extracts cannot delete each other. Similar names, regular files and symlinks
  are never touched. Desktop and the configured custom destination are swept
  at launch; arbitrary alongside/Finder destinations are swept when the next
  extraction reaches them. Success, tool failure, empty output, permission
  failure and thrown errors all clean their own staging directory before the
  job finishes.
- Tools: zip via `ditto -x -k` (keeps macOS metadata a plain unzip drops),
  tar/tar.gz/tar.bz2/tar.xz via `tar -xf` (bsdtar detects compression and strips
  absolute paths), a bare `.gz` via `gunzip -c` into the archive's own stem.
  Packing runs WITH THE PARENT AS WORKING DIRECTORY on bare item names, so an
  archive holds "shoot/one.raw" and not this Mac's "/Users/…" path: `zip -r -q
  -X` (no `__MACOSX` junk) and `tar --no-mac-metadata -czf`.
- **rar / 7z** need the 7-Zip helper (`7zz`, ~6 MB), fetched on the FIRST drop
  that needs it and installed only after its Ed25519 signature checks out. Hop
  never CREATES rar — the format is proprietary and no free packer may write it,
  so `PackFormat` has no rar case at all (asserted by a test).
- Zip-slip: `ArchiveRules.isSafeEntryPath` rejects absolute and `..` entry paths
  (tested); staging inside the destination contains anything the tools let past.
- **The drop target is a WINDOW**, not the panel: a popover closes the moment a
  drag starts, pulling the target out from under the file (Anton, 2026-07-25).
  The module's panel row opens the archive window, exactly like the converter's;
  dropping onto the row still works and opens the window. The window is a
  `ConverterWindow` for its ⌘V handling (Hop has no Edit menu), and the
  converter's own paste monitor stands down while it is key. Its height follows
  its content the way the converter's does, so an empty module is a drop plate
  and nothing else — no gap underneath (Anton, 2026-07-25).
- **Default opener in Finder**, exactly like the torrent module's: a card in
  SETTINGS → the archives page (not in the window — being the opener outlives any
  window, Anton 2026-07-25). Two rules, both Anton's (2026-07-26):
  - **Only rar may be claimed, and macOS's own app is never overridden.**
    `claimableTypes` contains only `com.rarlab.rar-archive`, and skips it when
    its current handler is any `com.apple.*` bundle. Zip, tar, gz, bz2, xz and
    7z stay with Archive Utility. If a future macOS release learns rar, the
    claim card disappears automatically.
  - **The state is READ, never remembered.** `isDefaultHandler` asks Launch
    Services through `NSWorkspace` every time (and `DefaultHandlerCard` re-reads
    on every app
    activation), because the default can be changed in Finder at any moment and
    a control that disagrees with the system is worse than no control.
  Earlier Hop versions claimed every declared archive type. When the live
  Launch Services state shows that Hop still holds any non-rar type, settings
  show a recovery action that returns only those Hop-held non-rar types to
  `com.apple.archiveutility`; the action never changes rar or a third-party
  handler and disappears after the handoff. Handler reads and writes use the
  macOS 12+ `NSWorkspace` content-type API; the deprecated Launch Services
  setter is not used.
  **Every declared type carries its own document icon** (Anton, 2026-07-27):
  a sheet of paper with a folded corner, Hop's asterisk, and the format on an
  ink band at the foot — TORRENT, RAR, ZIP, 7Z, TAR, GZ, TGZ, BZ2, XZ. Before
  this every type pointed at `AppIcon`, so a folder of archives looked like a
  wall of duplicated apps and said nothing about what the files were. Documents
  are paper and the app is a cream plate precisely so the two are never
  confused. macOS shows the icon only where Hop is the registered opener, which
  is exactly the intent: the icon appears when Hop owns the file and not before.
  Each `.icns` is drawn per size rather than downsampled; below 64pt the label
  is dropped, because at that size any text is a smudge and Finder shows the
  file name anyway. The files are build output (`scripts/make-doc-icons.sh`),
  not stored assets, and `DocumentIconDeclarationTests` fails if a type is ever
  declared without its own icon or the generator and the plist drift apart.
  Settings also carry a "show in the panel" switch for the module itself: being
  the opener and occupying a row are separate decisions, and someone who only
  double-clicks archives in Finder should not have to dig through "modules &
  tabs" to reclaim the space (Anton, 2026-07-26). It flips membership, the same
  thing that table does — hiding is not switching off.
  `processOpenBatch` routes an opened archive into the extractor, and it works with
  the module HIDDEN — the panel row is a place to drop things, not a
  precondition for Finder. Finder-open is a separate path from the drop/paste
  queue: it extracts only the opened archive, always beside that archive,
  regardless of `archiveDestination`, and leaves queued items untouched. The
  manual archive window is never shown or populated by this path. Instead, each
  Finder open event immediately creates one small standalone progress window
  (one row per selected archive, with an indeterminate activity indicator
  because the command-line extractors provide no reliable fraction). It closes
  automatically once every archive succeeds; any denied/tool/empty/helper
  failure keeps it open with the human-readable reason. Closing the progress
  window manually does not cancel extraction. Several non-native archives in
  one event share one helper installation rather than racing duplicate
  downloads. Large batches scroll inside the bounded window. Choosing a final
  collision-free output name and moving the staged result are serialized, so
  simultaneous archives cannot select the same path. Dev and bundle-less builds
  never mutate global archive associations; only the production bundle exposes
  those writes. The types are declared in `Info.plist` with
  `LSHandlerRank: Alternate` (and `CFBundleTypeIconFile`, so Finder draws Hop's
  icon on the files it owns) — Hop offers itself without shouldering aside
  whatever the user already chose.
- Jobs are in-memory rows (max 4, running rows never trimmed) with a
  reveal-in-Finder action when done; snapshot flags `--archive` (panel) and
  `--window-archive` (the window itself) stage two.
- `ToolInstaller` is the shared download-verify-install mechanism (one trust
  root, `toolPublicKeyBase64`, signed with `scripts/sign-tool.swift`);
  `TorrentEngineInstaller` is now a thin subclass naming the rqbit manifest, and
  the 7-Zip helper is a second instance. Hop ships no third-party binaries: each
  is fetched only when its module actually needs it.

### Converter: documents (1.5.0)

- A new `MediaKind.document` group in the SAME converter window and batch
  machinery: `md`, `markdown`, `txt`, `rtf`, `doc`, `docx`. Its chips choose the
  TARGET (`convDocTarget`: pdf / md / docx, default pdf) — the first category
  whose setting is a destination format rather than a compression level.
  Documents are matched by EXTENSION before the generic UTType checks, since
  `.md`/`.txt` conform to `public.text` and would otherwise fall through as
  unsupported. Size estimates are skipped for the group: a document changes
  shape, not weight, so a forecast would be noise.
- PDFs keep their own group and gain a MODE (`convPdfMode`: compress / markdown
  / docx, default compress) instead of moving categories — a dropped PDF still
  lands where the user expects. Word joined markdown on 2026-07-29: a pdf that
  has to be edited usually has to be edited in Word, and the machinery was
  already there (extract the text the way the markdown target does, lay it out
  again, hand it to the docx writer). In either extraction mode the quality
  slider is hidden: there is nothing to tune about extracting text.
- **Documents are set in Helvetica Neue, not the system font.** Printing an
  NSTextView set in San Francisco asks CoreText for `.SFNS-Regular…` BY NAME,
  gets Times New Roman substituted, and embeds a mapping under which Cyrillic
  extracts wrong: a heading written in Cyrillic came back with its "ka" turned
  into U+0138 (KRA), and copying that line out of the pdf in any reader gave the
  same (found 2026-07-29 while adding pdf → docx). Latin was unaffected, which is
  why it went unnoticed. A real embeddable family with a proper Cyrillic cut
  fixes it, and incidentally makes the output the deliberate typography the
  module claims rather than a silent Times fallback. Code blocks take Menlo for
  the same reason.
- **A paragraph is a code block only when ALL of it is fixed-pitch.** Reading the
  first run alone turned any paragraph that merely began with an inline
  `snippet` into a fenced block on the way back out of Word (found 2026-07-29 in
  a round-trip check). Links are the one thing that cannot survive that trip at
  all: AppKit's Word writer stores no hyperlink relationship, so a link arrives
  as plain text — said out loud in the module's help rather than left to be
  discovered.
- Output names drop the `-min` suffix for documents (`notes.pdf`, then
  `notes-2.pdf`): "-min" belongs to the compression story and would misdescribe
  what happened. A file already in the target format is REWRITTEN rather than
  refused — markdown comes back normalized, a Word file comes back clean.
- **Markdown engine is ours** (`HopCore.Markdown`), not a package: a
  CommonMark subset (headings, paragraphs with wrapped-line joining, lists,
  quotes, fenced code, rules; inline bold/italic/code/links with backslash
  escapes), plus a writer for the reverse direction. Zero dependencies, offline
  builds, and rendering we can pin with tests. The plan's swift-markdown route
  was dropped for that reason (Anton, 2026-07-25).
- **md → pdf**: markdown → `NSAttributedString` with Hop's own typography (A4,
  2cm margins, 22/17/14pt headings, 11.5pt body, monospaced code on a light
  fill) → an off-screen `NSTextView` printed via `NSPrintOperation` with
  `jobDisposition = .save`. That is what gives REAL pagination, and it is the
  same path a Word file takes, so images inside a .docx survive (an HTML detour
  would drop them — AppKit's HTML writer exports no images at all, verified).
- **docx/doc/rtf → pdf or md** through AppKit's own readers (what TextEdit
  uses). Structure is RECOVERED, not read: `HopCore.DocumentHeuristics` picks
  the body size as the most common size (ties to the smaller), then classifies
  by ratio (≥1.6 → h1, ≥1.3 → h2, ≥1.12 → h3, bold at body size → h3). Runs
  keep bold/italic/monospace/links as markdown markers; consecutive fixed-pitch
  paragraphs fold into one code block; an all-dashes line becomes a rule.
- **pdf → md** reads each page for its lines and their type sizes, then applies
  the same heuristics plus `continuesParagraph`: a PDF stores one run per VISUAL
  line, so wrapped lines are merged back into paragraphs unless the previous
  line ended a sentence or the next starts with a capital, a digit or a list
  marker. A page with NO text layer (a scan) is rendered at 2× and read with
  Vision — the screen-text module's recognition — using each box's height as its
  "type size" so the heading ratios still apply.
- **Reading a page is a fast path over a complete one** (`PDFContentScan` +
  `PDFLineMetrics`, 2026-08-04). The fast path takes the lines and their boxes
  from `selectionsByLine` and the type sizes from a walk of the page's own
  content stream, matching the two by vertical position: a segment belongs to a
  line when its baseline falls inside that line's box, and where a line carries
  several sizes the run with the MOST GLYPHS decides it (so a footnote mark
  cannot demote a heading, and a decorative capital cannot promote body text).
  Bold comes from the `BaseFont` name. Nothing is decoded from the stream —
  PDFKit stays the source of the text, so encodings and ligatures are unaffected.
  The complete path (per-page attributed strings) still runs whenever the fast
  one declines: a rotated page, a page whose text is drawn inside form objects,
  or any page where fewer than 90% of lines found a size (`coverageFloor`).
  Measured on four documents: same markdown out, 1.3× to 8.4× less time in,
  the spread being how much work a document's fonts give macOS — a page whose
  fonts it has to substitute cost 15 ms to lay out and 0.3 ms to walk.
- Honest limits stated in the UI (`convDocNote`) and the guide, not hidden: Word
  columns, footnotes and headers are lost; PDF → md is text extraction with
  heading guesses, not a faithful conversion.
- `isVerticallyCentered = false` on the print info: AppKit centres a PARTIAL
  page by default, which left the last page of a document floating in the middle
  of the sheet. Pages start at the top margin, like anything printed.
- The capability table lists what each category ACCEPTS and what it produces —
  and nothing else: the "what we cannot do" line is gone (Anton, 2026-07-25).
- **Video frames for the places video gets posted** (`VideoFrame`, Anton
  2026-08-04). Beside format, resolution and compression the video group has a
  `frame` row — `original`, 9:16, 4:5, 1:1, 16:9 — and, whenever a frame other
  than the original is chosen, a `fit` row deciding what happens to a picture of
  another shape: `crop` (fill the frame, lose the edges — the default and what
  every platform does anyway), `bars` (all of it, empty space around it) or
  `blur` (all of it, over an enlarged blurred copy of itself). Ratios are
  written as ratios rather than platform names, which go stale.
  - The frame's SHORT side is the chosen resolution, so 1080 means 1080×1920 for
    a reel and 1920×1080 for a landscape one, and the sides are rounded to even
    numbers because encoders refuse odd ones.
  - **Nothing is ever upscaled.** A frame that would need more pixels than the
    source has shrinks, keeping its shape: 720p footage asked for a 1080-wide
    reel comes out 405×720, not an invented 1080×1920.
  - `crop` and `bars` are one layer instruction on an ordinary composition (the
    empty space is the frame's own black). `blur` goes through Core Image per
    frame — background scaled to COVER, clamped (a blur reads past the edge and
    would otherwise leave a transparent halo), blurred by 5% of the short side
    so a 4K export is blurred as much as a 540p one, with the picture composited
    over it. It is built ONLY when there is space to fill.
  - The size forecast runs the same composition, so the "→ ~N MB" beside a
    reframed group is the reframed size.
- Dev entry points (DEBUG only, like the torrent self-test):
  `Hop --doc-selftest <source> <pdf|md|docx> <outDir>` and
  `Hop --video-selftest <source> <shape> <fit> <outDir>`.

### Keyboard lock (cleaning mode)

- Module key `"keyboard"`, title `keylockLabel` ("keyboard lock" — the name says
  what it does, Anton 2026-07-25). ONE line in the panel: name + the duration
  chips; tapping a duration LOCKS immediately, so there is no separate start
  button to press afterwards. While it runs the same line shows the countdown
  and an unlock button. A full-screen cover states what is happening and carries
  a way out.
- The keys are swallowed by a `CGEventTap` (session tap, head-insert) over
  keyDown, keyUp, flagsChanged AND `NX_SYSDEFINED` (14) — the brightness/volume/
  media row is not "keys" to macOS and would otherwise keep firing. Events are
  DROPPED, never inspected. `tapDisabledByTimeout/ByUserInput` re-arms the tap
  rather than leaving the keyboard half-locked.
- The POWER key: a SHORT press is swallowed like every other key — on a
  cleaning cloth it is the one press that would put the Mac to sleep mid-wipe.
  Holding it still forces the Mac off, because a long hold is handled in
  hardware and never reaches a tap at all: the emergency exit stays open without
  Hop having to leave the short press alive (Anton, 2026-07-25). Touch ID keeps
  working.
- Way out, four of them: the cover's done button, the module's own unlock
  button, simply opening the panel — reaching for Hop while the keys are dead IS
  the ask to release them — or HOLDING ESC + SHIFT for five seconds when the
  mouse is out of reach. A CHORD, not a lone key: something resting on the
  keyboard can hold one key down for minutes, and that must not undo a cleaning
  lock (Anton, 2026-07-26). `noteChord(escape:shift:)` tracks both from the tap
  (shift comes off `event.flags`, so a bare modifier change updates it too) and
  arms a real Timer — shift never auto-repeats, so there would be nothing to
  count. The Timer is a BACKSTOP, not the only clock: every later event
  (esc auto-repeats ~30 times a second) re-checks the elapsed time against the
  start, because a timer on a run loop busy with the cover's animation fires late
  and the release then trails the full bar by half a second (Anton, 2026-07-26).
  The bar itself fills 0.15s early for the same reason — a finished bar must never
  sit there waiting. Both keys are still swallowed on the way through, and the cover states
  the chord on its own line, heavier than the rest, with a bar that fills over
  the five seconds while the pair is held and snaps back the moment either key
  goes up (`chordHeld`) — a five-second hold with no feedback is five seconds of
  wondering whether it works. A normal keyboard shortcut would be exactly the thing
  that is switched off. Durations are 1 / 5 / 15 minutes and ∞
  (`durations = [60, 300, 900, 0]`, 0 = until told otherwise); the countdown is
  replaced by the infinity glyph in that mode.
- **Unlocking is ordered, not merely correct** (Anton, 2026-07-27): `unlock()`
  removes the tap, then orders the cover out, then hands focus back to whichever
  app was frontmost when the lock went up (remembered in `showOverlay`, before
  `NSApp.activate`) — and only then updates the published state. Two things made
  a correct unlock feel half a second late. Publishing `isLocked` while the cover
  was still on screen bought a SwiftUI layout pass on the way out. Worse, Hop is
  an accessory app: after activating itself to catch the cover's click it stayed
  frontmost, so the keys were free but the first thing typed went to no window at
  all. If the earlier app is gone, Hop hides itself instead, which hands focus to
  whatever macOS picks next.
- **The menu bar says so**: while locked, the star is REPLACED by a keyboard
  glyph — a corner dot would be too quiet for a state that stops the whole
  keyboard, and it outranks the finished bell. Unlocking plays the
  keep-awake "off" cue, so the release is audible without looking.
- The cover sits at `.floating`, deliberately BELOW the menu bar: the mark up
  there is the explanation for dead keys and must stay visible.
- Permission: **Accessibility**, asked with `AXIsProcessTrustedWithOptions`
  BEFORE the lock — without it the tap silently never fires and the cover would
  promise a lock that isn't there. The module then offers the deep link.
- Hotkey `⌃⌥X`, module-gated like the other module hotkeys. The tap dies with
  the process, so a crash can never leave a locked keyboard behind.

### Permissions (settings window)

- An "app permissions" page — fourth in the sidebar, because it is the page
  people go looking for (Anton, 2026-07-26) — listing EVERY permission Hop can
  ask for, what it is for, and whether it is granted right now — plus what Hop
  never does. The list is taken from the code (actual API calls), never written
  from memory; a new permission means a new row.
- Rows: network to antonshakirov.com (updates + the two downloadable helpers),
  torrent traffic (only with the module on), the speed test (macOS's own
  `networkQuality`, Apple's servers), Accessibility (paste-into-app, window
  manager, keyboard lock), Screen Recording (screen text ONLY — the eyedropper
  explicitly does not need it), notifications (timer + torrent done),
  administrator password (once, for closed-lid `pmset`), launch at login.
- Live status where it can be checked: `AXIsProcessTrusted()`,
  `CGPreflightScreenCaptureAccess()`, `UNUserNotificationCenter` settings,
  `SMAppService.mainApp.status`. The notification query is skipped in a
  bundle-less process (a snapshot render throws otherwise). A row offers its
  System Settings deep link only when the permission is NOT granted.
- The same list, condensed, is a README section (all 22 languages) and a FAQ
  answer on the landing (all 8).
- The page CLOSES with a statement, set larger and bolder than anything above
  it: the permissions exist so features can work, nothing about the user is
  collected, nothing leaves the Mac — and, because a promise is worth little,
  a link to the source (Anton, 2026-07-26). A list of permissions reads as a
  list of risks until somebody says plainly what is NOT happening.
- Snapshot: `--permissions` opens the settings window on that page.

### What's-new card (module checklist)

- A release that introduces modules announces them as a CHECKLIST: one switch
  per module, all OFF, plus save/hide. Nothing appears in the panel that was not
  ticked (Anton, 2026-07-25) — the old single "enable" button pushed modules at
  people who had not asked. Saving places the ticked modules on the FIRST space,
  whichever space happens to be open, and hides the rest.
- For an UPDATING user every module introduced in the release starts hidden
  (`newInThisRelease`, one-shot `optInModulesSeeded`); a fresh install has no
  expectations to violate, so only the permanently opt-in tools
  (`optInModules`: eyedropper, screen text) stay hidden there.
- The archive row carries a SECOND switch of its own — "open archives with Hop"
  — because a decision worth making about archives is also worth making right
  here (Anton, 2026-07-25). It is not a module key (`archive.defaultHandler`,
  deliberately outside `moduleKeys` so nothing tries to place it on a tab), it is
  offered even when the module itself stays hidden, and saving only ever CLAIMS
  the types: an untouched switch must not hand back an opener chosen earlier.
- The torrent card keeps its own two-step shape (opt-in, then follow-up
  settings while the engine downloads); `FeatureAnnouncement.checklist`
  picks which shape a card takes.
- `modules160` announces the VPN list and a grid of apps. The apps row is the
  only entry that is NOT a module key: it is the bare word `apps` (`appsChoice`),
  a REQUEST for a grid, because the launcher exists only once a grid does.
  Ticking it creates one and places it — and it must be introduced to the tabs
  model (`ensure`) before being placed, since placing a module the model has
  never seen is a no-op. Its row carries a one-line detail, like archives: the
  word "apps" alone does not say what the module is.

## Agent bridge (files and hop:// links)

Hop can be READ and DRIVEN from outside — by the user's own AI agent, a script,
or a Shortcut — through two plain JSON files in the app's Application Support
folder, plus a URL scheme. Files rather than a socket or a CLI because that is
the surface an agent already has: it can read and write files without being
taught anything.

- `agent-commands.json` — written by the agent, performed, then EMPTIED by the
  app. The emptying is the acknowledgement. A file that parses to nothing usable
  is left alone rather than silently eaten, so a malformed write can be seen.
- `agent-state.json` — written by Hop every 5s and after every command: timer
  mode/state/remaining, keep-awake, the tracking task and its today total, and
  the whole to-do list with notes, reminders and favourites.
- `hop://` links carry the SAME vocabulary — `hop://timer/start?minutes=16`,
  `hop://todo/add?text=…&important=true&repeatDays=mon,wed`, `hop://tracker/stop`.
  This is what a Shortcut can open, so anything the system can trigger a Shortcut
  from can reach Hop.
- The vocabulary covers the app rather than one module: the timer and stopwatch,
  the tracker, to-dos (add with note/reminder/repeat/star, complete, delete),
  keep-awake with an optional duration, lid mode, the keyboard lock, window
  snapping to any of its 18 positions, the speed test, the eyedropper, text
  recognition, putting text on the clipboard, and opening the panel.
- It is a CLOSED list of verbs (`AgentCommand`), not "set any field":
  `timer.start` is unambiguous, while a declarative "timer: running" would leave
  the app guessing whether to restart a timer the user just paused. Parsing is
  deliberately forgiving (`AgentCommandParser`, pure, tested) — the writer is a
  language model: `do`/`command`/`action` are all accepted as the verb key, a
  bare array works as well as `{"commands": […]}`, durations may be `seconds`,
  `minutes`, `hours` or `"1h30m"`/`"25:00"`/a bare number of minutes, weekdays
  may be numbers or names, and ONE bad entry never discards the rest.
- `todos.json` and the command file are watched (`FileWatcher`, coalesced 0.3s,
  re-arming on the delete/rename that a replacing writer produces), so a task an
  agent appends to `todos.json` appears while the app runs instead of being
  overwritten by its next save.

## Shared components

- The converter and archive rows are the SAME card: icon 12, gap 6, name at
  mono 11, a `RowActionIcon` on the trailing edge, `padding(.horizontal, 10)` /
  `padding(.vertical, 9)` on `Theme.rowBg` — 40pt tall, both of them (Anton,
  2026-07-26). A bare `Image` on one of them and the shared icon on the other is
  what made them differ by a hair.
- **ModuleMarkIcon (Controls.swift) is the ONLY module mark**: a fixed 16×14
  frame around a 12pt symbol. SF Symbols differ in HEIGHT too — `doc.zipper` is
  a tall document, `archivebox` a squat box — so the converter card came out
  1.5pt taller than the archive card beside it (Anton, 2026-07-26). With the
  frame both are 32pt, exactly like the clipboard rows.
- **RowActionIcon (Controls.swift) is the ONLY module-row action icon**: SF
  Symbols are not drawn to a common optical size, so at one point size a dashed
  viewfinder looked smaller than a boxed arrow and the solid eyedropper looked
  darker than both — three buttons in a row that visibly did not match (Anton,
  2026-07-26). The view carries a per-symbol size and weight table (viewfinder
  and boxed arrow 12.5, eyedropper 12 and .light) and one 24×22 tap area — or
  16×14 in `compact` mode, where the WHOLE row is the button (converter,
  archives) and a tap area of its own would only make the card taller. The
  colour is always `textSecondary`, `Theme.editing` while the action runs.
- The recognition and archive windows size themselves from their content the way
  the converter does (`screenTextContentHeight` / `archiveContentHeight` + the
  matching `adjust…Height`), and their `contentMinSize` sits BELOW the empty
  content: a floor above it is exactly what leaves a gap under the drop plate.
- **SettingChip (Controls.swift) is the ONLY chip toggle** in the entire
  app: height 28, corner radius 5, mono 10 / icon 13, padding 9,
  inactive border Theme.divider, hover hoverDim+pointer. All former
  local chips (settingChip/unitChip/themeIcon/alertMode/styleChip/
  bigToggleChip/displayStyleCard, onboarding and converter chips) are thin
  wrappers over it. A new chip = SettingChip only; copies are forbidden.
- **RowCircle + TransportCircle (Controls.swift)** are the shared leading-circle
  geometry and view for the row modules: the tracker's play/stop button and the
  to-do checkbox are ONE control at ONE visible diameter (`RowCircle.diameter`,
  18pt), each LEFT-ALIGNED (not centered) in the 22pt `RowCircle.gutter` at the
  2pt row inset, so the circle's visible edge sits exactly on the row inset line
  — the same line the module subheader and footer text start on — and the two
  circles line up on the same left column. `TransportCircle` draws a FILLED disc
  (glyph knocked out) or a BORDERED ring (an empty `systemName` = an unchecked
  box), with per-caller colors — the timer transport palette by default, muted
  tokens for the checkbox.
- **Play glyph (`PlayGlyph`, Controls.swift)** is the ONE play triangle across
  the whole app — SF's sharp `play.fill` is never used for a play control. It is
  a hand-drawn triangle filled and then stroked with a thick round line-join so
  the corners bulge smooth (the same technique as the status-bar running badge),
  everything proportional to a `box` size and offset right `box·0.06` for optical
  centering. Corner rounding is the `round` fraction of `box`, 0.46 by default
  (tuned noticeably rounder than the original 0.34, "round as much as possible",
  while still reading as a play down to the 18pt row circle); one factor scales
  sanely to every size. Call sites: the tracker/to-do transport
  (`TransportCircle`, `box = 0.38·diameter` at `round 0.36` — grown 2026-08-28
  because the glyph read as a dot at row size, and rounded LESS with it: at 0.46
  the join eats the tip and both far corners, so a bigger box only looked wider),
  the main timer button — compact 27/34pt and full 48pt,
  `box = 0.315·size` — the torrent row play control (`box 11`, pause keeps SF
  `pause.fill`), and the timer help-tab icon legend. The menu-bar badge is
  deliberately excluded (it ships with the corner-system redesign). Pause glyphs
  everywhere keep SF `pause.fill`.
- **HoverDeleteX (Controls.swift)** is the shared hover-only row delete. Both row
  modules insert it IN FLOW, only while the row is hovered, right before the
  row's trailing fixed content (the tracker's time; nothing follows it in
  to-dos) — it lives inside the row's flexible spacer, so a non-hovered row
  reserves no width and the trailing content never moves or gets covered.

## Dock presence

Hop is an accessory app (`LSUIElement`, `setActivationPolicy(.accessory)`) and
has no Dock icon — which is right until it opens a window of its own. A window
that cannot be reached from the Dock has to be found through the panel every
time, and the panel is the whole app when all the user wanted back was the
converter (Anton, 2026-07-28).

- While at least one of Hop's OWN windows is open, the policy is `.regular`:
  the app takes a Dock icon, a place in Cmd-Tab and a menu bar. The icon and
  the menu bar leave with the last window (`leaveDockModeIfIdle`, driven by
  `NSWindow.willCloseNotification` — which arrives while the window still
  reports itself visible, hence the one-runloop delay before the check).
- The switch happens BEFORE the window is ordered in (`enterDockMode`, called
  ahead of every `NSApp.activate` that precedes a window). Switching after it
  is on screen makes the app blink out of focus and the window drop behind
  whatever was in front.
- Counted windows: settings, the torrent add sheet, converter, archive,
  recognition, onboarding and each Finder archive-progress window. NOT the
  panel — it hangs off the status item and closes on any outside click, so it
  belongs to the menu bar rather than the Dock. NOT the quit confirmation: it
  lives for a second and asks one question.
- A click on the Dock icon reaches the window it is there for, including a
  minimized one (`applicationShouldHandleReopen` deminiaturizes and raises).
- `showWindowsInDock` (settings → general) turns it off for people who run a
  menu-bar app precisely so that nothing appears in the Dock. ON by default.
- Side effect worth knowing: in `.regular` SwiftUI supplies a real menu bar
  (Apple · Hop · Edit · View · Window · Help — verified 2026-07-28), so ⌘V in a
  window goes through the system Edit menu while one is open. The
  `ConverterPaste` monitor still handles the accessory case and stays.

## Panel and navigation

- Header: a spaces switcher on the left — one icon tab per space, click to
  switch, the active one chip-highlighted — and the service trio on the
  right: ⓘ (about), gear (settings), ⏻ (quit, with a confirmation dialog).
  The switcher is pure navigation: adding, reordering, renaming (icon) and
  deleting spaces all live in the settings "modules & tabs" table (the
  combined space/module table), so a stray header click can't create a
  space. Up to 4 spaces (`PanelTabsModel.maxTabs`) — the
  cap keeps 4×56pt tabs plus the trio inside the 340pt header content
  (≈338pt at the cap). Panel width 368.
- Deleting a space (in the settings table) moves its modules to the first
  remaining space and hides them there — nothing appears where the user did not
  put it (`PanelTabsModel.deleteTab`; confirm copy "its modules move to the
  first one and are hidden"). The
  last remaining space can never be deleted. The settings-table drop is resolved
  by pure, tested HopCore helpers: `SettingsDropGeometry.insertIndex` turns the
  laid-out chip frames + the drop point into an insert index (one resolver for
  both the live indicator and the commit), and `PanelTabsModel.applyDrop`
  applies it (remove-then-insert, so a drop onto a module's own slot is a no-op).
  `PanelTabsModel` is defensive against a caller-built empty model — `ensure`
  no-ops instead of indexing `tabs[0]`.
- **1.3.x → spaces migration:** upgrading from a 1.3.x build (one flat module
  order plus per-module `show*Module` toggles) into 1.4.0 spaces is one-shot on
  launch — the flat order becomes the "house" space, the system monitor and the
  tracker+to-do pair split into their own canonical spaces, and every module
  whose legacy toggle was OFF is hidden (exact seeds and
  one-shot flags in "Default spaces" below). It is idempotent: each step runs
  once behind its flag and never re-disturbs a layout the user has since
  rearranged.
- **Empty-space hint:** a space with NO visible modules (its modules dragged
  elsewhere or hidden) shows a centered `tabEmptyHint` ("empty space — move
  modules here", tertiary) in place of a blank body, so the space still reads as
  a real, fillable place rather than looking broken.
- Default spaces: a fresh install migrates into THREE spaces — "house" with
  the general modules, "display" for the system monitor (the monitor tab should
  LOOK like a monitor; was "gauge"), and "clock" for the time-management pair
  `["tracker", "todos"]`. Modules whose legacy default is hidden start hidden
  on a fresh migrate (currently the torrent module, opt-in
  before its onboarding/banner "enable" — which still activates it). A
  decoded legacy model gets its whole active layout rebuilt into that same
  three-space shape exactly once (`canonicalLayoutSeeded`): space 1 gets
  every other active module, in the order first encountered scanning the
  existing spaces, keeping space 1's current icon; space 2 gets "system"
  alone (icon "display") only if system is active; space 3 gets "tracker"
  then "todos" (icon "clock") only for whichever of the two are shown. Hidden
  flags are untouched — canonicalization only rearranges where modules sit, and
  any space beyond these three dissolves, its modules folded into space 1. This replaced three earlier one-shot seeds
  that each nudged a single module in place (`trackerTabSeeded`,
  `todosSeeded`, `systemTabSeeded`) because patching modules in one at a
  time could still leave them stacked on the wrong space depending on what
  else already occupied it. Existing users' icons/layout are otherwise
  untouched. The rebuild itself is a tested pure transform in HopCore
  (`PanelTabsModel.canonicalized()`); the app layer only guards it behind the
  one-shot flag, resets a dangling `activeSpaceID` and persists.
- **No opt-in for the new modules (1.4.0):** an upgrading 1.3.x user gets the
  new canonical layout IMMEDIATELY on first launch — the tabs rebuild at once and
  the tracker + to-dos are VISIBLE together on the clock space. There is NO
  feature/opt-in banner and no enable/hide question for them; the only
  feature-announcement banner in the app is the torrent module's own (its opt-in
  mechanics are unchanged). The user's existing off-states are preserved: any
  module hidden before the update (a monitor they turned off, torrent before
  its opt-in, anything the old bucket held) stays hidden after — only the new
  modules and the tab restructure appear automatically.
- Module-visibility migration: the old `show*Module` toggles are read once
  and every OFF module is hidden, after which visibility is the `hidden` flag
  and the toggles are never read again. The
  fresh-migrate path applies this deterministically on every recompute (so a
  module never flickers visible while `panelTabsRaw` catches up) and claims
  the `moduleVisibilityMigrated` flag; a decoded legacy model runs it once,
  behind the flag, so a later re-activation is not undone. Onboarding offers a
  per-module toggle for every module — timer, awake, clipboard, converter,
  window manager, the system monitor, the time tracker, to-dos and torrents
  (transient `@State`, not the dead `show*Module` keys) — and applies the
  choices straight to the spaces model (`activateStoredModule`/
  `deactivateStoredModule`): an enabled module stays on the canonical space the
  launch-time fresh migrate already placed it on, a disabled one is hidden
  where it stands. Because the fresh migrate always lays down all three
  canonical spaces, turning the monitor / tracker / to-dos off can empty space
  2 or 3, so `dropEmptyOnboardingSpaces` runs once right after and removes any
  space left empty (except space 1, which always stays — the speed test has no
  onboarding toggle, so it is never truly empty); the fresh install therefore
  never opens onto a blank tab. Opening a `.torrent` file or magnet link
  reactivates the torrent module the same way.
- Onboarding's module choices: ONE 3-column grid holding every module switch —
  fifteen of them, five even rows — in a 560pt-wide window (Anton, 2026-07-29;
  it was 300pt with four modules as full-width rows and the rest as a cramped
  grid of switch-above-name cells). Each cell is a name on the LEFT and the
  switch on the RIGHT, the same shape as the rows above it. Only the choices
  that are not modules stay full width, and in this order: language, theme,
  launch at login, timer format. Launch-at-login used to sit directly on top of
  the grid, where a wide row in a bigger type size read as a first column of it;
  the timer-format cards now stand between the two. Names are nouns, wrap to two lines, and their cells are TOP-aligned so a
  two-line name cannot lift its switch above its neighbours'. The torrent
  engine-size note sits under the grid and now names torrents, since it no longer
  stands beside them.
- EVERY switch starts ON, including the eyedropper, recognition, VPN and a grid
  of apps (Anton, 2026-07-29): the first screen should hand over a whole app, and
  a module nobody wants is one switch away in the same form. A grid of apps is
  the only choice with nothing to switch on — the module exists only once a grid
  does — so choosing it CREATES the first grid (empty, saying so) and places it.
- Onboarding marks EVERY what's-new announcement as seen (`featureAnnouncementIDs`),
  not a hardcoded pair. A fresh install has just answered the module question by
  name in the form, and a card in the panel asking it again is the app not
  listening; that is exactly what a newly added announcement did until this
  (Anton, 2026-07-29).
- The module grid is TWO columns, not three. At three, the gap between a switch
  and the next column's name was smaller than the gap to its own name, so the
  switch read as belonging to the wrong row.
- Settings tab order: general → modules & tabs → timer → monitor →
  remaining modules. "Remaining modules" = awake/clipboard/tracker/to-dos/converter
  as sections with headers (torrent sits at the end of the same tab). The tracker
  and to-do sections each carry a single `visible rows` row (`VisibleRowsField`:
  a numeric 3…15, default 10 — see 8.21). The window-snap block (layout picker,
  "resize windows with hotkeys" toggle, its ⌃⌥-key grid) is the LAST section on
  this tab (`windowsSettings`, after torrent) — Anton moved it here on 2026-07-21,
  reversing the 2026-07-19 move into "general": general keeps only the global
  hotkeys. The block is verbatim, including the toggle's `refreshSnapHotkeys()`
  re-registration hook.
- Torrent speed limit (8.22): the down/up limit fields (`RateLimitField`) share
  one `KB/s | MB/s` unit toggle (segmented, like the window-layout picker). The
  stored value is ALWAYS canonical KB/s (`torrentRateDownKBps`/`…Up`; 0 =
  unlimited) — the unit (`torrentRateUnit`, one shared preference) only changes
  the display: toggling reformats both fields in place, no migration. KB mode
  accepts up to 6 digits; MB mode up to 4 integer digits + one optional decimal
  (1 MB = 1000 KB, the module's decimal convention, matching the card's speed
  readout). Conversion/parse/clamp is `HopCore.RateLimit` (`RateLimitTests`). To
  make "off" legible, a ZERO value (including one the user just typed) renders in
  the tertiary/placeholder gray so it reads as inactive, while any non-zero value
  uses the normal active text color; a short tertiary caption below the row
  (`torrentRateHint`, "0 — no limit", ×18) spells it out. The semantics are
  unchanged — 0 still means unlimited; this is presentation only.
  "modules & tabs" is the combined space/module table,
  its own top-level section (a nested general/"modules & tabs" sub-tab was
  tried and rejected). The app version is shown next to the "check & update" button.
  The "latest version installed" / "failed" note after a manual check is
  transient: it clears when the settings window closes or after 30 minutes —
  a stale note would deny an update that shipped since.
  Toggles are our own MiniSwitch (the system Toggle doesn't render in
  ImageRenderer).
- Info page: per-module tabs, "term — explanation" style
  (the term is bold up to the " — "). The general-tab footer is three lines in
  ONE identical font (mono 11 — the plain connective text matches the links, so
  line heights don't jump): "open source · version X · GitHub" (GitHub a link);
  the author credit (`aboutFooter`, e.g. "made by Anton Shakirov") — the whole
  credit is itself the link to antonshakirov.com (ru → the Russian site, others
  → /en; there is no separate antonshakirov.com link) — next to the product
  landing link, in the app's language when the landing has it (8 languages),
  otherwise English. A third row is the support contact: "feedback & support ·
  hop@antonshakirov.com · telegram", the address a mailto: link opening the
  user's mail client and "telegram" a link to the support bot
  (https://t.me/HopSupportBot); both labels are proper nouns, not localized
  (like "GitHub"). Below the footer sits the donation block (see "Donation
  block").
- Donation block: the ONLY donation surface in the whole product — the landing
  and README deliberately have none, and nothing else in the app does either. It
  sits below the general-tab footer, set apart in its own faint card (chipBg,
  rounded). The WHOLE card is a single button that opens the donation link — one
  obvious place to click, with the house whole-row hover (a hoverBg lift plus the
  pointing-hand cursor). Inside, left-aligned, a title ROW — a leading filled
  heart (`heart.fill`, `Theme.iconHealth`, the house both-theme health red) then
  a bolder title (`donateTitle`, e.g. "support hop", house lowercase) — over a
  subtitle (`donateBody` — gift-framing, future-impact, e.g. "your support will
  help ship new features and keep making hop better"). The card HStack is
  TOP-aligned so the external-page glyph (`arrow.up.forward.app`, the same one
  the converter and torrent rows use, tertiary tint) rides the TITLE row at the
  top-right, not the card's vertical centre; it signals leaving the app. There is
  no separate action link.
  NO perks or rewards are ever promised (donations are gifts). Link routing
  mirrors the localized-README rule: Russian → https://web.tribute.tg/d/Nvp,
  every other locale → https://web.tribute.tg/d/Nvk. All strings are
  country/currency-neutral; the amount and any currency are Tribute's concern.
  Keys `donateTitle` and `donateBody` are translated across all 22 languages.
- Languages in pickers use the standard order, like system lists:
  alphabetical by NATIVE names, Latin → Cyrillic → CJK (pickerOrder,
  localizedCompare). FINAL per Anton 2026-07-13; the "by English names"
  variant was tried and reverted. "Same as system" sits on top; there is
  search.
- Menu bar: asterisk (brand glyph, 8 rays); on the right — a bottom badge and
  a yellow awake dot (top); on finish — a blinking bell; the countdown is
  monospaced and can be disabled in settings. The bottom badge is the timer's
  play/pause when the timer claims it; otherwise, while a task is tracking, a
  hand-drawn monochrome stopwatch badge sits there. With the countdown on
  (default) the digits are in the title and the stopwatch badge in the corner,
  so both show at once; the badge never changes the status-item width.
- **The panel is keyboard-transparent** (Anton, 2026-07-13; completed
  2026-07-15): it never steals keyboard focus — on open AND after any
  click inside it, focus goes back to the app underneath (dictation and
  Cmd+V land there). The panel is mouse-only, with four exceptions that
  do capture the keyboard: digit entry into the timer display (while a
  digit group is selected), the clipboard search field, a focused
  tracker inline field (a task name or a total-time edit), and a
  focused to-do field. The
  timer itself starts/stops ONLY via its on-screen play button — Return and
  Space do NOT toggle it (Anton, 2026-07-19). `handleKey` handles only digit
  entry, Delete (backspace a digit), Escape (deselect the digit group) and
  Return (end digit entry, same as Esc, without starting the timer).
  The tracker and to-do cases also guard the panel's global key handler: while
  such a field is open, Return commits the name/text — it must NOT reach
  `handleKey` and be swallowed by the digit editor. The capture is one flag fed
  by the timer digit editor, the clipboard search field, the tracker field and
  the to-do field (`panelKeyboardCaptured =
  editUnit != nil || trackerEditing || todosEditing || clipboardSearching`).
  When the capture ends
  (Esc/Enter/click elsewhere), focus returns to the app underneath again. Focus moving to another Hop window (settings,
  converter) is legitimate and is not overridden. Global hotkeys work
  regardless of focus.
- Right-click on the icon — a system NSMenu in sentence case:
  DYNAMIC items on top based on active state ("Stop Timer"/
  "Stop Stopwatch" during a countdown, "Turn Off No Sleep" while awake is
  active — they act without opening the panel), then Open / About /
  Settings / Quit.
- Launch at login — SMAppService.mainApp.

## Localization

- 22 languages: en ru de es pt fr it zh ja ko tr uk pl id th vi hi nl
  ar he fa ur — in this order in L10n.swift (th/vi/hi/nl restored
  2026-07-13: old translations from 2042b22 + new keys retranslated;
  ar/he/fa/ur added 2026-07-27 as the first right-to-left set). A new UI
  string = ALL 22 at once; `--l10n-check` must pass. Check long languages
  (de, fr, hi) for truncation.
- Inside the panel — brand lowercase; system surfaces (NSMenu,
  notifications) — sentence case (.capitalizedFirst). Arabic, Hebrew,
  Persian and Urdu have no letter case, so the rule is moot there.

### Right to left (ar, he, fa, ur)

- The language is picked in-app, not through the system locale, so SwiftUI
  never learns the direction on its own: `layoutDirection` comes from the
  process locale, which stays left-to-right. Every window, panel and
  popover root therefore calls `hopLayoutDirection()` (LayoutDirection.swift),
  which reads the setting through `@AppStorage` and flips live. AppKit
  surfaces do not see that environment — the right-click menus set
  `applyHopLayoutDirection()` separately.
- `Theme.mono` drops the monospaced design for these languages and returns
  the proportional system face with monospaced digits. A fixed-width cell
  per glyph pulls a cursive script apart; digits still hold their column,
  so the timer does not jitter. Urdu renders in SF Arabic (naskh), which
  is what every system app on macOS does — nastaliq is not a system face.
- Directional glyphs use the direction-aware SF Symbols (`chevron.backward`,
  `chevron.forward`), never `chevron.left`/`chevron.right`. The tab
  disclosure chevron rotates the opposite way in RTL, since the chevron
  itself has already flipped.
- Canvas drawings do NOT mirror: the dot-matrix digits, the monitor graphs
  and the window-snap glyphs keep their geometry, which is correct — a snap
  glyph is a map of the physical screen, and the left half stays on the
  left. Only the order of the buttons in the row follows the writing
  direction.
- Values substituted into a translated sentence (a file name, "5.1 GB", a
  version number) go through `L10n.fill`, which wraps them in Unicode
  isolates. Without that the sentence drags neighbouring punctuation to the
  wrong end of the value.
- The menu-bar icon is NOT mirrored: the bar itself stays in the system's
  direction, and the badge corners are documented positions, not text.

- Copy style: lively, no officialese and no literalism ("the Mac keeps
  counting" — bad; "lets you close the lid without shutting the Mac
  down" — good).

## Intel Macs (universal build)

- Everything shipped is a UNIVERSAL binary (`swift build --arch arm64 --arch
  x86_64`, taken from `.build/apple/Products/<Config>/Hop`). An arm64-only build
  does not launch on an Intel Mac at all — Rosetta translates the other way — and
  that is the ONLY reason Hop did not run there: the whole tree compiles for
  x86_64 unchanged. A `--dev` bundle stays single-architecture, since doubling
  the wait to look at a change buys nothing.
- **Shipped as two single-architecture builds, not one universal bundle.** The
  universal binary is built once and `lipo`-thinned into `dist/arm64/Hop.app` and
  `dist/x86_64/Hop.app`, each re-signed, each with its own zip and DMG. Both stay
  15 MB — the size Hop has always been — instead of one 29 MB download carrying a
  slice the machine cannot run (Anton, 2026-07-29). Both bundled helpers (the
  torrent engine, the 7-Zip archiver) have been universal all along.
- `latest.json` carries `zip`/`sig` (arm64, the historical names, so every client
  from before 1.7.0 keeps updating) plus `zipIntel`/`sigIntel`. The updater picks
  by the RUNNING process's architecture (`#if arch(x86_64)`), not by the
  hardware, and falls back to the plain pair when the Intel keys are missing.
- The landing offers the two downloads as TWO BUTTONS side by side — the white
  one is Apple Silicon, the outlined one Intel (Anton, 2026-07-29, after the
  Intel build was tested on real hardware). Both ship in every release and update
  through the same manifest; the processor is the only thing that tells them
  apart, so neither is a footnote. They COUNT TOGETHER: one Metrika goal
  (`hop_download`) with the architecture as a parameter. The install counter
  is unaffected either way: it counts update pings, which carry the version and
  nothing else.
- `Casks/hop.rb` in the tap gains its `on_arm` / `on_intel` pair from
  `release.sh`, which REGENERATES that whole head — version and both blocks — out
  of the images it has just built and hashed. Never patched line by line and
  never `sha256 :no_check`: a checksum that is not the file's is worse than no
  Intel block at all, since Homebrew then accepts whatever the URL serves, while
  a missing block simply refuses to install on Intel. Until the first release
  that ships an Intel image, the cask keeps its single pinned build. The tap had
  also silently sat at 1.5.1 while 1.6.0 was already downloading from the site,
  which is why the version is written here rather than by hand.
- **Temperatures** are the one thing that reads differently. Apple Silicon
  publishes sensors through `IOHIDEventSystemClient`; an Intel Mac publishes none
  there and keeps its thermometers behind the SMC. `SMCTemperatureReader` is a
  read-only client for it (open `AppleSMC`, ask a key's type and size, decode
  `sp78` / `flt` / `ui8`), and `TemperatureReader` picks the source by ASKING:
  HID first, SMC only when HID returns nothing. Not by architecture — a Mac that
  answers through neither then reads nil instead of taking a branch that cannot
  work. Verified on Apple Silicon, where the SMC path also answers for the keys
  that exist there (`TH0x`, `TB0T`, `Ts0P`), which is what proves the struct
  layout and the decoding are right.
- The rule for anything else that turns out to be Apple-Silicon-only: replace it
  where there is a replacement, and otherwise do not offer it on that Mac at all
  (Anton, 2026-07-29) — a row that can never have a value is worse than a row
  that is not there.
- `Hop --sensors` dumps both sources, each line labelled `hid` or `smc`. On an
  unfamiliar Mac the question is always which thermometer answered.

### Uninstaller (1.7.0)

Removes an app AND the dozen places it leaves things behind. A row in the panel
opens its own window, the way the converter and the archives do; apps arrive by
drag-and-drop onto that window or through a "+" that opens Finder.

- **It LISTS folders and matches entries, it does not guess paths.** The first
  cut built exact paths from the bundle identifier and found two of Telegram's ten
  traces — 2 GB of 28 GB — because the rest are shaped differently:
  `Containers/<id>.<extension>` for a share extension,
  `Group Containers/<TEAMID>.<id>`, `Application Scripts/<id>`,
  `Caches/<id>.ShipIt` for a Squirrel updater (measured 2026-07-30). The folders
  scanned are `~/Library/{Application Support, Caches, Preferences, Containers,
  Group Containers, Application Scripts, Saved Application State, HTTPStorages,
  WebKit, Logs, Cookies, LaunchAgents}` and — behind one admin prompt —
  `/Library/{Application Support, Preferences, LaunchAgents, LaunchDaemons,
  PrivilegedHelperTools}`.
- **An entry matches on a DOT boundary**: equal to the id, `id.`-prefixed,
  `.id`-suffixed (a team prefix), or `.id.` inside. That is what catches the four
  real shapes above while `com.acme.notesuite` is never swept up with
  `com.acme.notes`. File types (`.plist`, `.savedState`, `.binarycookies`) come off
  before comparing.
- **Three grades of match, and only two are ticked.** The identifier and the app's
  EXACT name are ticked — an app's `Application Support/<its name>` is where its
  gigabytes live, and leaving it unticked made the default run a half-uninstall. A
  name PREFIX (`Telegram Desktop` for `Telegram`) is listed unticked: often the
  same app, sometimes another one. A VENDOR folder (`Application Support/Google`
  when removing Chrome) is never ticked and always labelled — removing it takes
  Drive's data too, which is the classic uninstaller bug.
- launchd folders are stricter: only a `.plist` whose label matches the identifier
  counts, since a label is not a display name.
- **Everything goes to the TRASH, never `rm`.** The action stays reversible until
  the user empties it, which is the difference between a tool and a story about a
  tool. `FileManager.trashItem` for user-level items; the admin sweep moves its
  files into `~/.Trash` in ONE authorised step rather than deleting them.
- **The app is quit first** (`NSRunningApplication.terminate()`), and its launch
  agents are booted out (`launchctl bootout`) before their plists move — otherwise
  launchd writes them back a second later. An app that refuses to quit stops the
  run with that reason, rather than half-removing it.
- **Also scanned, found by checking a real disk** (2026-07-30):
  `Preferences/ByHost/<id>.<hardware uuid>.plist` — the reason a reinstalled app
  remembers a setting nobody expected; `Autosave Information`;
  `Logs/DiagnosticReports/<Name>_*.ips` crash reports; `/Users/Shared/<Name>`;
  `/Library/Caches`; and `/var/db/receipts/<id>.{bom,plist}`.
- **Receipts are REMOVED, not excused.** They were listed as an unremovable
  remainder until Anton asked why (2026-07-30) — and there was no reason: they are
  ordinary files behind the same admin prompt as the rest.
- **The report says what genuinely stays**, and only that: the Spotlight index (a
  database macOS maintains — it forgets a deleted file by itself in seconds, and
  `mdutil -E` would re-index the whole disk for hours to achieve nothing), unified
  logging's ring buffers (crash reports ARE per-app and are removed; the rest
  cannot be picked apart), keychain items (removable through the Security
  framework, deliberately not touched: the match is on a service name the app
  chose, and a wrong guess costs somebody a password), and system/network
  extensions with VPN profiles (the system unloads those through its own prompt).
  Claiming "not a single trace left" without that list is the lie the category is
  known for.
- The matching rules live in `HopCore.AppUninstall` and are unit-tested: the
  scanning and trashing is a thin AppKit layer over pure decisions.

### Two jobs, named in the panel

The module's row is TWO buttons — "remove the app" and "clear the cache" — each
opening the window straight into that job. One row that opened a window with tabs
inside meant you could not tell what you were about to do until it was open
(Anton, 2026-07-30). The window's title follows the job. The second is named
after what it mostly does rather than after the whole screen: "clean up" said
nothing about what would be cleaned, and the caches are why anybody opens it
(Anton, 2026-07-30).

- **Remove the app**: the drop plate AND a list of every app in /Applications and
  ~/Applications, so removing one is a click, not only a drag. The whole screen
  is ONE scroll — the plate scrolls up with the list rather than sitting above a
  list that scrolls inside it — and the window opens tall for it.
  - **Every app carries its size**, as a total with its NAMED parts beside it:
    `1.4 GB (1.2 GB app + 200 MB data)` — the bundle plus everything of its
    elsewhere. The second word is "data", never "cache": it counts application
    support, the container, preferences, logs and the cache together, and calling
    that lot a cache would make removing it sound harmless (Anton, 2026-07-30),
    because "how much do I get back" and "how much of that is the app" are two
    questions (Anton, 2026-07-30). Weighed AFTER the list is on screen, one app
    at a time, off the main thread: adding up /Applications on a Mac with a
    design suite takes seconds, and a list nobody can see yet is not worth
    waiting for. Until an app is weighed its row shows its identifier.
  - **Sorted by name or by size** (`uninstallAppSort`, remembered). A list of a
    hundred apps only answers "what should go" when the big ones can come first.
- **Clear the cache** is one screen with five sections, because they are one
  intention:
  - **caches by app**, built from the cache FOLDERS rather than the list of apps,
    so an identifier whose app is gone still shows up. The section heading says
    what the rows are, and the row itself carries only a name and a size: the
    same sentence repeated under every row was noise (Anton, 2026-07-31).
    Apple's own caches are skipped and anything under a megabyte is noise. Four
    places are read, not one: `~/Library/Caches/<id>`, a container's
    `Data/Library/Caches`, a group container's own `Library/Caches`, and the
    same folder one level inside a group container — sandboxed apps put their
    cache in whichever of those their own layout uses.
  - **installers** — folded in here rather than being a screen of its own, which is
    one screen too many for something this obvious (Anton, 2026-07-30).
  - **leftovers of apps long gone** — found automatically, which is the whole
    point: nobody remembers what they uninstalled two years ago. An identifier is
    a leftover when no installed app answers to it AND no installed app OWNS it —
    a dot-anchored prefix either way, because `com.foo.App.Updater` looks orphaned
    while its owner sits in /Applications. Five more guards keep live apps out,
    every one of them written after a real list on Anton's Mac offered eight rows
    of which seven belonged to something installed (2026-07-31):
    - **The container wrapper comes off first.** A group container is called
      `group.com.foo.App` (Podcasts writes `groups.`, with an s) and belongs to
      `com.foo.App`. Matching the raw name made Apple's own containers look
      orphaned and offered the rules file of an installed ad blocker.
    - **The same vendor is not a leftover.** `com.google.GoogleUpdater` is what
      keeps an installed Chrome up to date, and `com.openai.chat` is what an
      installed app wrote before it changed its identifier. Two shared
      components of an identifier count as one vendor. This hides a genuine
      leftover whose vendor still has something installed, and that is the trade:
      a leftover left alone costs disk space, a live app's data costs the work
      in it.
    - **Apps one folder deep count as installed.** `/Applications` is not flat:
      Adobe installs into `/Applications/Adobe Premiere Pro 2026/` and DaVinci
      Resolve into a folder of its own, and reading only the top level marked
      every one of them as uninstalled.
    - **macOS under its historic names** — Shortcuts still writes as
      `is.workflow`, the TV app as `tvappservices`, Game Center as
      `games.my.gcshowcase`, and Apple's own team identifier prefixes the
      containers it ships. None of them answer to `com.apple` and none has an app
      to vouch for them.
    - **A job launchd is running has an owner** whatever the dates say. Chrome's
      updater writes rarely enough to look abandoned while its agent sits in
      `launchctl list`.

    Nothing written to in the last 30 days is offered: something is still using
    it. The 30 days belong to the identifier and not to the folder — ChatGPT's
    preferences were three weeks old while its `HTTPStorages` folder had not been
    touched since May, and testing each folder on its own offered half of a live
    app's data. Every place one identifier was found is weighed and removed
    together.
  - **big app data we do not touch** — a list with no tick and no button, only a
    name and a size. It answers the question the cache list provokes: Telegram
    holds 23 GB and never appears among the caches, because its `Library/Caches`
    is EMPTY — the media sits in its own database inside the group container,
    cache and account data in one folder. Anything over a gigabyte in a container
    or group container is named here, with the note that only the app's own
    cleanup knows which half is disposable (Anton, 2026-07-30).
  - **the trash**, with its size and the one irreversible button in the module.
    The note under it explaining that much was dropped (Anton, 2026-07-31): the
    button is red, it says "empty the trash", and a line of small print under
    every section is what makes a window tiring to read.

  Every section with ticks carries **one tick for the whole section**, at the
  BOTTOM LEFT: a list of forty apps holding a cache is a list nobody ticks forty
  times (Anton, 2026-07-30), and the second click clears the lot again. Its box
  sits in the same column as every other box in the list and on the same line as
  the button it feeds; at the top right it was a stray control above the ticks it
  belonged to. Sections are 28pt apart, because a section ending in a button and
  the next one opening with a tick read as one row at 16.

  **The window opens before the scan does.** Walking every cache folder, every
  container and the trash, adding up sizes as it goes, takes seconds on a full
  Mac — and doing that first meant clicking the button and staring at nothing
  (Anton, 2026-07-30). The walk runs off the main thread and each list lands as
  it is ready: installers first because they are instant, then caches, the trash,
  the leftovers, and the containers last because they are the slowest thing here.
  A line at the top says the disk is still being read, and no section claims to
  be empty until it has actually been looked at.

### A release's first screen

- **Onboarding lists EVERY module, the uninstaller included**, and marks every
  what's-new announcement seen on the way out: a fresh install has just been
  asked about all of them by name, so greeting it with a card offering the same
  modules asks a question it already answered (Anton, 2026-07-29, restated
  2026-07-30).
- **Someone who UPDATES gets the card instead.** 1.7.0 announces `modules170`
  with the uninstaller in it, and the module ships hidden until it is ticked
  there — nothing appears in a panel that was not asked for.
- The one-shot that hides a new module is keyed PER
  RELEASE (`optInModulesSeeded170`). The original key was claimed in 1.5.0, so
  reusing it would have let 1.7.0's module land in everyone's panel unasked.
- `--feature-banner-latest` renders whatever the newest card is, so it can be
  reviewed without knowing its id.
- **A release also gets a card that only tells** (`newsBanner`, `--news-banner`,
  Anton 2026-08-30). The announcement above asks whether to switch new MODULES
  on, so a release that only deepened the modules already there announced itself
  nowhere: 1.9.0 brought projects and history to the tracker, platform presets to
  the converter, mkv and webm, and the iWork batches, and the only place that
  said so was the "what's new" text, behind a window nobody opens. The card
  sits on the same chrome surface, headed `new · Hop <release>` (the version is a
  literal, never translated), and carries a line per thing the release brought,
  ×22. `what's new` opens the settings window ON its about page — the full notes
  are already written and already translated, so the card summarises rather than
  repeats; `got it` only dismisses. Reaching a particular page needed
  `settingsSectionRequest` on the model, consumed once by the window, because the
  window remembers the page it was left on.

  **A card's lines name what improved, never by how much** (Anton, 2026-08-30).
  The first cut of the vpn line read "changes colour at once instead of half a
  minute later", which advertises how bad the old behaviour was and invites the
  reader to ask why it was ever built that way. It says the connection's state
  syncs faster and the dot follows it, and no release card quotes a before-figure
  again.

  **A card is WRITTEN per release, not derived from the version.** That is what
  makes "only the second number earns a card" true without a rule in the code: a
  fix rolled out on top of a release simply gets no card, so there is nothing to
  suppress, and `ReleaseNews.Version` parses the third number only to drop it —
  1.9.1 is still the 1.9 card. `HopCore.ReleaseNews` (`ReleaseNewsTests`) picks
  the NEWEST card at or below the running version, never a queue of them:
  somebody who skipped a release wants to know where the app stands, not to
  dismiss its history one card at a time. The ones it passes over are `overtaken`
  and marked seen so they cannot surface later.

  **It leaves on whichever limit runs out first:** the button, two panel openings
  that drew it, or two days from the first one that did. The two-day clock exists
  for somebody who neither reads nor dismisses it, who would otherwise carry the
  card at the top of the panel for the rest of the release. A showing is counted
  on the way OUT rather than in, because counting on the way in can push the card
  past its limit while it is still on screen, and a banner that vanishes mid-read
  is worse than one shown once too often.

  The 1.9 card ships in 1.9.1 and reaches EVERYONE, including people already on
  1.9.0: a banner can only travel by update, and nobody has seen this one
  (Anton, 2026-08-30). It never greets a fresh install — onboarding marks the
  release cards seen alongside the announcements (`releaseCardIDs`). It also
  never shares the panel with a module announcement: that one asks a question and
  this one only tells, so the question goes first and the news waits for the next
  open.

### Tooltips

- **Every control that does something says what it does, on hover.** Icon-only
  controls are unreadable without it, and a label that truncates is only half a
  sentence — so the settings switches carry one too (Anton, 2026-07-30).
- The shared controls take it as a parameter rather than leaving it to each call
  site: `HoverIconButton`, `HoverDeleteX` and `NumericField` all accept `help`,
  and `switchSetting` attaches the row's own label.
- **A tooltip follows the STATE, not only the control.** The transport says
  "start", "pause" or "resume" depending on what the next press does; reset says
  the time it returns to; the stash button says the time it brings back; ±5 says
  which way it goes; and the digits say how they are edited AND what they read
  right now — a time set by dragging or typing has to be as legible on hover as a
  preset is (Anton, 2026-07-30).
- **A tooltip says what THIS control does, with its own numbers in it.** A
  preset reads "set the timer to 90 min", a cycle template "work 25 min, rest 5
  min, 4 rounds", a keep-awake or keyboard-lock chip "lock the keyboard for 15
  min" — and ∞ gets a sentence of its own ("until you stop it"). A generic "a
  preset" tooltip on a row of bare figures explains nothing (Anton, 2026-07-30).
- **They appear after one second** (`NSInitialToolTipDelay`, registered at
  launch). The system's own couple of seconds arrives after the pointer has moved
  on; a third of a second fires while the pointer is only passing through, which
  reads as twitchy — Anton tried both (2026-07-30).

### Uninstaller: the other two modes

- **Clear the cache, keep the app.** Only folders macOS itself calls a cache —
  `~/Library/Caches/<id>` and `Containers/<id>/Data/Library/Caches` — because the
  system may empty those at any moment, so an app that cannot survive it is
  already broken. A container or GROUP container is never cleared from outside: it
  holds the cache AND the data in one folder (Telegram's is 25 GB of media cache
  mixed with the account database, and removing it logs somebody out). Those are
  listed with their size and the note that only the app's own cleanup can go in
  there.
- **Installers** (`HopCore.InstallerFiles`): `.dmg`, `.pkg`, `.mpkg` at the TOP
  level of Downloads, Desktop and Documents. Deliberately narrow — an `.iso` may be
  a film and a `.zip` may be a year of work — and NOTHING is ticked by default: an
  installer on disk is somebody's choice, and a tool that pre-ticks them all
  eventually deletes the one that mattered. Size and date are shown so the person
  can decide.
- **The identifier is recovered when the app is already gone.** Most people drag
  the app to the Trash first, and without its Info.plist only name matches work: a
  run then found 13 traces where 22 were waiting (measured 2026-07-30). Two ways
  back — the bundle sitting in `~/.Trash/<Name>.app`, and the leftovers that spell
  the id out themselves (`ru.keepcoder.Telegram.plist` ends with the app's name;
  separators and case are ignored, so `com.x.hop-uninstall-test` matches "Hop
  Uninstall Test"). If two entries imply DIFFERENT ids, nothing is inferred: two
  apps sharing a name is exactly when guessing removes a stranger's data.
- **The cache Hop already made is thrown away once.** Setting the shared cache to
  zero stops new files; it does not remove the ones a previous version wrote. So
  the first launch of a build carrying this deletes `Cache.db`, its `-shm`/`-wal`
  and `fsCachedData` from Hop's own cache folder and records that it did
  (`httpCacheDropped`). Our own folder, so nothing is asked of anybody — "we keep
  no cache" has to mean the same thing for an update as for a fresh install
  (Anton, 2026-07-30).
- **Hop keeps no HTTP cache of its own.** It never asked for one: macOS hands
  every app a URL cache, and Hop's few downloads — the update check, the speed
  test, the 7-Zip helper — left megabytes of write-ahead log in
  `~/Library/Caches/<id>/Cache.db` that nothing ever reads again. Anton found Hop
  in its own cache list and asked what could possibly be in there (2026-07-30);
  the honest answer was "nothing of yours, and nothing we use". `URLCache.shared`
  is set to zero on both memory and disk at launch: a one-shot download gains
  nothing from being cached, and a speed test served from a cache would measure
  the wrong thing.
- **Containers, autosaved data and cookies need Full Disk Access.** macOS refuses
  even `mv` on them, so they are reported apart from real failures, with a button
  that opens the right pane of System Settings. Without it the score stops at 28
  of 31 seeded traces; with it, at 31.

### Measured against CleanMyMac (2026-07-30)

On the same fixture app, seeded with 31 traces: CleanMyMac removed 9 (the bundle,
Application Support by id and by name, Caches including the `.ShipIt` one,
Preferences, Saved Application State, Logs, one CrashReporter report) and left 22 —
containers, group container, Application Scripts, HTTPStorages, WebKit, ByHost
preferences, the launch agent, the DiagnosticReports crash log, autosaved data and
all eleven plug-in locations. Hop's scan finds 30 of the 30 seedable ones and moves
28 of them (the three protected paths need Full Disk Access). Caveat kept
deliberately: the fixture was never launched or registered, so a tool leaning on
its own database of known apps may do better on real software than it did here.

### The converter and the archives in one row (setting)

- Both are the same shape of thing — a row that opens a window and takes files —
  and on a crowded space they cost two lines for very little. `toolsOneRow` (off
  by default) draws them as ONE row split in equal parts.
- **The uninstaller is NOT part of it.** Its row is already two named buttons
  ("remove the app", "clear the cache"), so folding it in would either drop one of
  them or crowd four things into a line built for two (Anton, 2026-07-30). It
  keeps its own row whatever this setting says.
- Each part is an icon and a SINGLE word ("converter", "archives"). The full names
  do not fit side by side on a 340pt row in any language, least of all in German;
  they stay in the tooltip and in settings.
- The row is drawn where the FIRST of the two sits in that space's order, and the
  other drops out of the drawn list. Nothing is stored: the spaces model keeps
  holding the real module keys, so switching the setting back changes nothing
  else, and a space with only one of them shows that one as a normal module row.
- The collapsed row has no "move to / hide" context menu: it stands for two
  modules at once, so the menu would be lying about what it moves.

### Scoring the uninstaller (`scripts/make-uninstall-target.sh`)

- Creates a harmless app in /Applications (`Hop Uninstall Test`, its executable a
  shell script that exits) and seeds a file in EVERY place the uninstaller
  scans — 31 user-level ones, plus 14 system-level ones with `--system`.
- `--check` prints what is still on disk and the score. That is the referee for
  comparing tools: seed, let ANY uninstaller remove the app, then `--check`
  reports exactly which of the known traces survived. Neither tool's own report is
  trusted, and reading the other tool's UI is not needed (Anton's question, 2026-07-30:
  otherwise we could never learn what a competitor erases and we do not).
- Two folders cannot be seeded or read without Full Disk Access
  (`~/Library/Cookies`, `~/Library/Autosave Information`); the script names them
  and leaves them out of the score instead of dying halfway.
- Hop finds 30 of the 30 seedable user-level traces (measured 2026-07-30). The
  gaps that measurement itself exposed — `.wdgt`, `.colorPicker` and `.app`
  bundle suffixes — were fixed the same day.

## Tooltips

- Every ICON-ONLY control carries a tooltip naming what it does (Anton,
  2026-07-29): the header trio, copy and paste in the clipboard, its expand and
  clear-search icons, the note mark on a to-do, the tracker's play and stop, the
  timer's presets, ±5, restore, play/pause and mode toggle, the ten-plus window
  zones by name, keep-awake durations, the speed test's rerun, a colour row's
  three notations, the torrent rows (fold, folder, pause, remove), a grid icon's
  ✕ and the archive queue's ✕.
- Controls that already carry a VISIBLE label do not get one. A tooltip
  repeating the word under the cursor is noise, and it trains people to ignore
  the ones that say something.
- Zone names live in L10n like any other string (`tipSnap*`), so the window
  layouts finally have names in all 22 languages instead of being glyphs only.

## Architecture and build

- `HopCore` (library, no UI): TimerEngine — a finite state machine
  idle/running/paused/finished + cycles + stash + stopwatch; TimeFormatting.
  Timer logic lives only here and only with tests.
- `Hop` (executable): SwiftUI panel, 5×7 dot font on Canvas,
  settings in UserDefaults, signals (NSSound Glass + UNUserNotificationCenter,
  notifications only work from the .app bundle).
- **One list of modules** — `HopCore.ModuleCatalog`: identity, whether a module
  ships hidden, and what it can be asked to do. The hotkey manager reads it
  instead of spelling the sixteen modules out a second time. A module carries an
  "open" action only where pressing a key SHOWS something without the panel — a
  window of its own (converter, archives, uninstaller) or a change on screen
  (eyedropper, text recognition, keyboard lock), plus the timer and no-sleep
  (Anton, 2026-09-01). The clipboard, the monitor, the tracker, the to-dos and
  the rest are read IN the panel, which has a key of its own, so a second key
  would only open the same panel. The storage keys of the six actions that had
  one (`hotkey_panel`, `hotkey_timer`, `hotkey_awake`, `hotkey_color`,
  `hotkey_ocr`, `hotkey_keyboardLock`) never change — saved combinations hang on
  them; the three window actions ship with no combination, because claiming
  global shortcuts on somebody's behalf is rude.
- **Which combination may be claimed** — `HopCore.HotkeyActivation.registrable`:
  the panel's own always, a module's only while the module is visible, unless
  `hiddenModulesKeepHotkeys` lets hidden modules answer anyway (off by default,
  no UI until the hotkeys page exists). Hidden means what the panel does not
  show: the layout's `hidden` set, the legacy `inactive` bucket it is migrating
  from, and any module sitting on no space at all. `HotkeyManager` claims
  nothing for an action with no handler — a global shortcut that swallows the
  key and does nothing is worse than no shortcut.
- Full cycle after EVERY change: `swift build` (0 warnings) →
  `swift test` → `--l10n-check` → `./scripts/build-app.sh --install`,
  check in both themes.
- **Build times, measured 2026-07-26** (this tree, M-series, cold builds):
  debug 14s · release with `-O` **16m46s** · release with `-Osize` **37s**, and
  the binary is the same 11.6 MB either way. So the app target ships with
  `-Osize` (Package.swift, release only) and HopCore keeps `-O`: at `-O` the
  optimizer hits a pathological case on a 29k-line SwiftUI module and inlines for
  a quarter of an hour to no measurable effect — the work of a menu-bar app
  happens inside AppKit, and Hop's own hot paths are in HopCore. `-Onone` was
  also measured (26s) and rejected: same speed as `-Osize` but a 19 MB binary.
  Whole-module optimization is NOT the culprit: `-no-whole-module-optimization`
  took 17m13s, i.e. no better. Release builds are never incremental in SwiftPM,
  so any one-line change costs the full build — which is exactly why a dev
  install is `--dev` (debug, ~2s) and release builds happen only for a release.
- `--snapshot out.png [--stats|--finished|…]` — renders the panel to PNG;
  Toggle/TextField/onDrop produce artifacts in snapshots — a rendering
  quirk, not a bug. `--window-settings --settings-section <id>` opens any
  settings page (`--news` and `--permissions` are shorthands for two of them),
  so a text change can be checked where it is actually read.
- `--window-uninstall` / `--window-clean` render the uninstaller's two jobs with
  STAGED content: the real lists are this Mac's own apps and this Mac's own disk,
  and a product picture must not be somebody's home folder. A rescan is skipped
  entirely under `Snapshot.active` — it would wipe the staged lists on its way to
  walking that disk.
- `--stats --charts` renders the monitor in chart mode with a SYNTHESIZED
  history (sin-based, deterministic): a live run has two points by render time
  and every card would come out empty. The gpu series is staged too, and the
  gpu ROW is pinned to where its own curve ends — the card appears as soon as
  the Mac reports a load, so on an idle Mac the picture used to show a gpu
  reading with a blank card under it, and a raised curve over a "0%" row is no
  better. The temperature line is staged only where the chip reports one, and
  the monitor does NOT poll under `Snapshot.active`: a refresh would replace the
  staged sample a beat before the render.
- **Lists render in a snapshot through `SnapshotAwareScroll`.** ImageRenderer
  hands a ScrollView an unbounded height, the ScrollView reports nothing back,
  and the picture comes out as a title on black — which is exactly how the first
  render of the clean-up window came out. In a snapshot the rows are laid out
  directly and the caller gives the render its height.
- `--only <module>` leaves ONE module's row on the panel and hides the rest;
  `--overview` does the opposite and shows every module at once, the opt-in
  ones included, with content staged in each (the colour picker draws its
  swatches out of the clipboard history, so the overview seeds a mixed list —
  an empty row in the one picture meant to show the whole app is worse than a
  crowded one). The colours go BELOW the three rows the clipboard shows by
  default: with them on top the shot said "this keeps colours" twice and never
  showed that it also keeps a link, a file and a piece of text (Anton,
  2026-07-30).
- `scripts/make-screens.sh [out-dir] [lang …]` renders the WHOLE product set —
  every README and product-page image, for the eight languages with their own
  folder — into the website repo by default. Every other README points at the
  English folder. The recipes used to live nowhere and each shot was taken by
  hand, so the set drifted out of date module by module and a section about the
  timer carried a picture of the entire app (Anton, 2026-07-28). A section that
  describes one module gets a shot of that module: `--only`. Sample files for
  the converter window are generated inside the script, so its rows carry real
  thumbnails and believable size estimates. After a run, bump `SCREENS_VER` in
  the site's `src/views/hop/config.ts` — the image optimizer caches for 31 days
  and the file names are stable.
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
- DMG window: 640×400, icons at (170, 165) and (470, 165), picture 1280×800
  at 144 dpi drawn by make-dmg-bg.swift in the landing's palette (#0b0b0b,
  accent #ffd60a). Finder draws that picture only when it sits inside
  `.background/` on the volume, the icvp alias points at it, and dmgbuild's
  pBBk bookmark record is gone — each of the three was checked on its own
  against freshly built images. With a picture in place Finder also switches
  both icon labels to dark text whatever the system appearance is, so the
  backdrop carries light pads under "Hop" and "Applications". make-dmg.sh
  asserts the whole layout after building.
- After installing an update the app relaunches itself: a detached shell
  helper waits for the old process to exit and opens the new bundle
  (a plain `open` before terminate only activates the still-running old
  instance — nothing would start the new one, and two live instances
  racing NSWorkspace.setIcon corrupted the Finder icon into a folder).
- Auto-check cadence: 15 s after launch, every hour, and 30 s after
  wake from sleep (the quietest moment — the user is just coming back
  and doesn't rely on the app yet). Only the tiny latest.json is fetched
  on each check; the zip downloads only when a newer version is found.
- Install timing: a found release installs at the first moment the user
  isn't actively using Hop, not at the next hourly check. If the check
  finds a release but the moment is busy, it's remembered and a 60 s
  retry (gate-only, no network) installs it the instant the user goes
  idle. "Not in use" = no interaction for 20 minutes AND no running/paused
  timer, sleep-prevention, open panel, or in-progress conversion.
  Interactions that reset the 20-minute window: opening the panel,
  timer/awake hotkeys, opening a window, running a conversion. A
  critical release skips the 20-minute wait and the awake/panel/converter
  checks — but still never interrupts a set timer. The rule lives in
  HopCore's UpdateInstallPolicy (unit-tested).
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
- The dev build does NOT check for updates automatically — it makes no
  network calls and doesn't trip testers' firewalls; it updates by
  rebuilding. "Dev" is ONE shared rule (`Bundle.isDevBuild`): the bundle id is
  not EXACTLY the production id (`…minimo`). That covers the ".dev" parallel
  app AND any bundle-less run (raw `swift build` binary, `--snapshot` probe:
  nil id), so a bundle-less process can never be mistaken for production and
  auto-update. The same rule drives the menu-bar "D" dev-mark and the
  Finder-icon "D" badge (the icon badge is additionally suppressed under
  `--snapshot`, so marketing renders show the production icon). A
  `.dev`-suffix-only heuristic was wrong: it read a nil-id run as production.
- Releases are signed with Developer ID and notarised by Apple as of 1.9.1, so
  the Gatekeeper warning on a first install is gone — see "Signing,
  notarisation, and why permissions must survive an update".
- Updater: watches the GitHub Release (the repo will be antonshakirov/hop),
  the Ed25519 signature is mandatory, disabled until the public key is
  embedded; a silent hourly check, installs at the first moment the user
  isn't actively using Hop (see the install-timing rule above).

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

## Checks that run themselves

`scripts/checks.sh` is the check cycle in one place — build (warnings count as
failures), `swift test`, and `--l10n-check` — and THREE things call it, so they
cannot drift apart (Anton, 2026-08-29):

- **CI** (`.github/workflows/ci.yml`) on every push and pull request to `main`
  AND `dev`. It used to watch `main` only, which meant the branch all the work
  actually happens on had no automatic checks at all.
- **The local pre-push hook**, so nothing red leaves the machine.
  `HOP_SKIP_CHECKS=1 git push` is the escape hatch for a known-good docs fix.
  Like the other hooks it lives in `.git/hooks` and is restored by hand after a
  re-clone.
- **`release.sh`**, right after it has validated its arguments and found the
  signing key, and before it packages anything: a release that fails its own
  checks is not a release.

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
Reworked 2026-07-15 (Anton): the old "(used+swap)/RAM %" threshold read
as if swap were on top of the shown figure and lied about pressure. Now:
- The row shows RAM used ("18.0 / 24.0 GB") with swap alongside when
  > 50 MB ("swap 4.9 GB") — the figures no longer include each other.
- "Used" matches Activity Monitor's Memory Used, computed the way its bar is
  built: Physical Memory − Cached Files − free, i.e.
  `hw.memsize − ((free_count − speculative) + file-backed) × page`
  (`HopCore.MemoryUsage.usedBytes`). Both subtracted terms were measured
  against a live Activity Monitor reading (2026-07-27, 24 GiB machine, Used
  20.98 GB): Cached Files is `external_page_count` ALONE, and free is
  `free_count` MINUS `speculative_count`, because Mach's `free_count` already
  contains the speculative pages — that is why `vm_stat` prints the two apart.
  This is the additive App Memory + wired + compressed sum PLUS the
  kernel/hardware-reserved pages `host_statistics64` files in no queue — on
  Apple Silicon the GPU/firmware carve-out of unified memory (0.78 GB measured)
  — plus the speculative and purgeable pages Activity Monitor also counts as
  used. Three formulas have been wrong here in turn: an active_count one ran
  ~2 GB under (fixed 2026-07-18), the additive sum ~0.9 GB under (fixed
  2026-07-22), and the first subtractive one deducted purgeable pages as cache
  and speculative pages twice, so it drifted under by however much of each the
  machine held — up to about a gigabyte (fixed 2026-07-27). Subtraction
  degrades cleanly where there is no carve-out (reserved ≈ 0), matching the
  additive sum.
- The COLOR takes the WORSE of two signals (`HopCore.MemoryStrain`), because
  each is blind to what the other sees:
  - macOS's own `kern.memorystatus_vm_pressure_level`: 1 normal (green when
    colorful), 2 warning → yellow, 4 critical → red. It answers "am I
    struggling to hand out pages right now" and nothing else.
  - Swap as a share of physical RAM, against a user threshold
    (`thSwapYellow` / `thSwapRed`, defaults 25 / 50). Pages pushed to disk that
    have stayed cold cost the system nothing, so the pressure level keeps
    reporting normal while a great deal of memory sits in swap: measured on a
    24 GB machine holding 9.4 GB of swap, the level was still 1 (Anton,
    2026-07-28). That is a fact about the machine the user can act on, so the
    row says it.
- Swap is compared to RAM and NOT to the size of the swap file: macOS grows
  that file on demand, so "92% of the file" becomes "46%" the moment it grows
  with nothing about the machine having changed.
- This is NOT a return of the pre-2026-07-15 rule. That one coloured on
  `(used + swap) ÷ RAM` with yellow at 110%: it added a figure that already
  counts compressed memory to a pool living on disk and compared the sum to the
  size of RAM. A "normal" threshold above 100% is the tell that the metric had
  no physical meaning. The keys `thMemYellow` / `thMemRed` are swept, and the
  new ones are named apart so an inherited 110 cannot become "warn when swap
  passes 110% of RAM", which is silence.
- Memory is deliberately NOT part of the menu-bar icon's red zone, as it has
  never been: swap fills over hours rather than spiking, so a badge for it
  would sit there all day and stop meaning anything.

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

## The about page (settings window)

- What the app is has no window of its own any more. The ⓘ button in the panel
  header, the right-click menu's "about" item and a release card's "what's new"
  all open the SETTINGS window on its "about" page
  (`model.settingsSectionRequest`, consumed once by the window, which otherwise
  remembers the page it was left on).
- The page carries the donation card (still the only donation surface in the
  product), the last ~5 releases (`docNews`, ×22) with a link to the full history
  on GitHub Releases, and the footer: version, source, the author's site, the
  product page, support mail and the Telegram bot.
- **The per-module documentation is gone from the app.** It was fourteen tabs of
  text that had to be written, translated ×22 and kept true release after
  release, read by almost nobody, in a window nobody opened. The guide lives on
  the site instead, and every module page links to it with the code of the
  modules that person actually sees (`?m=`, see "Modules"). The site's guide is
  published in 8 languages, so a reader in one of the other 14 gets it in
  English — a step back for them, and the reason to translate the guide page
  next rather than to keep two copies of the same text.

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
  landing redirect) → commit + site deploy → `scripts/verify-release.sh
  X.Y.Z` → `git tag vX.Y.Z` + GitHub release.
- Nothing is announced before the files serve: verify-release.sh downloads
  the LIVE latest.json, the exact zip it points to, checks the 64-byte
  signature file and the bundle version inside the zip, and the landing
  DMG — the tag and the GitHub release are created only after it passes.
  (1.3.1 lesson: Next's public manifest 404s NEW file names until a site
  rebuild; the deploy self-probes changed public paths and rebuilds now.)
- Installation only with a valid Ed25519 signature (the key is embedded
  in the app; the private half is `~/.minimo-release-key`, outside the repo).
- The production `/Applications/Hop.app` is updated ONLY through this
  channel; `build-app.sh --install` without `--dev`/`--prod` refuses
  to install.
- The test build is "Hop Dev.app" (`--install --dev`), living in parallel;
  its icon carries a gold "D" badge in the bottom-right corner so the
  production and test builds can't be confused.
- Install staging (`temporaryDirectory/hop-update-<UUID>`) cannot be
  removed by the process that created it — it terminates right after
  copying the new bundle. Each launch sweeps ALL leftover hop-update-*
  folders instead (they were accumulating ~7 MB per update until macOS's
  periodic temp purge).


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
- Video size estimates come from a real sample encode: the first ~8 s of
  the file go through the actual export preset and the result extrapolates
  by duration ("original" — the source size, container change only).
  Estimates are marked "~" and never exceed the source size.

## Timer: finish sound and calm-down

The finish sound fires EXACTLY ONCE per finish (`engine.onFinish` →
`Alerts.fire` → `Sounds.alarm`). There is no repeat timer — the earlier
3-second `startAlarmRepeat` loop (auto-muted after `alarmRepeatSeconds`) was
the source of the "fires several times" behavior and has been removed, along
with the now-unused `alarmRepeatSeconds` default.

The finished state signals in two phases — an alarm, then a calm reminder — so
it stays obvious the timer needs a reset without the alarm nagging on:

- **Fresh finish — the alarm blink.** The menu-bar bell blinks and the zeroed
  digits blink in the panel (`engine.isFinishBlinking`, true while finished and
  not yet acknowledged). The ticker drives both, and both the bar bell
  (`StatusItemController.refreshButton`) and the panel digits (`AppModel.blinkOn`)
  derive their blink from `engine.isFinishBlinking`.
- **Opening the panel acknowledges the finish** (`presentPopover` →
  `TimerEngine.acknowledgeFinish`): the alarm settles — the menu-bar bell stops
  blinking and holds a steady `bell.fill`, and the finish sound was one-shot
  anyway. The state stays `.finished`. Acknowledgment is idempotent and a no-op
  off the finished state; every fresh finish clears the flag and blinks anew.
- **After acknowledge — the calm pulse.** The bell is gone, but the zeroed
  digits keep a subtle pulse (`engine.isFinishSettled`, i.e. finished AND
  acknowledged) — dimming and returning via `AppModel.finishedPulseOpacity`, a
  gentle "it finished, reset it" reminder rather than a full-disappear blink.
  The ticker keeps running to drive it; the pulse is tick-driven opacity, never
  a `repeatForever` SwiftUI animation (which would break the popover sizing). It
  runs across all three display styles (dots/text/units) and both themes. It does
  NOT touch the menu bar: the bar shows the steady bell and no time text for a
  finished timer, so nothing there pulses.
- **The pulse ends** the instant the finished state ends — a reset, a new start,
  or digit entry (`engine.reset` / `start` / `setDuration`) all stop the ticker
  and exit the `.finished` state.
- **Clicking the finished digits** (full display and compact row) resets the
  timer to the configured duration (`engine.reset`), leaving the finished
  state entirely and ending the pulse. Per-digit-group editing by click becomes
  available from the next click, already in idle.

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
- The windows module page → "resize windows with hotkeys": under the toggle sits
  a legend "zone glyph + ⌃⌥ key", four columns (`snapHotkeyItems`), replacing the
  old cryptic symbols-only caption.
- App icon (Finder/Applications): dark or light chip with the REAL icon
  previews, light is the default; "auto" removed. The row sits after the
  updates section, away from the theme picker (it kept reading as part of
  the theme). setIcon failure rolls the Finder custom-icon flag back —
  a half-written icon rendered the app as a folder.

### Signing, notarisation, and why permissions must survive an update

macOS ties a permission — full disk access above all — to the app's CODE
SIGNATURE. Hop is signed with **Developer ID Application: Anton Shakirov
(8GL36WUJPX)**, and a stable certificate is the whole reason a grant survives an
update: the designated requirement names the certificate, which does not change
between builds. An ad-hoc signature (`codesign --sign -`) pins the requirement to
the build's own hash instead, so every update is a DIFFERENT app to the system
and every user is asked for every permission again (Anton, 2026-07-30).

Developer ID is also the only signature Gatekeeper accepts from outside the App
Store, and only once Apple has NOTARISED the build. Until 1.9.1 releases were
signed with a self-signed local certificate ("Minimo Signing"), which kept
permissions alive but left every first install blocked behind the "cannot be
opened" dialog and the Privacy & Security override.

- One-time cost of the move: the signature changed, so every permission granted
  to the old builds is gone on the machines that update to 1.9.1 — the system
  sees a different app. The release card in the panel says so; nothing else can,
  since the app is not asked before the system decides.
- `signing.sh` holds the identity, the runtime options and the entitlements in
  ONE place, sourced by both scripts, so a build and the release made from it
  cannot drift apart. The certificate is looked up by kind ("Developer ID
  Application"), so a renewal needs no edit.
- The hardened runtime (`--options runtime`) is required by the notary service
  and is on for dev builds too, so anything that only breaks under it surfaces
  while a change is being looked at. It costs one entitlement:
  `com.apple.security.automation.apple-events` in `scripts/Hop.entitlements`,
  without which the iWork export and the lid switch lose their Apple events.
  `NSAppleEventsUsageDescription` accompanies it in `Info.plist` — a process
  that sends an Apple event without one is killed by the system.
- `build-app.sh` signs with that identity and falls back to ad-hoc only for a
  local build with no certificate present.
- `release.sh` proves the certificate, its expiry and the notary credentials
  BEFORE the 25-minute build. It thins the universal build into two bundles,
  which invalidates the signature — so it signs each slice again, submits it,
  staples the ticket into the bundle, and asks `spctl` what the user's Mac will
  decide. Both DMGs are signed, notarised and stapled in turn. A missing
  certificate, a rejected submission or refused credentials all stop the release.
- Notary credentials live in a git-ignored `.env` (`APPLE_ID`, `APPLE_TEAM_ID`,
  `APPLE_APP_PASSWORD` — an app-specific password from appleid.apple.com, never
  the account password). `.env.example` is the template.
- `verify-release.sh` re-checks the SERVED copy: it downloads what `latest.json`
  points to, runs `spctl` over it and validates the stapled ticket, on the app
  and on the landing DMG. A build that is signed but not notarised passes every
  other check and is still blocked on a first install.
- The updater installs with `ditto`, not `copyItem`: it carries a bundle across
  whole, and a bundle that arrives intact keeps both the signature the permission
  hangs on and the stapled ticket.

### Release