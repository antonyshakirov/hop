# Input source list: visual proposal

Stage: native visual mockup only. No application controller or settings change.

## Owner agreement

On 28 October 2026 the owner chose to collapse unpinned sources into Other Sources by default. System Default and pinned sources stay above the group. Earlier requests ask for reversible hiding and a familiar pin affordance.

## Proposed behavior shown

- System Default remains first and follows the macOS microphone.
- Selected and pinned sources remain visible above Other Sources. Existing pin.fill and ellipsis affordances match output app rows.
- Other Sources starts collapsed. Selecting a source brings it into the visible group; deselecting it does not move the row while its menu is open.
- An inactive source may be hidden through its menu. Hidden Sources opens a small restore list. Active sources cannot be hidden.
- Presentation changes never select a microphone, start capture, switch the system device, or erase a saved gain/mute setting.
- Known virtual devices carry a Virtual label. Classification must come from device transport metadata, not an app-running guess or a name blacklist.
- Window height fits its content. A long source list scrolls within the available screen height, retaining existing window behavior.

## Visual scope

Native AppKit proposal using current Hop Theme token values, mono typography, 28-point chips, 11-point row labels, 9-point details, existing SF Symbols, opaque slider thumbs. These drawings are not screenshots of an implemented feature. Mock data: System Default resolves to AirPods; MacBook mic is pinned; Spotify is selected; additional AirPods, ZoomAudioDevice and VLC are available; one inactive iPhone microphone is hidden.

Render in Russian and English, dark/light, at 480/520/720 points. Export compact, expanded and restore-list views at 520 points. Check exact text line fragments used for drawing, horizontal bounds and fitted window height. No audio, device enumeration, network, user preferences or live app automation.

## Next implementation boundary

After visual review, add stable-identity presentation preferences independently of source audio presets and expose confirmed pin/hide actions through the existing agent protocol. Do not silently hide currently selected sources during migration or change capture settings. Full localization and behavior/agent regressions belong to that implementation, not this mockup.

## Observed checks

48 native in-memory render cases (RU/EN, dark/light, 480/520/720 points, four list/menu states); 16 PNG exports at 520 points. The text renderer checks the same line fragments it draws: no wrapping, clipping or text outside the image frame. A full device name initially wrapped in all cases; the fixed source-name column now fits it with the inline pin. Compact, menu and light restore previews inspected. This confirms the mockup, not live controls or scrolling. No application tests rerun because application sources are unchanged.
