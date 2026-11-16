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
| TOR-06 | Use the patched engine to download selected members and restart with fast resume | Selected bytes match; selection and shared fragments persist; missing ranges are verified rather than trusted |
| TOR-07 | Shared pieces with absent skipped files, then seed to another client | Selected bytes match in both clients; skipped files/directories remain absent; fragments are served from the journal |
| TOR-08 | Shared pieces with existing skipped data | Existing bytes and length remain unchanged; selected bytes match |
| TOR-09 | Deselect, then reselect with overwrite disabled | Owned file is reusable; later skipped writes use cache; previously foreign files remain protected |
| TOR-10 | Fail after materializing one of several requested files, then retry | Previous effective selection survives; owned file can be reused without allowing foreign overwrite |
| TOR-11 | Delete synthetic torrent files from Error with a corrupt cache | Payload and cache are removed without replay; an obstructed cleanup returns an error |
| TOR-12 | Torn/corrupt journal, overlapping writes and repeated overwrite | Incomplete tail recovers, corrupt complete records fail, latest ranges replay correctly and obsolete data is compacted |

| TOR-13 | Start with a stock 9.0.1 helper, then use the signed 9.0.1.1 manifest | Hop requires the newer helper; matching packaging revision is accepted; signature and manifest validation retain their existing guarantees |

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
| TOR-14 | Required helper update fails with an old or missing version; saved torrents remain | Old binary stays unchanged, no process or output directory is created, and the visible retry action accepts a click without losing saved rows |

## Clipboard quick picker

| ID | Given / action | Expected observable result |
| --- | --- | --- |
| CL-01 | Press Command-Shift-C with clipboard enabled | Searchable history opens; no Copy keystroke is issued to the preceding app |
| CL-02 | Search a synthetic history, then press Command-1 through Command-9 | Corresponding filtered result is copied whole and picker closes; order stays unchanged |
| CL-03 | Move with arrows, press Return; reopen and press Escape | Return copies selection; Escape preserves the clipboard |
| CL-04 | Select an image, files or externally stored long text | Existing copy path restores the actual content, preserving history |
| CL-05 | Empty result, out-of-range digit, another Hop window, disabled module | No unintended copy or global digit interception; disabling releases the opener and closes the picker |
| CL-06 | Open in light/dark themes and with long localized labels | Search, selection and numbered hints are readable and fit the window |
| CL-07 | Compose Japanese/Chinese text in the search editor, press arrows/Return/Escape | Native composition receives those keys and history is not copied or dismissed |
| CL-08 | Rebind the picker opener to Command-1, open, then press it again | First result is copied through the picker selection path |
| CL-09 | Hover a truncated multiline text entry in the panel and quick picker | Preview contains the actual text and paragraphs, not the clipboard module purpose; panel copy/paste/save controls retain their action hints |
| CL-10 | Hover external long text, newline flood, file list, image or color | Text preview uses the stored head without loading a large body; omitted tail has an ellipsis, files show paths, images show miniatures and colors retain their notation |
| CL-11 | Hover a row for0.49s, then0.5s; move within it, leave/reenter and switch rows repeatedly | No early preview; actual preview appears at0.5s for each current row, independent of native tooltip cooldown; within-row movement does not postpone it |
| CL-12 | Leave, click, scroll, hide/close panel, replace an item or remove its view during the delay/preview | No late or stale preview, no focus/pasteboard/copy change, and the parent panel stays in place |
| CL-13 | Show the preview in both themes near screen edges or on a short display | Regular10pt body and0.5pt border; preview follows the pointer's screen, stays nearby and fits without covering the hovered point |
| CL-14 | Hover short text, a small image, a large image, then another row while loading | Content determines window size, image aspect/color are retained and no dimensions placeholder or empty footer appears; late image cannot replace the next row |
| CL-15 | Supply traversal/symlink/non-PNG/oversized or unsafe-dimension image data; load many images | Reject unsafe files before thumbnail decoding; actor serializes work, thumbnails stay bounded and cache remains within12 entries/8MiB |

| CL-16 | Hover a book-sized text, a long unbroken string or thousands of newlines on regular/short screens in both themes | Preview is bounded to1500 characters/20 source lines; rendered window fits the screen and360pt limits, has no scroll view and ellipsizes wrapped overflow; original copied content remains intact |

## Protected lid sessions and cooling

| ID | Given / action | Expected observable result |
| --- | --- | --- |
| HW-01 | Enable protected lid mode with no approved helper | Explain approval; no sleep or fan override is claimed |
| HW-02 | On battery reach10%, or serious/critical thermal state during protected lid mode | End the mode, restore owned sleep/fan changes, report the reason; no automatic rearm |
| HW-03 | AC connected at5%, battery absent, or lid state unavailable | No false low-battery cutoff; unknown observations cannot authorize new overrides |
| HW-04 | Kill app, stop heartbeat, expire session, or restart helper | Independent restoration occurs; durable record survives failed restoration and retry |
| HW-05 | Invalid fan inventory/RPM, NaN, missing/stale temperature, unsupported encoding | No unsafe write; restore system control for any acquired fan |
| HW-06 | Unsigned/wrong-identity XPC client or a second Dev/production owner | Deny control; preserve the legitimate owner's lease |
| HW-07 | Update while lid/manual fan control is active; fail unregister/copy/register | Defer active update; retain recoverable bundle/state and surface error |
| HW-08 | Select automatic, maximum, bounded fixed RPM or curve on supported hardware | Actual measured capabilities determine controls; readback confirms state |
| HW-09 | Another GUI acquires hardware between an idle status and update prepare | Prepare rejects; no unregister occurs and its active override remains intact |
| HW-10 | Crash/restart after maintenance ACK or failed unregister; race Dev/production | Durable marker blocks rearm, foreign daemon releases shared lock, matching owner completes only after unregister barrier and new handshake |
| HW-11 | Close a busy Dev window, then end the production lease | Background status clears the stale update blocker without reopening the window |
| HW-12 | A valid integrity-signed app/helper uses ad-hoc signing or a wrong Developer ID/team/identifier | Candidate is rejected before unregister and swap |
| HW-13 | Intel fan interface has an additional Ftst key; a sensor value read fails after takeover | Restore uses the same metadata-selected control scheme and does not leave the manual mask set |

| HW-14 | Enable System or Keep Awake while the service is missing/pending approval | Start setup once per off-to-on transition; unrelated changes do not repeat the request; no hardware override is armed |
| HW-15 | Reopen a retained nonactivating panel after granting/revoking approval without an application-focus event, or lose the XPC connection | Banner reflects actual access, offers the next action, and clears after recovery; basic module functions remain available |
| HW-16 | Enable modules during maintenance, render snapshots, or leave both modules off | No competing registration, no system permission UI in snapshots/onboarding, and no irrelevant banner |

| HW-17 | Open cooling on a fanless Mac, then on a controllable-fan fixture | Unsupported state has no mode grid/Apply; actual native window matches measured content without a fixed empty footer |
| HW-18 | Select macOS control or CPU temperature; change language/theme | Selected-mode explanation identifies who sets speed; curve thresholds remain explicit; content stays readable and the window refits |
| HW-19 | Install the prepared Dev build and preview its release card | Installed version is the preparing version; latest card appears and dismisses, with its own persisted seen state |

| HW-20 | Expire a finite Awake lease with the lid already closed and music playing | Restore fans/sleep flag, then request native sleep only when macOS says closing this lid should sleep; verify actual playback stops and the power log records sleep on-device |
| HW-21 | End protected lid mode with an open lid, native external-display clamshell policy, or a fan-only lease | No forced sleep request; independent ordinary timer/Awake behavior is preserved |
| HW-22 | Fail enable before applying, crash after applying/before marking, or fail sleep request after resetting the flag | No sleep for unapplied intention; applied duty survives reset/restart and retries; the record clears only after restored settings and accepted request/policy |

| HW-23 | Turn cooling off/on in Monitor settings, then reopen/relaunch | Only the cooling row hides/reappears; the choice persists and no fan/lid control operation is sent |
| HW-24 | Apply maximum/fixed/CPU curve, return to macOS, stop, lose service or enter recovery | Only a confirmed active manual mode appears as quiet trailing text before the arrow; no button styling, stale label or additional poller |
| HW-25 | Hover cooling in both themes | Highlight has8pt extra space on each horizontal edge; icon/label/arrow columns remain aligned with metrics |

| HW-26 | Toggle protected lid on/off with an idle approved service | Confirm actual readback before the active indicator; bounded direct system commands avoid the former Process launch delay without weakening durable restoration |
| HW-27 | System command times out, floods output, exits nonzero or loses its child status | Reject the reply, release descriptors, reap only the owned child and preserve coordinator restoration/readback rules |
| HW-28 | Lid enable fails or another Hop owns the service; retry/off supersedes a late reply | Show the reason beneath Awake without opening Cooling or taking over another session; the current intent owns the error, successful retry/off clears it |

## Output engine retirement

| ID | Given / action | Expected observable result |
| --- | --- | --- |
| AUD-RET-01 | Replace, lose or stop a listening output while its former engine destructor is slow | Playback stops before DSP discard; final app-owned engine release runs off main, and the main run loop can process Quit |
| AUD-RET-02 | Borrow an engine during a throwing operation, or fail engine initialization | Owner survives the borrow and schedules one background release after stack unwinding |
| AUD-RET-03 | Configuration notification arrives during/after playback retirement | Synchronous notification bridge never queues an engine reference on main; stopped callbacks cannot touch the engine or restart the retired output |

| HW-26 | Change Awake duration while lid enable reply is delayed, while off is pending, or after failed enable | Root receives the latest deadline for a live on-intent; pending off and failed enable cannot be rearmed by a duration change |
| HW-27 | Start a new lease while an old lid sleep-request recovery is pending | Complete old recovery and report busy without active=true in the same transition; a later explicit request is independent |
