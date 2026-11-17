# Configuration reference

OpenGestures reads `~/.config/opengestures/config.toml`, or
`$XDG_CONFIG_HOME/opengestures/config.toml` when that variable is set. The
file is created with comments on first launch and reloaded whenever it is
saved. If it contains an error, the error is shown in the menu with its line
number and the previous configuration stays in effect.

Validate a file from the terminal at any time:

```sh
OpenGestures check
OpenGestures check path/to/another.toml
```

The format is [TOML](https://toml.io), with one extension: bare keys may
contain `+`, so `fn+four-finger-tap` does not need quotes.

- [General settings](#general-settings)
- [Sections](#sections)
- [Bindings](#bindings)
- [Actions](#actions)
- [Built-in actions](#built-in-actions)
- [Slides](#slides)
- [Examples](#examples)

## General settings

```toml
[GENERAL]
haptic-feedback = true
show-menu-bar-icon = true
dominant-hand = "right"
tap-duration = 300
double-tap-interval = 300
swipe-distance = 18
slide-step = 5
edge-size = 0.15
trackpad-natural-scrolling = true
mouse-natural-scrolling = false
```

| Setting | Default | Range | Meaning |
| --- | --- | --- | --- |
| `haptic-feedback` | `true` | | Tap the trackpad when a binding runs. Slides use a lighter tap per step. |
| `show-menu-bar-icon` | `true` | | Hide the icon to run invisibly. Quit with `osascript -e 'quit app "OpenGestures"'`. |
| `dominant-hand` | `"right"` | `"left"`, `"right"` | Which way round `index-to-pinky` and `pinky-to-index` are. |
| `tap-duration` | `300` | 50–1000 ms | Longest a finger may stay down and still tap. |
| `double-tap-interval` | `300` | 100–1000 ms | Longest gap between the two taps of a double tap. |
| `swipe-distance` | `18` | 5–80 mm | How far a swipe travels before it fires. |
| `slide-step` | `5` | 0.2–100 mm | Distance between two steps of a slide, unless the binding sets its own. |
| `edge-size` | `0.15` | 0.05–0.4 | Width of the edge zones for area clicks, as a fraction of the surface. |
| `trackpad-natural-scrolling` | system | | Scroll direction for trackpads. Unset follows System Settings. |
| `mouse-natural-scrolling` | system | | Scroll direction for mice, wheel and Magic Mouse alike. Unset follows System Settings. |

macOS has one natural scrolling setting for every device. When the two
settings above differ from it, OpenGestures reverses scroll events from the
device that should go the other way, so the trackpad can scroll naturally
while a mouse wheel does not. Wheel events always count as a mouse;
continuous ones count as whichever surface has fingers on it. Leave System
Settings as it is: OpenGestures works out the difference itself.

## Sections

Bindings live in a section per device:

```toml
[TRACKPAD]   # Built-in trackpads and Magic Trackpads
[MOUSE]      # Magic Mouse
```

A section can be limited to some applications, or apply everywhere except
some, by naming them in the heading. Names are matched against the
application's name or its bundle identifier, without regard to case:

```toml
[TRACKPAD."Safari, com.google.Chrome"]   # Only in these applications
[TRACKPAD."!Terminal, Xcode"]            # Everywhere except these
```

When a gesture happens, OpenGestures looks for a binding in this order:

1. Sections limited to the frontmost application
2. Sections that exclude other applications
3. The plain `[TRACKPAD]` or `[MOUSE]` section

While Fn is held, `fn+` bindings are searched first in all of these, then
the ordinary ones. A gesture without a binding does nothing.

## Bindings

A binding is a gesture name, optionally prefixed with `fn+`, and a value.
See [gestures.md](gestures.md) for every gesture name.

```toml
three-finger-tap = "cmd+t"                                  # One action
four-finger-tap = ["cmd+a", "cmd+c"]                        # A sequence
index-to-pinky = { action = "cmd+shift+4", sound = "Pop" }  # With options
```

A comment written after a binding is kept when the gesture editor changes
that binding.

**Sequences** run their steps in order. `wait:MS` pauses between steps; the
waits in one sequence may add up to ten seconds. Bindings never run
concurrently: a sequence that is still running delays the next one.

**Options**, in the table form:

| Option | Meaning |
| --- | --- |
| `action` | A step or a sequence. |
| `haptic` | `true` or `false`, overriding `haptic-feedback` for this binding. |
| `sound` | Play a sound first, by system sound name (`Glass`, `Pop`, `Tink`…) or file path. |
| `say` | Speak text first. |

## Actions

| Form | Example | Effect |
| --- | --- | --- |
| Keystroke | `"cmd+shift+4"` | Press a key combination. |
| Built-in action | `"mission-control"` | See [below](#built-in-actions). |
| Mouse button | `"mouse-4"` | Click mouse button 3 to 32 at the pointer. `middle-click` is `mouse-3`. |
| URL | `"url:raycast://extensions/…"` | Open a URL. A value containing `://` needs no prefix. |
| Application | `"app:Safari"` | Open or switch to an application, by name or bundle identifier. |
| Menu item | `"menu:View > Enter Full Screen"` | Choose a menu item in the frontmost application. |
| Script | `"script:~/bin/clean-desktop"` | Run an executable file. |
| Text | `"text:Kind regards,"` | Type text. |
| Sound | `"sound:Glass"` | Play a sound. |
| Speech | `"say:Done"` | Speak text. |
| Pause | `"wait:250"` | Wait, in a sequence. |

### Keystrokes

Join modifiers and a key with `+`. Modifiers are `cmd` (`command`, `⌘`),
`shift` (`⇧`), `opt` (`option`, `alt`, `⌥`), `ctrl` (`control`, `⌃`) and
`fn`. An uppercase letter implies Shift.

Named keys: `return`, `enter`, `tab`, `space`, `delete`, `forward-delete`,
`escape`, `up`, `down`, `left`, `right`, `home`, `end`, `page-up`,
`page-down`, `help`, `keypad-enter` and `f1` to `f20`. Characters that are
awkward to write can be named: `plus`, `minus`, `equal`, `comma`, `period`,
`slash`, `backslash`, `semicolon`, `quote`, `backtick`, `left-bracket`,
`right-bracket`. `ctrl++` also works.

Characters are resolved against the active keyboard layout when the
keystroke is sent, so `cmd+z` presses the key labelled Z on AZERTY, QWERTZ
and other layouts too.

### URL placeholders

| Placeholder | Example output |
| --- | --- |
| `{{clipboard}}` | Text on the clipboard |
| `{{date}}` | `2026-11-17` |
| `{{time}}` | `14:05` |
| `{{datetime}}` | `2026-11-17T14:05:09-03:00` |
| `{{timestamp}}` | `1794935109` |
| `{{date:EEEE d MMMM}}` | Any [date format pattern](https://www.unicode.org/reports/tr35/tr35-dates.html#Date_Field_Symbol_Table) |

Filters follow a bar and can be chained: `urlencode`, `trim`, `lowercase`,
`uppercase`. For example
`"url:https://duckduckgo.com/?q={{clipboard|trim|urlencode}}"`.

### Scripts

Scripts are run directly, so they need a `#!` line and execute permission
(`chmod +x`). Output is discarded. These environment variables describe what
triggered them:

| Variable | Example |
| --- | --- |
| `OPENGESTURES_GESTURE` | `four-finger-slide` |
| `OPENGESTURES_DIRECTION` | `up` (slides only) |
| `OPENGESTURES_DEVICE` | `trackpad` |
| `OPENGESTURES_APP` | `Safari` |
| `OPENGESTURES_BUNDLE_ID` | `com.apple.Safari` |

## Built-in actions

| Action | Effect |
| --- | --- |
| `mission-control` | Open Mission Control |
| `app-expose` | Show all windows of the frontmost application |
| `show-desktop` | Show the desktop |
| `launchpad` | Open Launchpad, or Apps on macOS 26 |
| `next-app`, `previous-app` | Bring the next or previous open application forward, in Dock order (Finder first, then kept applications, then the rest) |
| `last-app` | Switch to the last used application (⌘⇥) |
| `next-tab`, `previous-tab` | Move between tabs (⌃⇥, ⌃⇧⇥) |
| `new-tab`, `close-tab`, `reopen-tab` | ⌘T, ⌘W, ⌘⇧T |
| `maximize` | Zoom the focused window |
| `full-screen` | Toggle full screen for the focused window |
| `minimize` | Minimize the focused window |
| `play-pause`, `next-track`, `previous-track` | Media keys |
| `mute`, `volume-up`, `volume-down` | Volume keys, with the system overlay |
| `brightness-up`, `brightness-down` | Display brightness keys |
| `keyboard-backlight-up`, `keyboard-backlight-down` | Keyboard backlight keys |
| `volume-up-fine`, `volume-down-fine`, `brightness-up-fine`, `brightness-down-fine`, `keyboard-backlight-up-fine`, `keyboard-backlight-down-fine` | A quarter of a step, like pressing the key with ⌥⇧ |
| `middle-click` | Middle click at the pointer |

## Slides

`two-finger-slide` (Magic Mouse), `three-finger-slide`, `four-finger-slide`
and `hold-slide` are continuous: they run an action for every `step`
millimetres of movement. Give them a preset name:

```toml
four-finger-slide = "volume"
```

| Preset | Up / right | Down / left | Step |
| --- | --- | --- | --- |
| `volume` | `volume-up-fine` | `volume-down-fine` | 0.8 mm |
| `brightness` | `brightness-up-fine` | `brightness-down-fine` | 0.8 mm |
| `keyboard-backlight` | `keyboard-backlight-up-fine` | `keyboard-backlight-down-fine` | 0.8 mm |
| `zoom` | `cmd+=` | `cmd+-` | 8 mm |
| `undo` | right: `cmd+shift+z` | left: `cmd+z` | 10 mm |
| `tabs` | right: `next-tab` | left: `previous-tab` | 15 mm |
| `history` | right: `cmd+]` | left: `cmd+[` | 25 mm |
| `spaces` | right: `ctrl+right` | left: `ctrl+left` | 25 mm |
| `tracks` | right: `next-track` | left: `previous-track` | 25 mm |
| `apps` | right: `next-app` | left: `previous-app` | 25 mm |

The level presets move in quarter steps, 64 from bottom to top, so the
whole range takes about 5 cm. Their haptic tap comes once per whole step.
They set the output volume (Core Audio) or the built-in display's
brightness directly, so the level follows the fingers at once, and send a
media key at most every 33 ms to keep the system overlay in step. Outputs
without a settable volume fall back to one media key per step.

Or a table with any of `up`, `down`, `left` and `right`, each taking any
binding value, plus optional `step`, `haptic` and `preset`. Keys in the
table override the preset:

```toml
three-finger-slide = { up = "cmd+=", down = "cmd+-", step = 6 }
hold-slide = { preset = "volume", step = 1.5, haptic = false }
```

The first movement past 3 mm decides the axis. If the binding has no
direction on that axis the slide stays out of the way, so `"volume"` on four
fingers leaves four-finger horizontal swipes to macOS.

## Examples

A fuller example is in [`examples/config.toml`](../examples/config.toml).
