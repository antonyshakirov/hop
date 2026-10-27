# Hop Mix input sources

## Owner agreements and implementation status

Owner requests, 27 October 2026: keep a separate System Default microphone source,
include it on first use, follow the current macOS default, allow additional named
physical microphones, and retain subsequent source choices/levels. The owner also
requested confirmed agent control of all audio settings. These are agreed
requirements implemented in the current source and under automated verification;
the installed Dev build and physical acceptance have not yet been updated.
The system-wide default input must not be changed to Hop Mix automatically.

## User scenario

The user opens Sound → Input. The source list always contains System Default,
showing its currently resolved microphone, plus connected physical microphones
and eligible applications. The fresh preset selects only System Default at 100%.
Opening the window, reading agent state, or loading the preset does not capture.
The user explicitly starts Hop Mix; after permission and actual capture readiness,
all source controls become available together. Additional physical microphones and
apps can be enabled with separate gain and mute. Choosing an app in the receiving
application remains necessary; Hop does not silently change other apps' inputs.

## Source identity and saved data

- `system` is a stable logical source, resolved against the current macOS default.
  It remains visible when unavailable. An explicit physical source uses its device
  UID, never its localized display name. App sources use bundle IDs.
- Store active, gain and mute separately from actual runtime state. A fresh preset
  selects System Default; an existing preset with that source off stays off on
  the next start. Save input-app selections as well. Stop, close, failure, quit
  and module disable stop capture without erasing the preset or resuming it later.
- A named source does not follow changes in the system default. When unplugged it
  waits for that same UID; it never captures a substitute microphone.
- A system default that is Hop Mix or another Hop-owned virtual input is
  unavailable for capture, preventing recursive feedback. No physical substitute
  is chosen by Hop.
- Technical choice: resolve a physical UID only once. When System Default and a
  saved explicit source resolve to the same UID, the System Default settings take
  precedence while it is active. The explicit selection is retained and shown as
  already included through System Default; it becomes effective separately when
  the default changes or is turned off. Never double the signal.

## Runtime changes and privacy

Changing the macOS default updates the System Default source while the mixer is
running; it does not turn the whole mixer off. Reconfigure only sources whose
resolved identity changes. Adding an app or changing gain must not reopen an
unchanged physical microphone. Removed sources leave the render gate before their
capture is stopped. New source controls and the ready state reflect actual ACK,
not just a queued start. Bluetooth connection time must be shown honestly; do not
simulate readiness or keep a microphone warm while the mixer is stopped.

The hardware accessory mute applies to physical microphone contributions inside
Hop Mix, with consistent status across all included microphones. Preserve each
source's saved individual mute. It must not claim to mute unrelated applications
using a microphone directly, and must not mute app/music contributions implicitly.

Closing Sound, disabling the input mixer/module, quitting, denial, failure or
cancellation must stop physical capture. Late permission/start acknowledgements
cannot revive it. Explicit quick-start remains supported without opening Sound;
closing Sound after opening it still stops its input mixer. Closing the main
popover alone is not the same as closing Sound. No voice file, beep, recording or
network transfer is added by these changes.

## Confirmed audio agent contract

Extend protocol 2 only. Capabilities/state expose stable source IDs, current
resolved UIDs, selected versus effective settings, availability, failure and
requested/starting/ready state. Read/discovery is side-effect free.

Confirmed actions cover physical master volume/mute, output mixer start/stop,
per-app gain/mute/destination/pin/order/add/reset, input mixer start/stop, and
input-source gain/mute/active choices. Reuse controllers, bounds and device
validation used by the UI; no arbitrary preferences or executable commands.

Stop receipts wait for an empty-capture ACK or a reaped producer. A new start
waits for stop completion. Readiness and timeout handling belong to one session
generation; an old request must never finish against or stop a newer session.
A named source currently included through System Default is rejected as an
independent agent mutation, matching its disabled UI controls.

Keep existing strict fields, customer attestation, TTL, digest-bound durable
claim, conflict and replay behavior. Async start is applied only after an actual
session ACK; rejected startup returns a specific failure. Unknown/crash outcomes
remain indeterminate, and replay must not repeat capture. No unconfirmed legacy
or URL command gains microphone access. Restart restores settings, not capture.
Agent control must also work when the Sound window is closed, using an explicit
confirmed control scope rather than pretending that windowOpen is true.

## Acceptance

The scenarios in `../03-test-cases.md` are required. UI validation includes both
themes, available/missing system input, few and many sources, disabled/starting/
ready/error states, and localized labels in Hop's shared controls. AirPods startup,
voice plus music received by a consumer, microphone stop and accessory mute still
require physical acceptance; unit tests alone do not establish these results.

## Bluetooth input format acceptance (28 October)

A physical input capture must use the exact selected device UID without a default-device
fallback. Worker microphone capture uses AVCaptureSession and native-format
AVCaptureAudioDataOutput buffers; each buffer is converted to the existing 48 kHz
stereo mix format. This isolates capture from an AVAudioEngine input tap retaining
a previous 48 kHz format while AirPods change to 24 kHz. No microphone monitoring
output, system input/output change, audio file or background prewarming is allowed.

A successful session start without usable audio is not ready. Configuration ACK
requires the first nonempty successfully converted PCM buffer for every newly added
physical source. A bounded first-frame failure stops the attempted capture and
reports failure. Stop rejects late buffers and errors, drains the callback queue,
and stops capture before its completion is acknowledged. Hardware format changes
within a capture must not force a new session just to convert 24/48 kHz input.

Synthetic tests cover native-format changes, missing/empty frames, exact UID,
early failure and post-stop callbacks. Real AirPods cold start, live system-default
change and actual receiver audio still require separate acceptance; synthetic
results do not establish Bluetooth startup latency or audible delivery.
