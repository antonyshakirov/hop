# Compact app audio and Hop Mix

Approved by Anton, 2026-10-22. Preview only; publication requires separate approval and release checks.

The Sound window offers output-device volume and compact app volume/mute rows. App volume is0–100%, with100% preserving the app's own level. Input is a tab in the same window: selected microphone, hardware level/mute, an explicit local check and optional Hop Mix. App mixing never starts input capture, creates Hop Mix or invokes the input worker, including with legacy saved active inputs.

Start Mixer records an explicit persistent choice. Closing/reopening Sound does not change the listening choice. Hop Mix stops on close and stays off on reopening. Normal quit releases audio while keeping the choice; the next ordinary launch resumes output mixing. Stop Mixer clears the choice. Module disable suspends routing without losing the user's choice; re-enable resumes. Capture permission failure shows an error. A listening-output failure retains the source muting guard and shows an unavailable route; it never falls back to system playback. Background routing does not need an open window. Temporary checks are discarded on Sound close.

Verification scenarios:

- Output with two demo apps fits below400pt; Input has its own measured compact height in the same window.
- Fake output-session lifecycle: initial launch stays off; start/close/reopen keeps running; quit-like suspend/recreate restores; explicit stop prevents restore; module disable/re-enable gates restore; runtime failure does not erase choice; restoring a persisted muted app applies mute immediately.
- Legacy active input/bass settings do not create input channels or a worker in output-only mode.
- App gain/mute persists; normalization to0–100% preserves mute and clamps old boosts; main output and selected-input hardware volume remain independent.
- Real Preview: appvolume/mute works; closing Sound stops/discards its explicit check and Hop Mix, closing Sound does not stop routing; reopening and relaunch reflect the persistent choice. No microphone recording for these tests.
-22languages, actual text wrapping, compact layout in both themes, available full native tests, archive signature verification and bounded review.

No additional global microphone toggle, noise suppression, per-tab browser mixing, automatic login-item installation or publishing is part of this change.
