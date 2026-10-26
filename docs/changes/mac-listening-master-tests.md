# Mac listening master acceptance (2.4 development)

Intent: docs/spec.md, "Mac volume across listening destinations".

- Same output as Mac: app 100% receives unchanged DSP gain, hardware handles Mac volume once. App 50% adds one 50% attenuation.
- Explicit other output: reducing Mac level reduces its listening signal without changing its physical device volume or selected UID.
- Mac mute/unmute applies across listening destinations, preserves each saved app mute and gain.
- Hardware-key changes refresh the top UI and session without requiring Sound to be open.
- Volume-only updates do not recreate capture/output engines or change master/system output selection.
- Pending preparation, default-output change, missing-device pause/reconnect and first audible frame use the latest master state without double application.
- Stop cancels observation, late callbacks cannot resume processing. Hop Mix/physical mic and stored app settings remain unchanged.
- Unknown/nonfinite volume metadata uses a documented safe neutral fallback, never an invented mute or boost.

Physical acceptance: stable Spotify source in AirPods with no route switching during the level comparison; compare Mac keys and top Hop control; default and explicit-output cases; app 100%/50%/mute; close Sound and repeat Mac keys; restore original levels/routing. Source-code tests establish policy and lifecycle only, not acoustic timing.
