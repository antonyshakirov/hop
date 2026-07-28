# Automating Hop

Hop can be read and driven from outside the app — by an AI agent, a script, a
Shortcut, or by hand in a text editor. There is no API to sign up for and nothing
to install: it is two JSON files and a URL scheme.

Everything lives in

```
~/Library/Application Support/com.antonshakirov.minimo/
```

(`com.antonshakirov.minimo.dev` for the development build).

## Reading what Hop is doing

`agent-state.json` is written by Hop every few seconds and after every command:

```json
{
  "version": 1,
  "timer": {
    "mode": "countdown",
    "state": "running",
    "remainingSeconds": 812,
    "durationSeconds": 960
  },
  "tracking": { "task": "design", "todaySeconds": 5400 },
  "keepAwake": false,
  "lidMode": false,
  "keyboardLocked": false,
  "todos": [
    {
      "id": "72D31DD8-A52F-466E-86B6-F5BB37D44D0F",
      "text": "call the notary",
      "done": false,
      "note": "ask for the second copy",
      "important": true,
      "remindAt": "2026-07-28T15:00:00Z",
      "repeatDays": [2, 4]
    }
  ]
}
```

It is written whole each time, never patched, so a reader never sees half a file.

## Telling Hop what to do

Write `agent-commands.json`. Hop performs the commands and then EMPTIES the file
— an empty `commands` array is the acknowledgement, so a script can wait for it.
A file it cannot use at all is left alone rather than silently discarded.

```json
{
  "commands": [
    { "do": "timer.start", "minutes": 16 },
    { "do": "todo.add", "text": "call the notary", "note": "ask for the copy",
      "remindAt": "2026-07-28T15:00", "repeatDays": ["mon", "wed"], "important": true }
  ]
}
```

### Verbs

| Verb | Fields | Effect |
|---|---|---|
| `timer.start` | `seconds` / `minutes` / `hours` / `duration` | Starts a countdown |
| `timer.pause` | — | Pauses it |
| `timer.reset` | — | Back to idle |
| `stopwatch.start` / `stopwatch.stop` | — | The stopwatch |
| `tracker.start` | `task` | Tracks time on that task, creating it if it is new |
| `tracker.stop` | — | Stops the active task |
| `todo.add` | `text`, `note`, `remindAt`, `repeatDays`, `important` | Adds a to-do |
| `todo.complete` | `text` | Ticks the matching to-do |
| `todo.delete` | `text` | Removes it |
| `keepawake.on` / `keepawake.off` | `minutes` (optional) | Keeps the Mac awake, for a while or until told otherwise |
| `lid.on` / `lid.off` | — | Keep working with the lid shut |
| `keyboard.lock` / `keyboard.unlock` | `minutes` (optional) | Locks the keyboard for cleaning |
| `window.snap` | `position` | Moves the frontmost window: `center`, `maximize`, `leftHalf`, `rightHalf`, `topHalf`, `bottomHalf`, `topLeft`, `topRight`, `bottomLeft`, `bottomRight`, `leftThird`, `centerThird`, `rightThird`, `leftTwoThirds`, `rightTwoThirds`, `centerHalf`, `topThird`, `bottomThird` |
| `window.center` / `window.maximize` | — | Shorthands for the two common ones |
| `speedtest.run` | — | Runs a speed test |
| `color.pick` | — | Opens the eyedropper |
| `ocr.capture` | — | Starts a screen-text selection |
| `clipboard.copy` | `text` | Puts text on the pasteboard and into the history |
| `panel.open` | — | Opens Hop's panel |

The parser is deliberately forgiving, because the thing writing the file is often
a language model:

- the verb key may be `do`, `command` or `action`;
- a bare array works as well as `{"commands": [...]}`;
- a duration may be `{"minutes": 16}`, `{"seconds": 960}`, `"16m"`, `"1h30m"`,
  `"25:00"` or a bare number, which is read as minutes;
- `repeatDays` may be numbers (1 = Sunday) or names (`mon`, `tuesday`);
- `remindAt` may be ISO-8601 or a local `2026-07-28 15:00`;
- one malformed entry never discards the rest, and an unknown verb is skipped.

## hop:// links

The same vocabulary as a URL, which is what Shortcuts can open:

```
hop://timer/start?minutes=16
hop://timer/pause
hop://todo/add?text=call%20the%20notary&important=true&repeatDays=mon,wed
hop://tracker/start?task=design
hop://awake/on?minutes=30
hop://window/snap?position=center
hop://keyboard/lock?minutes=2
hop://lid/on
```

From a terminal or a script: `open "hop://timer/start?minutes=16"`.

### Siri and Shortcuts

Hop publishes five actions of its own — start a timer, add a task, lock the
keyboard, keep the Mac awake, recognize text on screen. They appear in Shortcuts
and Spotlight by themselves, and Siri takes them spoken:

- "Start a timer in Hop"
- "Add a task to Hop"
- "Lock the keyboard in Hop"
- "Keep the Mac awake with Hop"
- "Recognize text with Hop"

Apple's rule, not Hop's: **the phrase has to name the app**. "Lock the keyboard"
on its own goes to the system, not here.

For anything the five actions do not cover, a Shortcut whose only step is
**Open URL** with one of the links above works too, and you can name it whatever
you like to say.

## Editing the task list directly

`todos.json` is the to-do list, and Hop reloads it when something else changes
it. Append an item and it appears in the panel within a second:

```json
{
  "items": [
    { "id": "11111111-2222-4333-8444-555555555555",
      "text": "call the notary",
      "done": false,
      "note": "ask for the second copy",
      "important": true }
  ]
}
```

`id` must be a UUID and unique. `remindAt`, `firedAt` and `snoozedUntil` are
stored the way Foundation encodes a `Date` — seconds since 2001-01-01 UTC — so
`todo.add` through the command file is the easier route when a reminder is
involved.
