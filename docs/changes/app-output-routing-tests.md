# App listening routes/list acceptance — 2.4 development

- Save Chrome25/mute, pins/order/outputUID; app/Hop restart/newPID preserves all;
  names equal across differentbundleIDs stay separate. Offlinepinned disabled.
- Default destination follows macOS; explicitAirPods ignoresdefaultchanges.
- Explicitdevice loss holds source mute with no fallback; returning sameUID
  restores latestgain/mute only. Missing/failed savedroute visibly differsfromlive.
- RapidA→B, processreplacement, stop/restart: latebuild/callbackdiscarded;
  stoppedcaptureguard releasedonlywhenintentionallystopping/unowningprocesses.
- HopMixsend and physicalhardware/defaults unaffected by listeningroute edits.
- Sourceactivity beforegain/mute, no sorting/focus/geometryjump onupdates;
  visibleonlysampler stopswhenhidden; no physicalinputpermissionforoutput.
- EmptyInput/app-listcompact; Output/Input/HopMix UIkit/neutral/22languages;
  percent defaultplainreadout, no automaticfocus, fixedmute/buttonwidth.
- ActualYouTube volume100/25/mute, destinationA/B isolation, disconnect/reconnect,
  backgroundclose/relaunch; no tone. Voice/AirPodsmanualtests deferredbyuser.

## Local verification, 2026-10-25

- Available native suite: 1847 tests passed, warnings-as-errors build,
  canvas/export/live drawing checks, all22 translations and version2.4.0.
  AppKit line-fragment checks cover all changed audio labels at relevant widths.
- Independent audio review identified a process-replacement muting-guard gap,
  missing cancellation propagation and a retained bass-filter tail. Regressions
  first failed; fixes passed and the same reviewer confirmed the corrections.
- Native render matrix: RU/EN, both themes,480/520/720pt, Output/Input/HopMix-on/
  empty-input; other20 languages at480pt, Output and HopMix-on.88images total.
- Actual review UI: real built-in microphone listed, output chooser, pin/unpin,
  explicit speakers vs system-default, editable percentage returns to a readout.
  VLC25/mute/pin/explicit destination survived a normal quit/relaunch; original
  VLC100/unmuted/unpinned/system-default restored afterward. System output44%
  and built-in input81% were observed and left unchanged.
- HopMix was enabled with no selected sources; no physical microphone capture
  or tone. Closing Sound changed it to disabled while output routing remained
  enabled. Reopening/relaunch did not select sources or start HopMix.
- User postponed the new YouTube check. Real signal gain/mute, two physical
  output devices, disconnect/reconnect, local/send separation and voice/receiver
  acceptance remain unverified on this new routing backend. AirPods button is
  also explicitly deferred. No publication or production installation.
