# OpenGestures

Custom trackpad and Magic Mouse gestures for macOS, including continuous
gestures that keep acting while your fingers move: slide four fingers up to
raise the volume, sideways to move through tabs, and so on.

OpenGestures is a small menu bar app configured with a plain text file. It
reads raw touch data, recognizes taps, double taps, swipes, slides, hold and
tap combinations, finger brushes and clicks in the corners or along the
edges of the trackpad, and turns them into keystrokes, media keys, URLs,
menu commands, scripts and more.

[Português](README.pt-BR.md)

## Highlights

- **Continuous gestures.** A slide fires one step for every few millimetres
  of movement, in either direction, for as long as the fingers stay down.
  Volume, brightness, zoom, tabs, undo and desktops are built in, and any two
  actions can be paired.
- **75 gestures** on the trackpad and the Magic Mouse. See
  [docs/gestures.md](docs/gestures.md).
- **Per-application bindings**, bindings that only apply while Fn is held,
  and multi-step sequences.
- **Live configuration.** The file is reloaded as soon as you save it. A
  mistake is reported with its line number, and the last valid configuration
  stays active.
- **Light.** A 1.3 MB universal binary with no dependencies. Recognizing a
  frame takes about a quarter of a microsecond, nothing is allocated while
  fingers move, and the app uses no CPU while the trackpad is idle: there is
  no polling anywhere.

## Requirements

- macOS 13 Ventura or later, on Apple silicon or Intel
- A built-in trackpad, Magic Trackpad or Magic Mouse
- Xcode or the Command Line Tools (`xcode-select --install`) to build

## Installation

```sh
git clone https://github.com/rafaelcaetite/OpenGestures.git
cd OpenGestures
make install
```

This builds a release binary for your Mac, installs `OpenGestures.app` into
`~/Applications`, starts it, and registers it to open at login. Use
`make install ARCHS="arm64 x86_64"` for a universal build, and
`make install PREFIX=/Applications` to install for all users.

On first launch macOS asks for **Accessibility** permission, which
OpenGestures needs to send keystrokes and handle clicks. Turn it on in
System Settings > Privacy & Security > Accessibility. The permission is
tied to the bundle identifier, so it survives later rebuilds.

To call the command-line interface by name, run `make link`, which adds
`opengestures` to `~/.local/bin`.

## Quick start

The configuration lives at `~/.config/opengestures/config.toml` and is
created, fully commented, on first launch. Open it from the menu bar icon
with **Edit Configuration…**:

```toml
[TRACKPAD]
four-finger-slide = "volume"                 # Slide up or down to change the volume
three-finger-double-tap = "play-pause"
hold-left-tap-right = "next-tab"             # Rest a finger, tap to its right
bottom-right-corner-click = "show-desktop"
fn+four-finger-slide = "brightness"          # The same slide while holding Fn

three-finger-slide = { left = "cmd+z", right = "cmd+shift+z", step = 10 }

[TRACKPAD."Safari, Google Chrome"]
four-finger-slide = "tabs"

[MOUSE]
two-finger-tap = "middle-click"
```

Save the file and the new bindings apply immediately.

### Gestures macOS already uses

OpenGestures observes the trackpad; it does not stop macOS from responding
to the same movement. If you bind a gesture that macOS also uses, such as
four-finger vertical swipes for Mission Control, turn the macOS gesture off
in System Settings > Trackpad > More Gestures. `OpenGestures check` lists
every overlap, and so does the menu.

## Configuration

A binding is a gesture name and what it does:

| Value | Effect |
| --- | --- |
| `"cmd+shift+4"` | Press a key combination (`cmd`, `shift`, `opt`, `ctrl`, `fn`) |
| `"mission-control"` | Run a [built-in action](docs/configuration.md#built-in-actions) |
| `"url:https://example.com/?q={{clipboard\|urlencode}}"` | Open a URL with placeholders |
| `"app:Safari"` | Open an application |
| `"menu:File > New Window"` | Choose a menu item in the frontmost app |
| `"script:~/bin/tool"` | Run an executable |
| `"text:Kind regards"` | Type text |
| `["cmd+c", "wait:100", "app:Notes"]` | Run several steps in order |
| `{ action = "cmd+w", haptic = false, sound = "Pop" }` | Add options |

Slides take a preset (`volume`, `brightness`, `keyboard-backlight`, `zoom`,
`tabs`, `history`, `undo`, `spaces`, `tracks`) or a table with any of `up`,
`down`, `left` and `right` plus an optional `step` in millimetres.

The full reference, including general settings and scoping rules, is in
[docs/configuration.md](docs/configuration.md).

## Command line

```
OpenGestures check [file]   Validate a configuration and list overlaps with macOS gestures
OpenGestures trace [--all]  Print gestures as they are recognized, without running actions
OpenGestures gestures       List every gesture
OpenGestures actions        List built-in actions, presets and action prefixes
```

`trace` is the quickest way to see what OpenGestures recognizes while you
experiment. With `--all` it reports every discrete gesture, bound or not.

## How it works

OpenGestures reads contact frames from `MultitouchSupport.framework`, the
private framework behind macOS's own gesture handling, about a hundred times
a second while fingers are down. Each device has a recognizer, a small state
machine that is fed frames synchronously on the framework's thread, so no
work is queued per frame. When a gesture completes, its binding is resolved
against the frontmost application and run on a separate serial queue.
Physical clicks are only intercepted when a click gesture is bound.

[docs/architecture.md](docs/architecture.md) covers the design in more detail.

Because the framework is private, a future macOS release could change it.
OpenGestures loads it at run time and reports a clear error rather than
crashing if it disappears.

## Development

```sh
make test       # Run the test suite
make app        # Build .build/OpenGestures.app
make zip        # Build a distributable archive
```

The recognizer, configuration parser and action parsing are covered by unit
tests that feed synthetic touch frames; no hardware is needed to run them.
See [CONTRIBUTING.md](CONTRIBUTING.md).

## Uninstalling

```sh
make uninstall
```

Your configuration in `~/.config/opengestures` is kept. Remove OpenGestures
from System Settings > Privacy & Security > Accessibility as well.

## Acknowledgements

The contact layout of MultitouchSupport was documented by the
reverse-engineering work behind projects such as
[Jitouch](https://github.com/JitouchApp/Jitouch), whose gesture vocabulary
inspired several of the gestures here.

## License

[MIT](LICENSE)
