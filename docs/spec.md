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
   jiggle 1px between tabs.
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

The "general" settings section is split into two text-switched sub-tabs:
"general" for the everyday options (theme, language, launch, sounds,
updates, app icon, hotkeys) and "modules & tabs" for the panel layout. The
"modules & tabs" tab is ONE combined table: a column per space, in order,
then a permanent "inactive" column, then a slim "+" stub column while under
the space cap. Module chips (name, lowercase) stack vertically in each
column; a hand-rolled drag moves a chip between columns and within a column
to reorder — that drag IS the visibility control (`move`/`deactivate`/
`reorder`). Inactive chips render dimmed. Each space column header carries
the space icon (tap it or its rotating disclosure chevron to open the
full-width icon picker below the table), "#N", and a hover-only delete xmark
that opens an inline confirmation (`delete this tab? its modules become
inactive` + delete/cancel); confirming sends the space's modules to the
inactive bucket (they are hidden, not merged into another space). The
inactive column header is just an "inactive" label — no icon, no delete, and
it cannot be moved. Dragging a column header horizontally reorders spaces
(`moveTab`, committed on release against the measured column frames). The
standalone settings window is 720pt wide so up to five columns (4 spaces +
inactive) read comfortably; chips truncate with `lineLimit(1)`. The in-panel
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

- Copy history: text, links, files, images. A copied file is stored as its
  FULL path (the file-url is read BEFORE the plain-text type: Finder also
  puts the bare file name as a string, which alone is useless). Clicking a
  row puts the entry back on the clipboard (its position doesn't change); a
  row that is a path to an existing file goes back as the FILE plus the path
  as text — Finder pastes the file itself, text fields get the path. Buttons:
  copy / paste into the last app. Confidential content (password managers) is not stored,
  and everything lives only on this Mac. The entry limit is in settings.
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
- Global zone hotkeys: a toggle in windows settings (ON by default —
  Anton, 2026-07-15), a fixed ⌃⌥ scheme covering ALL 18 zones:
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

- Time tracker over projects and tasks. All logic lives in HopCore
  (`TrackerEngine`, persisted to `tracker.json` via `TrackerController`);
  the view is glue. Labels tick off `tracker.heartbeat` (1/s while a task is
  tracking). Active by default — unlike torrents it has no engine to
  download, so it isn't opt-in; hidden or shown like every other module by
  membership in the "modules & tabs" table (drag it to/from the inactive
  column). The module title (`trackerLabel`) is "time tracker" — it names the
  feature both in settings and in the empty state.
- **Mixed root list:** the root is an ORDERED list of interleaved projects and
  project-less tasks. `TrackerData.rootOrder` holds the ids of every root item
  — every project plus every task whose `projectID` is nil — with no
  duplicates; the engine normalizes it on load (keep listed ids in order, drop
  stale ones, append any missing: projects in array order, then root tasks).
  A task's `projectID` is optional now: nil marks a ROOT task that tracks,
  aggregates, edits and deletes exactly like a nested one but belongs to NO
  project (so it never counts toward any project total). `addTask(projectID:)`
  takes an optional — nil appends a root task to `rootOrder`.
- **Reordering (engine):** `move(taskID:toProjectID:at:)` nests a task at a
  clamped position inside a project (lifting it out of the root or another
  project), `move(taskID:toRootAt:)` detaches a task to a clamped index in the
  mixed root list, and `moveRootItem(from:to:)` reorders that list (clamped;
  `from` out of range is a no-op). Each fires `onChange` once; add/delete keep
  `rootOrder` in sync.
- **Migration:** an old `tracker.json` (every task nested, no `rootOrder`)
  loads losslessly — the decode tolerates the missing field and every array
  field defaults to empty, and the engine derives `rootOrder` as the projects
  in their existing order. Open intervals, corrections and expanded flags are
  untouched.
- **Single active task:** at most one task is ever tracking. Tapping play on
  task B while A runs stops A first — the engine closes the open interval
  itself (`start(taskID:)`), the UI never juggles two. Deleting the active
  task stops tracking (its open interval is dropped with it).
- **Menu-bar indication:** while a task is tracking, the status-bar icon
  carries a small purple dot in the bottom-right slot — the same slot the
  timer badge uses, so the badge wins it in the rare digits-off-while-running
  config; with the countdown digits shown (the default) the dot stays visible
  during a countdown. An opt-in `show task time in menu bar` setting
  (`trackerTimeInBar`, OFF) additionally shows the active task's ticking
  `today` value as the bar title, but only when nothing else claimed it — the
  timer countdown always wins the title. Both toggle immediately on
  start/stop and tick 1/s off `tracker.heartbeat` (already routed to the
  status item via AppModel's forward).
- **Flat rows** (no card fills — TorrentView-style, so the width the padded
  cards ate is reclaimed): regular weight everywhere; the ACTIVE task is
  emphasized by COLOR only (its "today" label `Theme.textPrimary`). Delete
  xmarks are hover-only across the whole module.
- **Rendering:** the view walks `rootOrder`, drawing per id either a project's
  accordion block (header, then — while expanded — its task rows and the
  `+ new task` row) or a project-less root task row.
- **Project row** (mono 12): a disclosure chevron (`chevron.right`, rotated
  90° when expanded, 0.15s easeInOut), the name, and — only while COLLAPSED —
  a right-aligned `today — total` summary (mono 10, tertiary). Expanded project
  rows show just chevron + name (+ hover delete): the tasks below already carry
  their own numbers, so repeating the rolled-up pair was ticking noise.
  Clicking the row toggles expansion; hover reveals a trailing xmark. Delete
  uses the house inline confirm (`delete project and its tasks?` + delete/
  cancel on one line); confirm removes the project with its tasks, intervals
  and corrections.
- **Task row** (indented under an expanded project): a play/PAUSE button in the
  main timer's transport family (`TransportCircle`: `play.fill` in a filled
  circle when idle = "start"; `pause.fill` in a bordered circle when this task
  is active), the name, then `today` (mono 11) and the `total` prefixed with
  `Σ ` (mono 10, tertiary — e.g. `Σ 1:23`, so the pair reads as two different
  things at a glance), and the same hover xmark + inline confirm (`delete
  task?`). The active task's "today" label uses `Theme.textPrimary`. A
  project-less ROOT task uses the same row at root indentation (aligned with
  project headers, not the nested 16pt inset).
- **Adding / renaming:** a `+ new project` footer row, a root-level `+ new task`
  beside it (reuses `trackerNewTask`, creates `addTask(projectID: nil)`), and —
  inside an expanded project — a per-project `+ new task` row; all swap into an
  inline TextField (lowercase placeholder = the label), committed on Return
  (empty = cancel), Escape cancels. Double-clicking a name opens the same
  inline field to rename. Every inline field (new/rename/today-edit) shows
  explicit ✓ (commit) / ✕ (cancel) buttons right of it (`FieldCommitButtons`,
  house hover style) — the mouse equivalent of Return/Escape.
- **Drag to reorder:** a burger handle (`line.3.horizontal`) appears on hover at
  each project and task row's left edge (kept as a fixed gutter via opacity, so
  an in-flight drag's gesture survives the pointer leaving the row); dragging it
  avoids fighting the row's tap/scrub/play. On macOS a click-drag never fights
  the panel's wheel/trackpad scroll. Drop resolution uses a frame-preference
  resolver (the 8.2 settings-table pattern — robust across the mixed row
  heights of expanded accordions): every row reports its frame in the
  `trackerList` coordinate space, and the pointer's y resolves to a target. A
  TASK can drop at any position in the mixed root list, between an EXPANDED
  project's task rows, or ONTO a COLLAPSED project row (appends into it); a
  PROJECT drops only among root positions (it never nests). The dragged row
  dims and follows the pointer; a 2pt accent line marks the insertion point.
  One engine move commits per completed drag (`move(taskID:toRootAt:)`,
  `move(taskID:toProjectID:at:)`, or `moveRootItem(from:to:)`).
- **Editing today's time** (only while the task is NOT active — the engine
  refuses otherwise and the UI hides the affordance): scrub the today label
  (horizontal drag, 8pt = ±1 min, a scrub tick per step) with a live local
  preview, committed as ONE correction on gesture end (the engine appends
  corrections, so per-step commits would pile up); or click the label to type
  into an inline field that reads `H:MM` or bare minutes (`90` = 90 min,
  `1:30` = 1h30m). `.help` carries the hint. Times via `TimeFormatting.short`.
- **Empty state:** an empty root (no projects and no root tasks) → a `time
  tracker` title line (mono 12, primary) over the `no projects yet` hint
  (tertiary), plus the add rows.
- **Snapshot rule:** every focused-field state is gated off `Snapshot.active`,
  so `--snapshot` renders never show an editing TextField (yellow artifact).

### To-dos

- A flat checklist. Logic lives in HopCore (`TodoList` + `TodosStore`,
  `todos.json`, atomic write, corrupt → `.bak` + empty, tolerant decode of a
  missing `items` key); `TodosController` mirrors `TrackerController` minus the
  ticker (a checklist has nothing that ticks). Model API: `add(text:)` trims and
  APPENDS at the bottom (empty = no-op), `toggle(id)` flips `done` IN PLACE
  (completed items keep their position), `delete(id)`.
- **Row:** a circle checkbox (`circle` / `checkmark.circle.fill`), the text
  (mono 12; done = `Theme.textTertiary` + strikethrough), and a hover-only
  xmark. Deletion has NO confirmation — a to-do is cheap to lose and to retype
  — and works for done and active alike.
- **Adding:** a `+ new to-do` footer row opens an inline field with the same
  ✓/✕ buttons and `Snapshot.active` gating as the tracker; Return/✓ append,
  Escape/✕ cancel, empty = cancel.
- Registration is by membership like every module (key `"todos"`, title
  `todosLabel`); it captures the keyboard while its field is focused (same
  `onEditingChanged` path as the tracker) so digits don't leak to the timer.
  Fresh installs pair it with the tracker on the "clock" space; existing users
  get it seeded directly after the tracker exactly once (`todosSeeded`).

## Shared components

- **SettingChip (Controls.swift) is the ONLY chip toggle** in the entire
  app: height 28, corner radius 5, mono 10 / icon 13, padding 9,
  inactive border Theme.divider, hover hoverDim+pointer. All former
  local chips (settingChip/unitChip/themeIcon/alertMode/styleChip/
  bigToggleChip/displayStyleCard, onboarding and converter chips) are thin
  wrappers over it. A new chip = SettingChip only; copies are forbidden.

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
- Default spaces: a fresh install migrates into THREE spaces — "house" with
  the general modules, "display" for the system monitor (the monitor tab should
  LOOK like a monitor; was "gauge"), and "clock" for the time-management pair
  `["tracker", "todos"]`. Modules whose legacy default is hidden start in the
  inactive bucket on a fresh migrate (currently the torrent module, opt-in
  before its onboarding/banner "enable" — which still activates it). Models
  saved before the tracker had its own space lift the tracker out of the first
  space into a new "clock" space exactly once (`trackerTabSeeded`; skipped if
  the user already moved it or the spaces are at the cap); models saved before
  the to-do module get "todos" placed directly after "tracker" exactly once
  (`todosSeeded`, in whichever container holds the tracker — the same space
  below it, or the inactive bucket if the tracker is hidden). Models saved
  before the system monitor had its own space lift "system" out of the first
  space into the second space (or a fresh "display" space if only one
  exists) exactly once (`systemTabSeeded`; skipped if the user already moved
  it elsewhere, or a fresh space can't be minted because the model is at the
  cap). Existing users' icons/layout are otherwise untouched.
- Module-visibility migration: the old `show*Module` toggles are read once
  and every OFF module is moved into the inactive bucket, after which
  visibility is pure membership and the toggles are never read again. The
  fresh-migrate path applies this deterministically on every recompute (so a
  module never flickers visible while `panelTabsRaw` catches up) and claims
  the `moduleVisibilityMigrated` flag; a decoded legacy model runs it once,
  behind the flag, so a later re-activation is not undone. Onboarding applies
  the fresh install's module choices straight to the spaces
  (`activateStoredModule`/`deactivateStoredModule`), and opening a `.torrent`
  file or magnet link reactivates the torrent module the same way.
- Settings tab order: general → timer → remaining modules → monitor.
  "Remaining modules" = awake/clipboard/converter/windows as sections with
  headers. The "general" tab splits further into two text-switched sub-tabs,
  "general" and "modules & tabs" (the combined space/module table);
  the selected sub-tab is transient state, not persisted. The app version is shown next to the "check & update" button.
  The "latest version installed" / "failed" note after a manual check is
  transient: it clears when the settings window closes or after 30 minutes —
  a stale note would deny an update that shipped since.
  Toggles are our own MiniSwitch (the system Toggle doesn't render in
  ImageRenderer).
- Info page: per-module tabs, "term — explanation" style
  (the term is bold up to the " — "). The general-tab footer links to
  the GitHub repo next to the version ("open source · version X · GitHub"),
  to antonshakirov.com and to the product landing — in the app's language
  when the landing has it (8 languages), otherwise English.
- Languages in pickers use the standard order, like system lists:
  alphabetical by NATIVE names, Latin → Cyrillic → CJK (pickerOrder,
  localizedCompare). FINAL per Anton 2026-07-13; the "by English names"
  variant was tried and reverted. "Same as system" sits on top; there is
  search.
- Menu bar: asterisk (brand glyph, 8 rays); on the right — play/pause
  badges or a purple tracking dot (bottom, mutually exclusive) and a yellow
  awake dot (top); on finish — a blinking bell; the countdown is monospaced
  and can be disabled in settings.
- **The panel is keyboard-transparent** (Anton, 2026-07-13; completed
  2026-07-15): it never steals keyboard focus — on open AND after any
  click inside it, focus goes back to the app underneath (dictation and
  Cmd+V land there). The panel is mouse-only, with four exceptions that
  do capture the keyboard: digit entry into the timer display (while a
  digit group is selected), the clipboard search field, a focused
  tracker inline field (a project/task name or a today-time edit), and a
  focused to-do field. The
  timer itself starts/stops ONLY via its on-screen play button — Return and
  Space do NOT toggle it (Anton, 2026-07-19). `handleKey` handles only digit
  entry, Delete (backspace a digit), Escape (deselect the digit group) and
  Return (end digit entry, same as Esc, without starting the timer).
  The tracker and to-do cases also guard the panel's global key handler: while
  such a field is open, Return commits the name/text — it must NOT reach
  `handleKey` and be swallowed by the digit editor. The capture is one flag fed
  by the timer digit editor, the tracker field and the to-do field
  (`panelKeyboardCaptured =
  editUnit != nil || trackerEditing || todosEditing`). When the capture ends
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
- Settings → windows → "resize windows with hotkeys": under the toggle sits a
  legend "zone glyph + ⌃⌥ key", four columns (shared `snapHotkeyItems` list with the
  help tab legend), replacing the old cryptic symbols-only caption.
- Help → general no longer ends with the "hop — and it's done…" closing
  line: it duplicated the page (removed in all 18 languages).
- App icon (Finder/Applications): dark or light chip with the REAL icon
  previews, light is the default; "auto" removed. The row sits after the
  updates section, away from the theme picker (it kept reading as part of
  the theme). setIcon failure rolls the Finder custom-icon flag back —
  a half-written icon rendered the app as a folder.
