# Audio input and confirmed-agent regression cases

## Torrent initial selection

Requirements: `docs/spec.md`, Initial torrent file selection.

| ID | Given / action | Expected observable result |
| --- | --- | --- |
| TOR-01 | Add selected members of a multi-file torrent | First add includes their sorted indices; raw metadata is unchanged; no initially unrestricted download |
| TOR-02 | Confirm none, a negative index or an unknown member | Rejected before starting an engine or adding a row |
| TOR-03 | Select every file of a magnet containing `so` | Explicit confirmed indices override the magnet selection |
| TOR-04 | Re-add an existing torrent with a different selection | Update uses info hash; a refused update propagates and does not replace the row with unconfirmed state |
| TOR-05 | Add into a folder with an existing unselected file | Initial selection does not resize that file; no cleanup deletes existing data |
| TOR-06 | Download selected members, including a shared piece, then restart | Selected bytes are correct and selection persists; document rqbit's skipped placeholders and shared-piece writes rather than treating path absence as verified |

## Audio input and confirmed-agent cases

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

| IN-20 | Open the stopped mixer with physical, virtual, app and hidden sources | Connected physical microphones are visible after pinned/selected sources; other inactive sources collapse; manual hiding is respected; no capture or preset change |
| UI-04 | Hover Other Sources; open main and per-app device selectors | Disclosure text brightens without a full-width fill; both selectors use compact padded rows; long lists still scroll |

| IN-21 | Stop, close, cancel or fail a published input mix | Capture stops and Hop Mix is withdrawn before completion; explicit Start republishes before capture; saved source preferences remain intact; receiving app defaults are not changed |

| IN-22 | HAL refuses input withdrawal | Stop reports failure, resources remain owned for cleanup, producer is reaped and a later explicit retry cleans up before publishing again; presets remain unchanged |

## Tracker keyboard and project moves

| ID | Given / action | Expected observable result |
| --- | --- | --- |
| TR-01 | On macOS 27, open New Task in an inactive panel and type; submit and repeat | Keystrokes enter the field; Return creates one task and clears the draft for the next |
| TR-02 | Rename a project, edit a task name or time, then finish or cancel | Field owns keyboard input during editing; ordinary panel clicks return focus without flicker |
| TR-03 | More visible tracker rows than the configured cap; drag a task name onto a folded or open project | Task moves into that project once; task identity, history and recorded time remain intact |
| TR-04 | In a scrolling list, drag a project name, reorder tasks, or move a task out | Projects remain at root; task ownership and insertion follow the uncapped list rules |
| TR-05 | Scroll with wheel/trackpad; scrub a task's time horizontally; cancel a native name drag | Scrolling and scrubbing remain available; cancelled drag leaves data and row appearance unchanged |
| TR-06 | Drop plain text, malformed transfer data or a row from another tracker session | No tracker mutation |
| TR-07 | Add a project or task; type a full name across tracker redraws; Return twice, then Escape | Caret survives every character, each Return creates one complete item and retains the cleared field, Escape discards the remaining draft |
| TR-08 | In an uncapped list, drag a task name diagonally onto an open or folded project | AppKit pointer path moves the task once through the shared resolver; identity, intervals and corrections remain intact |
| TR-09 | Click a project name, then separately begin a name drag and press Escape | Click opens one rename field; cancelled drag changes no task ownership and releases capture and preview |

These cases define the required behavior. Native unit tests cover activation-tag
release, editor key handling and transfer payloads; they do not certify physical
keyboard routing, focus return or the complete mouse-drag path.
The actual hosted TrackerView also covers TR-07. Synthetic mouse replay failed
its plain DragGesture control, so it is not evidence for TR-03 through TR-05.
TrackerNamePointerTests drive queued AppKit events through the actual native
name surface and hosted TrackerView for TR-08/TR-09. Physical WindowServer
delivery still requires the installed Dev check.
