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
3. **The menu bar button width AND label presence are frozen** while the
   panel is open (Anton, 2026-07-15). Showing at open → the countdown
   stays visible and ticking, padded with spaces to the frozen length;
   if the digits outgrow the slot (stopwatch passing an hour) the freeze
   extends and the didMove observer re-anchors. A reset while open shows
   the reset value (the configured duration), never a blank slot. Hidden
   at open → a timer started from the panel does NOT surface the label
   until the panel closes; on close the bar reflects reality.
4. **No repeatForever animations** — they trigger NSHostingController
   size recalculation. Icon changes are an opacity crossfade in a
   fixed-size ZStack.
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

## Modules

The main screen shows the modules of the selected space (tab) as a stack,
in the order the user set. **Module visibility is membership**: a module is
shown iff it sits on a space and hidden iff it sits in a permanent,
non-deletable "inactive" bucket. There are NO per-module on/off toggles;
every key lives in exactly one place — a space OR inactive
(`PanelTabsModel.inactive`, an ordered list; HopCore enforces uniqueness
across the union and decodes older JSON that lacks the field as an empty
bucket).

The settings window's top-level text-switcher has five sibling sections, in
order: "general" for the everyday options (theme, language, launch, sounds,
updates, app icon, and the GLOBAL hotkeys only — show panel / timer / no-sleep),
"modules & tabs" for the panel layout, "timer", "monitor", and "other modules"
(which now also carries the window-manager section — the grid/row layout picker
and the "resize windows with hotkeys" toggle/grid, moved out of general on
2026-07-21) — no tab-in-tab, each
is its own top-level section. The switcher chips take their natural width and wrap onto
a second line if a language runs long (`SectionChips(wraps:)`), so the fifth
chip never truncates in the 720pt window. The "modules & tabs" section is
ONE combined table, a single row of columns: the permanent "inactive" storage
column FIRST (a subdued gray fill + dashed border set it apart from the tab
columns' clear fill + solid border, so it reads as a holding area, not a space),
then the space columns in order, then a compact square "+" add-tab tile aligned
to the TOP of its slot while under the space cap (it was a full-height dashed
column before — the stretch was dropped; the revert is a one-liner noted in
`addColumnStub`). Module chips (name, lowercase) stack vertically in EVERY
column, inactive included; a hand-rolled drag moves a chip between columns,
within a column, and into/out of the inactive column — that drag IS the
visibility control (`move`/`deactivate`/`reorder`).
Inactive chips render dimmed. While a chip is dragged, a live insertion
indicator marks exactly where it will land: a 2pt horizontal line with rounded
caps in the shared `Theme.editing` accent (the same yellow/goldenrod token the
timer digit-group highlight uses) between the rows of the target column —
the inactive column shows this line too now, since it stacks like the rest
(top/bottom for first/last, and centred in an empty column); the target column
also tints while hovered. The indicator's position is read from the SAME
resolver that commits the drop (`insertIndex(for:in:at:)` → `SettingsDropGeometry`,
ONE shared stacked resolver for every column), so line and landing can never
disagree. Which column a point falls in is `SettingsDropGeometry.columnID(at:)`
(containment wins, else nearest by X; inactive is a regular column — no
vertical-band special case, no X-nearest exclusion), tested in
`SettingsDropGeometryTests`. Each space column header carries
the space icon (a padded icon+chevron control with breathing room around the
hover highlight — tap it or its rotating disclosure chevron to open the icon
picker), "#N", and a hover-only delete xmark that opens a delete confirmation
(`delete this tab? its modules become inactive` + delete/cancel); confirming
sends the space's modules to the inactive bucket (they are hidden, not merged
into another space). The icon picker is an anchored popover under the header
control (the settings window is a real NSWindow, so a popover is safe here,
unlike the status-bar panel): a scrollable grid, ~7 columns, capped ~320pt
tall, of the curated SF Symbols catalog (`IconCatalog`, 200+ symbols grouped
by theme — home, time, work, media, and so on — with each group set off by
extra vertical spacing rather than a label to avoid a per-group translation;
every name resolves on macOS 14). It dismisses on outside click, Escape, or a
pick, and never reflows the table; a drag in progress cannot open it. The
delete confirmation is an overlay ON the table — a dimmed scrim plus a
centered card — so the columns never reflow beneath it; the scrim tap or
Escape cancels. The inactive column header is just an "inactive" label in the
section-header style — no icon, no delete (no hover affordance at all), and it
cannot be dragged. Dragging a space column header horizontally reorders spaces
(`moveTab`, committed on release against the measured column frames), with a
vertical `Theme.editing` insertion line marking the landing slot while dragging
(read from the same `columnID(at:)` target the move commits to). Column-drag
and chip-drag never fight: the header and the chips are separate grab zones.
The standalone settings window is 720pt wide so the inactive column plus the
space columns and the "+" tile read comfortably across one row; chips truncate
with `lineLimit(1)` in every column. Under the table sits an airy tertiary
caption (`modulesTableHint`, ×18) stating that "inactive" modules never show in
the panel and that both columns (to reorder tabs) and the chips inside them
(between/within columns) are draggable. The in-panel
`.settings` screen is unreachable (never set outside `init`, which always
pairs it with the standalone window), so the table is designed for that
window only. A module can also be re-homed from the panel: right-click it and
pick a target under "move to" — one item per other space plus a final
"inactive" destination that hides it (the menu is never empty). A hidden
module is simply not rendered, so there is no inverse "activate" context menu
— reactivation is a drag out of inactive in settings. The divider between
modules sits exactly in the middle: top inset = bottom inset = 16pt.

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
- Finish: signal per setting (sound+banner / sound / silent). The finish
  sound plays EXACTLY ONCE (no repeat). The zeroed digits blink and a bell
  blinks in the menu bar — opening the panel acknowledges it
  (`TimerEngine.acknowledgeFinish`): the bell settles to a steady lit bell, but
  the zeroed digits keep a subtle pulse (`isFinishSettled`) as a "reset me" cue
  until a reset or a new start ends the finished state. Play from finished
  restarts the same duration.
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
  problem. Thresholds are configurable (temperature, load, disk, battery;
  battery semantics are inverted — below the threshold is worse). °C/°F:
  auto by region, can be set explicitly. "Calm" mode is the default:
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
  In chart mode the rows are larger (12pt).
- A red "!" on the left of the menu bar icon during a red zone (same
  thresholds that color the values; a charging battery doesn't count).
  OFF by default, toggle in monitor settings.

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
  works unconditionally and regardless of click-focus — Hop is an accessory app
  with no Edit menu, so there is no Paste key-equivalent to drive SwiftUI's
  `onPasteCommand`; the window itself catches ⌘V (`ConverterWindow`'s
  `performKeyEquivalent`) whenever it is key. `performKeyEquivalent` calls
  `super` FIRST and handles ⌘V only when super returns false, so the responder
  chain (any future editable field) keeps first refusal on paste; with no such
  field today the behavior is unchanged. An empty or text-only clipboard is
  a silent no-op; an unsupported file lands in the "unsupported" group, same as
  a dropped file of that type.
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
- Video: MP4/MOV/M4V → MP4/MOV (original/1080/720/540). Audio: → M4A.
  MP3/MKV/WebM output is not supported by the system; we don't embed ffmpeg.
- Resolution chips at or above the source's short side are hidden — they
  would re-encode at the same frame size and read as a second "squeeze";
  a currently selected chip stays visible so the choice is never invisible.
- Video settings are three independent rows (Anton, 2026-07-15):
  "format: MP4/MOV", "resolution: original / 4K / 1080p / 720p / 540p"
  and a "compression" toggle (HEVC instead of H.264, ON by default,
  available at every resolution). The legacy single "quality" value
  migrates into the pair on first launch ("hevc" → original + compress).
- Downscaling is hop's own videoComposition targeting the SHORT side,
  aspect ratio and orientation preserved — a vertical 1244×1664 at
  "1080p" becomes 1080×1444. The system resolution presets fit into a
  LANDSCAPE box (807×1080 for that source) and were dropped. Never
  upscales; dimensions are rounded to even for the encoders.
- Estimates are honest: images/PDF — a trial conversion of the first file +
  a curve over reference quality points (interpolation, no recompute on
  every slider move); video/audio — the system encoder's forecast. Per-file
  estimates use the sample's compression ratio.
- All converter sizes use decimal units (1 MB = 1,000,000 bytes) — the same
  scale as Finder, so the promised and the delivered numbers match; binary
  MiB read ~5% smaller and made every result look heavier than estimated.
- Each group card carries an honesty note "output size is approximate"
  (convApproxNote) while files are pending; during conversion the card
  shows a whole-batch progress bar (files done + the current video's own
  fraction), a percentage and "converting… i/n".
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

- Time tracker over a FLAT LIST OF TASKS — projects are gone (removed in 8.14;
  an old file that still has them is flattened away on load, see Migration). All
  logic lives in HopCore (`TrackerEngine`, persisted to `tracker.json` via
  `TrackerController`); the view is glue. Labels tick off `tracker.heartbeat`
  (1/s while a task is tracking). Active by default — unlike torrents it has no
  engine to download, so it isn't opt-in; hidden or shown like every other
  module by membership in the "modules & tabs" table (drag it to/from the
  inactive column). The module title (`trackerLabel`) is "time tracker" — it
  names the feature in settings and in the always-on subheader above the list.
- **Flat task list:** `TrackerData.rootOrder` is the single source of the list's
  order — it holds the id of every task, no duplicates; the engine normalizes it
  on load (keep listed ids in order, drop stale ones, append any missing in the
  tasks' array order). A task's `projectID` is a legacy optional kept only for
  backward decode; every live task is a root task (`nil`). `addTask(name:)`
  appends a task to the list and to `rootOrder`; each mutation fires `onChange`
  once, and delete/reorder keep `rootOrder` in sync.
- **Migration (one-shot, on init):** an old `tracker.json` with projects and
  nested tasks is FLATTENED by the engine — every task becomes a root task
  (`projectID` set to nil), a project's tasks expand IN PLACE where the project
  sat in `rootOrder` (internal order preserved), root tasks stay put, and the
  `projects` array empties. A file with no `rootOrder` derives the order from the
  projects' array order (each expanded to its tasks) then any root tasks.
  Intervals, corrections and the open (active) interval are untouched — an active
  task inside a project stays active after the flatten. The `projects` and
  `projectID` Codable fields remain so the old file still decodes; the engine
  never writes a non-empty `projects` array again, and the flatten is idempotent
  once flat.
- **Single active task:** at most one task is ever tracking. Tapping play on
  task B while A runs stops A first — the engine closes the open interval itself
  (`start(taskID:)`), the UI never juggles two. Deleting the active task stops
  tracking (its open interval is dropped with it). `activeIntervalStart` exposes
  the open interval's start so the view can flag a long run (see 8-hour warning).
- **Menu-bar indication:** while a task is tracking, a small hand-drawn
  monochrome stopwatch BADGE is shown in the icon's bottom-right slot — the
  same slot the timer's play/pause badge uses (`MenuBarIcon.drawTrackingBadge`:
  a ~5.4pt stroked circle body with a short crown tick on top, drawn by hand
  because an SF `stopwatch` symbol reads spiky at 7pt). It is monochrome — the
  star's glyph colour (white in dark, 85%-black in light), NOT a system colour
  like the green/orange play/pause badges — so tracking adds no new hue to the
  bar. Crucially it lives on the FIXED 22×17 icon canvas, so tracking has ZERO
  effect on the status-item width and cannot shift the attached panel (this
  replaced an earlier in-title glyph that widened the button — Anton, 2026-07-20).
  **Slot precedence:** the timer's play/pause badge WINS the slot; the badge
  only appears when the countdown digits are HIDDEN, so in the normal config
  (digits on) the countdown sits in the title and the stopwatch badge in the
  corner — both states visible at once. In the rare overlap (countdown digits
  OFF + timer running/paused + a task tracking) the timer badge takes the slot
  and the tracking state is visible only inside the panel; this is deliberate.
  Tracking is a decoration, so it drops out of the plain-template fast path and
  the icon goes through `compose` (same as a badge or awake dot). An opt-in
  `show task time in menu bar` setting (`trackerTimeInBar`, OFF) additionally
  shows the active task's ticking `today` value as the bar title (digits only —
  no glyph), but only when nothing else claimed it — the timer countdown always
  wins. `today(taskID:)` stays in the engine for this figure and for corrections
  math; the panel itself shows the total, not today. The badge toggles
  immediately on start/stop off `tracker.heartbeat`; the opt-in bar time ticks
  1/s. The badge never touches the title, so it plays no part in the
  width-freeze — only the `trackerTimeInBar` digits (a deliberate, opt-in width
  change of the same class as the countdown) ever change the title width.
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
  (`trackerVisibleRows`, "other modules" settings): an ALWAYS-active number 3…15,
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
- **Drag to reorder:** grabbing ANYWHERE on a row reorders the flat list — the
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
  `Snapshot.demoTasks` (a sanctioned per-locale string site, English fallback).

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
  subheader and the `+ new task` footer text start on — ONE control at ONE
  diameter with the tracker's play/stop (`RowCircle.diameter`), so the two line
  up on the same left column when the modules stack on a space. The hover xmark
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
  (`todosVisibleRows`, "other modules" settings): an ALWAYS-active number 3…15,
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
- Registration is by membership like every module (key `"todos"`, title
  `todosLabel`); it captures the keyboard while its field is focused (same
  `onEditingChanged` path as the tracker) so digits don't leak to the timer.
  Fresh installs pair it with the tracker on the "clock" space; existing
  users get it paired with the tracker on the same space by the canonical
  layout repair described under "Default spaces" below.

## Shared components

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
  centering. Corner rounding is the `round` fraction of `box` (0.46 — tuned
  noticeably rounder than the original 0.34, "round as much as possible", while
  still reading as a play down to the 18pt row circle); one factor scales sanely
  to every size. Call sites: the tracker/to-do transport (`TransportCircle`,
  `box = 0.315·diameter`), the main timer button — compact 27/34pt and full 48pt,
  `box = 0.315·size` — the torrent row play control (`box 11`, pause keeps SF
  `pause.fill`), and the timer help-tab icon legend. The menu-bar badge is
  deliberately excluded (it ships with the corner-system redesign). Pause glyphs
  everywhere keep SF `pause.fill`.
- **HoverDeleteX (Controls.swift)** is the shared hover-only row delete. Both row
  modules insert it IN FLOW, only while the row is hovered, right before the
  row's trailing fixed content (the tracker's time; nothing follows it in
  to-dos) — it lives inside the row's flexible spacer, so a non-hovered row
  reserves no width and the trailing content never moves or gets covered.

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
- Deleting a space (in the settings table) sends its modules to the INACTIVE
  bucket — they are hidden, not silently merged into another space
  (`PanelTabsModel.deleteTab`; confirm copy "its modules become inactive"). The
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
  whose legacy toggle was OFF moves to the inactive bucket (exact seeds and
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
  `["tracker", "todos"]`. Modules whose legacy default is hidden start in the
  inactive bucket on a fresh migrate (currently the torrent module, opt-in
  before its onboarding/banner "enable" — which still activates it). A
  decoded legacy model gets its whole active layout rebuilt into that same
  three-space shape exactly once (`canonicalLayoutSeeded`): space 1 gets
  every other active module, in the order first encountered scanning the
  existing spaces, keeping space 1's current icon; space 2 gets "system"
  alone (icon "display") only if system is active; space 3 gets "tracker"
  then "todos" (icon "clock") only for whichever of the two are active. The
  inactive bucket itself is untouched — canonicalization only rearranges
  what is ON a space, and any space beyond these three dissolves, its active
  modules folded into space 1. This replaced three earlier one-shot seeds
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
  module inactive before the update (a monitor they turned off, torrent before
  its opt-in, anything in `inactive`) stays inactive after — only the new modules
  and the tab restructure appear automatically.
- Module-visibility migration: the old `show*Module` toggles are read once
  and every OFF module is moved into the inactive bucket, after which
  visibility is pure membership and the toggles are never read again. The
  fresh-migrate path applies this deterministically on every recompute (so a
  module never flickers visible while `panelTabsRaw` catches up) and claims
  the `moduleVisibilityMigrated` flag; a decoded legacy model runs it once,
  behind the flag, so a later re-activation is not undone. Onboarding offers a
  per-module toggle for every module — timer, awake, clipboard, converter,
  window manager, the system monitor, the time tracker, to-dos and torrents
  (transient `@State`, not the dead `show*Module` keys) — and applies the
  choices straight to the spaces model (`activateStoredModule`/
  `deactivateStoredModule`): an enabled module stays on the canonical space the
  launch-time fresh migrate already placed it on, a disabled one goes to the
  inactive bucket. Because the fresh migrate always lays down all three
  canonical spaces, turning the monitor / tracker / to-dos off can empty space
  2 or 3, so `dropEmptyOnboardingSpaces` runs once right after and removes any
  space left empty (except space 1, which always stays — the speed test has no
  onboarding toggle, so it is never truly empty); the fresh install therefore
  never opens onto a blank tab. Opening a `.torrent` file or magnet link
  reactivates the torrent module the same way.
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
  readout). Conversion/parse/clamp is `HopCore.RateLimit` (`RateLimitTests`).
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
  Keys `donateTitle` and `donateBody` are translated across all 18 languages.
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
- The "it just works for users" path: sign releases with Developer ID
  + notarization (Apple Developer Program, $99/year) — Gatekeeper
  warnings and "suspicious signature" flags from firewalls
  (LuLu/Little Snitch) disappear. The self-signed "Minimo Signing" is for
  local development only.
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
- "Used" matches Activity Monitor's Memory Used: anonymous pages minus
  purgeable (App Memory) + wired + compressed. Not the active queue —
  active_count loses app memory parked on the inactive queue (gigabytes
  after days of uptime) and wrongly counts the active file cache
  (fixed 2026-07-18, was ~2 GB under the system's figure).
- The COLOR comes from macOS's own memory-pressure signal
  (kern.memorystatus_vm_pressure_level): 1 normal (green when colorful),
  2 warning → yellow, 4 critical → red. No user threshold: the system's
  verdict is the honest one. A caption in monitor settings says so.

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

- Opens 1060pt wide so all ELEVEN section tabs (general, timer, awake, monitor,
  clipboard, converter, windows, internet, torrents, tasks & time, what's new) sit
  on ONE line in the widest language (was 940 for ten; the "tasks & time" tab was
  added 2026-07-21 and adds ~130pt of natural-width chip). Each module has its own
  full documentation tab, torrents included (`docTorrentFull`, all 18 languages).
- The `tasks & time` tab (`aboutTabTasks`, 8.23) documents the two 1.4.0
  time-management modules together in ONE tab, as two clearly separated sections:
  the time tracker (`docTrackerFull`) above and the to-do list (`docTodosFull`)
  below, split by a divider. Same tone/structure as `docTorrentFull`; every claim
  matches shipped behavior including the sink-to-bottom (8.20) and visible-rows
  (8.21) changes. The `general` overview tab (`docGeneral`) gained `time tracker`
  and `to-dos` bullets, and its `header` bullet was refreshed for the 1.4.0
  spaces-tabs (icon tabs, up to four spaces, arranged in settings). All ×18.
- Free resizing in both directions: content scrolls vertically; on width
  changes the section tabs wrap onto new lines (FlowLayout, natural-width
  chips) and the text reflows. Minimum 480×300.
- The window size is set explicitly (sizingOptions=[]); .preferredContentSize
  is forbidden — it crashed AutoLayout on baseline views.
- First-open sizing: the content height is only known after SwiftUI lays out,
  so the very first open orders the window in TRANSPARENT (alpha 0) at the full
  1060 width and reveals it only once the first `hopAboutContentHeight` report
  arrives — sized to the active tab, recentered, faded in — so it is never seen
  at a guessed/oversized height (house invariant: laid out before shown). A
  1-second safety net reveals it anyway if no report comes. Later opens reuse
  the retained, already-correct frame (the active tab is remembered) and just
  recenter. Heights are integral (a fractional height re-triggered a resize).

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
- Settings → general → "resize windows with hotkeys": under the toggle sits a
  legend "zone glyph + ⌃⌥ key", four columns (shared `snapHotkeyItems` list with the
  help tab legend), replacing the old cryptic symbols-only caption.
- Help → general no longer ends with the "hop — and it's done…" closing
  line: it duplicated the page (removed in all 18 languages).
- App icon (Finder/Applications): dark or light chip with the REAL icon
  previews, light is the default; "auto" removed. The row sits after the
  updates section, away from the theme picker (it kept reading as part of
  the theme). setIcon failure rolls the Finder custom-icon flag back —
  a half-written icon rendered the app as a folder.
