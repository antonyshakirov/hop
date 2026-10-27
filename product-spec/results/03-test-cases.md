# Audio input and confirmed-agent regression cases

Requirements: `screens/sound-input.md`. These scenarios are required for the new
implementation; this file does not declare that they currently pass.

| ID | Given / action | Expected observable result |
| --- | --- | --- |
| IN-01 | Fresh settings; open Input | System Default selected at 100%; other sources off; no permission request or capture |
| IN-02 | Disable default, set gains/mutes and app choices; stop/recreate/start | Exact preset retained; default remains off; no unsolicited capture on recreation |
| IN-03 | Default points at AirPods; add MacBook microphone | Two unique captures and independently adjustable contributions |
| IN-04 | Default and explicit source resolve to same UID | One capture/one contribution; saved explicit choice retained and effective precedence visible |
| IN-05 | Change macOS default during a running mix | Default source changes; explicit sources retain UID; unchanged captures and music are retained |
| IN-06 | Add/remove app or edit gain | No reopen of unchanged microphones; removed audio disappears before disposal |
| IN-07 | Explicit device disappears/returns | No substitute capture; same UID can rejoin while the explicit active session permits it |
| IN-08 | Default is absent or Hop-owned virtual input | Unavailable source, no feedback/fallback; other valid sources remain usable |
| IN-09 | Close Sound or stop during permission/start | Actual input flag becomes false; late callbacks cannot restart capture |
| IN-10 | Accessory mute with multiple microphones | All Hop microphone contributions mute together; saved row mutes preserved; music/unrelated apps unaffected |
| IN-11 | Physical AirPods start | One deliberate start reaches real PCM/ready or reports an explicit failure; UI never claims ready while pending |
| AI-01 | Read audio state/capabilities | No capture, permission prompt, write or device switch |
| AI-02 | Missing/expired confirmation; legacy audio command | Rejected with no audio effect |
| AI-03 | Confirmed async input start; delayed success/failure ACK | No applied receipt before ACK; correct final status and actual state |
| AI-04 | Replay same ID while pending or after restart; changed bytes same ID | No second capture; existing indeterminate/terminal receipt or conflict |
| AI-05 | Stop while start is pending | Stop can cancel it; no deadlocked serial inbox and no late capture |
| AI-06 | Invalid source/UID/gain/type/unknown field | Strict rejection; no partial settings mutation |
| AI-07 | Confirmed per-app output and input-source edits | UI and agent state agree; persistence and no-fallback policy match UI |

| IN-12 | Refresh publishes a new default and its device list | One consistent snapshot; no intermediate empty configuration or accessory unmute |
| IN-13 | Close/stop while a live input reconfiguration is blocked | Producer reaped before completion; no late capture after close |
| AI-08 | Stop a running input mix | No applied receipt until zero-capture ACK or producer exit; new start/edit waits |
| AI-09 | Start A, stop, start C before scheduled readiness tasks | A is cancelled; its ACK or timeout cannot finish against or stop C |
| AI-10 | Mute a named mic currently included through System Default | Rejected before mutation; no saved-only success while microphone stays audible |

| IN-14 | Native microphone changes 48/24/48 kHz during a capture | Converted 48 kHz stereo continues without reopening capture |
| IN-15 | Session starts but emits no valid converted PCM | No ready ACK; bounded failure stops the attempted capture |
| IN-16 | Frames or errors arrive after Stop | No later consume/failure callback or capture restart; stop remains idempotent |

| UI-01 | Toggle Mix repeatedly with the pointer over its icon or label | Enabled button retains a hand; chip text never becomes selectable |
| UI-02 | Leave a chip for an editable text field or cover/hide its window | Previous chip cannot overwrite the next control/window cursor |
| UI-03 | Disable/re-enable a chip without moving the pointer | Arrow when disabled; hand when enabled |
| IN-17 | Pin/hide/restore an inactive input with the mixer stopped; restart Hop | Typed source identity and presentation persist; audio preset bytes, hardware and capture unchanged |
| IN-18 | Disconnect a hidden source and restore it | Saved name remains available inside Other Sources; restoring does not select it |
| IN-19 | Try to hide a selected source, or select a hidden source through AI | Hide rejects; selection reveals the source; System Default cannot be hidden |
| AI-11 | Confirmed pin/hide commands, strict booleans/fields and system-source rejection | UI/state/persistence agree; no permission request or hardware write |
