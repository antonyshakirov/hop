# Agent protocol v2

Owner agreement, 2026-10-26: make both Hop and hop.tools usable by customer agents. The first verified local workflow adds the customer's tasks and starts their requested timer. Existing file commands and hop:// links remain compatible. Publication and installation are separate from preparation.

The website describes the actual product, download choices, modules, supported actions and limitations from maintained registries. A localized /agents page links a public machine catalog. Product/version/download data reuse the existing release config; the release script remains the only writer of the public app version. A local capability file is the authority for an installed build; a website response cannot prove that the customer has upgraded.

## Local surface

No network listener or remote account. The customer's own desktop agent needs OS permission to the Hop Application Support directory. This is the existing same-user trust boundary, not authenticated remote access. Public pages never read or transmit local state.

Hop writes agent-capabilities.json and preserves agent-state.json. New requests use agent-requests/<lowercase UUID>.json; results use agent-results/<same UUID>.json. Requests are UTF-8 JSON, at most 64 KiB, immutable under their ID, created atomically without replacing an existing pending request. One request performs one action. Different IDs use different files. The client waits for the matching result before dependent actions.

Envelope: schemaVersion=2, id, createdAt and expiresAt (UTC ISO8601, at most 10 minutes apart), confirmation={method:client_agent_attestation,confirmedAt}, command. Approval must be after creation and before execution/expiry, and must cover this exact action. The agent shows the task or timer change and obtains the customer's explicit consent. The app checks format/time, not who clicked in an external chat. An agent without file access explains how the person can install/open Hop; it cannot claim execution.

Supported v2 actions: timer.start(seconds1..86400), timer.pause, timer.reset, stopwatch.start, stopwatch.stop, todo.add(text1..500,note0..4000,important optional), todo.complete(id), todo.delete(id), tracker.start(task1..500), tracker.stop. Completion/deletion use a UUID from the state, never a guessed name. Starting a timer replaces the current timer or stopwatch and clears its progress. tracker.stop finishes all active tracking sessions; the customer must approve that scope. Confirmed audio actions are described below. Other interactive/system-permission-dependent legacy actions retain their existing acknowledgement limits.

## Results and retries

Each result has schemaVersion, id, requestDigest (SHA256 of the exact request bytes), status, code and optional entity IDs. Statuses: applied (the model accepted the operation), no_change (already in the requested state), rejected (not applied), indeterminate (execution cannot be established), conflict (the ID was reused with different bytes). Read agent-state.json to verify current state; no result promises persistence beyond the underlying stores' normal guarantees.

Before performing a command Hop durably creates an exclusive journal entry with an indeterminate outcome. Only then does it mutate the model and atomically store the final result. Duplicate unchanged requests return the existing outcome; changed bytes return conflict while preserving the original journal. A crash between claiming and writing the final result stays indeterminate across restart and never causes automatic re-execution. The client stops and asks the person to inspect state; it must not mint a replacement ID to work around an uncertain result. If the journal or result cannot be stored, the app fails closed before executing, or retains the already claimed indeterminate result.

Directories are same-user private0700, files0600. No-follow descriptor-relative I/O rejects links, foreign owners, nonregular files and oversized requests. Receipts contain codes/IDs rather than copies of task text. Journal capacity is bounded; at capacity new operations are rejected before execution. Expired requests do not become new operations. The original v1 surface has its original retry/acknowledgement limitations and must not be mistaken for v2.

## Verification

Core tests: invalid/expired/future approval, strict fields/types and limits, unchanged retry, changed-ID conflict, crash/unknown replay, durable-write failure, unsafe files/directories, concurrent IDs, capacity. App integration: synthetic task + timer, reload result, duplicate produces one task, UUID not found/ambiguous tracking produces a rejection, unknown actions never report success. Website: current release facts, real download paths/languages, all modules/actions, local-capability discovery and consent; complete localized page and footer link, RTL, browser discovery/layout, built export metadata/catalog/schema. Test data stays isolated from installed Hop and real customer data.

Protocol-2 clock commands respect the reported mode. Timer pause/reset reject stopwatch mode; stopwatch stop rejects countdown mode. Stopwatch start resumes a paused stopwatch, leaves a running stopwatch unchanged and rejects a running or paused countdown. The customer can approve timer.reset before switching from a paused countdown. State includes stopwatch elapsedSeconds.

## Confirmed audio controls

Audio uses the same version-2 envelope, customer attestation, lifetime and journal.
The installed capability file lists the exact fields for these commands:

- `audio.master.volume(direction,value)` and `audio.master.mute(direction,muted)`
  address the current physical input or output. Values are 0…1.
- `audio.device.select(direction,deviceUID)` selects a discovered device. The
  reserved value `system` resumes following the current macOS default. Selecting
  a named device changes that macOS default; Hop Mix cannot become the global
  input through this command.
- `audio.outputMixer.set(enabled)` controls output routing.
- `audio.app.update(appID,gain?,muted?,outputUID?)` requires at least one changed
  field. `outputUID: "system"` clears the app's explicit destination.
- `audio.app.add(appID,name)`, `audio.app.pin(appID,pinned)`,
  `audio.app.move(appID,offset)` and `audio.app.reset` manage the output app list.
  Move accepts −1 or 1 within the same pinned group. Reset clears all saved app
  gains, mutes and destinations; it preserves pins and order.
- `audio.inputMixer.set(enabled)` explicitly starts or stops capture.
- `audio.inputSource.update(source,sourceID?,gain?,muted?,active?)` requires at
  least one setting. Source is `system`, `device` or `app`. System has no
  sourceID; device/app requires its discovered UID/appID. Changes made while the
  input mixer is stopped save a preset and leave capture stopped. A named device
  matching the current System Default while that logical source is active is
  rejected with `audio_source_included_via_system`; its controls belong to the
  System Default source.

Start succeeds after the input session's ready acknowledgement. Changes to a
running input mixer wait for the corresponding configuration acknowledgement.
Permission denial, startup failure or cancellation rejects the action. The
operation remains pending while it waits; an identical request cannot start a
second capture. A separate confirmed stop can interrupt a pending start. Its successful result
waits for an empty capture configuration acknowledgement or producer shutdown.
State exposes `stopping` until that completes, and new input starts/edits reject
with `audio_input_busy`. Each pending readiness check belongs to one session
generation; a later restart cannot satisfy it or be stopped by its timeout. After
15 seconds without a conclusive result, Hop stops the input mixer and returns
`indeterminate`. Inspect state before any further action. Restart never retries
an uncertain operation automatically.

Audio state contains physical device and app inventory snapshots, current default UIDs, follow-system
flags, saved channel settings, input startup/update revisions and runtime flags.
`inventoryFreshness: "snapshot"` identifies a read-only inventory query.
Reading state or capabilities never publishes controller changes,
requests permission or starts capture. Input `running` follows session readiness;
saved source `active` describes the preset. `requestedPhysicalInputs` resolves
that preset against current devices; `effectiveInputUIDs` and
`effectiveApplicationIDs` report the last acknowledged session configuration and
become empty on stop. `microphoneOverlayMuted` reports accessory microphone mute
separately from saved source mutes. Output `running` means a routing
session exists. It does not establish audible playback; inspect each app's route
state and verify sound in the receiving app.

Physical controls also work with the Sound window closed. They retain device
identity checks and acknowledge hardware writes. A failed write/readback with an
uncertain effect returns `indeterminate`. Audio has no version-1 or URL command.
