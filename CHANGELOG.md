# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [1.2.1] - 2026-11-17

### Fixed

- Volume and brightness slides follow the fingers without lag. macOS takes
  about 10 ms per synthesized media key, so a quick slide queued more than
  half a second of keys and the overlay trailed behind. The level is now set
  directly as the fingers move, and one key at most every 33 ms keeps the
  system overlay in step with it.

## [1.2.0] - 2026-11-17

### Added

- Scroll events are dropped while three or more fingers drive a bound slide
  or swipe, so a four-finger slide no longer scrolls the window under the
  pointer. The event tap runs on its own thread and only while such a
  gesture is bound.

### Changed

- A bound slide starts after 1 mm of movement instead of 3 mm.
- A running slide carries on when a finger slips off or lands late, instead
  of restarting and waiting for the threshold again.

## [1.1.0] - 2026-11-17

### Added

- Gesture editor window, opened with **Edit Gestures…** or by opening the app
  again: a searchable gesture list per device, a drawing of each gesture,
  actions picked from a menu, a shortcut recorder, an application picker, a
  sensitivity slider for slides and warnings for overlaps with macOS. It
  edits the configuration file in place and keeps its comments.
- English and Brazilian Portuguese interface, following the system language.
- `*-fine` actions that change volume, brightness and keyboard backlight by a
  quarter step.

### Changed

- The `volume`, `brightness` and `keyboard-backlight` presets move in
  quarter steps every 0.8 mm, covering the whole range in about 5 cm
  instead of 8 cm in 16 coarse steps, with one haptic tap per whole step.
- Steps may be as small as 0.2 mm.
- The menu's binding list is replaced by the editor.

## [1.0.0] - 2026-11-17

### Added

- Recognition of taps, double taps, hold and tap, swipes, brushes and
  physical multi-finger, edge and corner clicks on trackpads, and taps,
  swipes and holds on the Magic Mouse.
- Continuous slides with three or four fingers, two fingers on the Magic
  Mouse, and hold-slide, with presets for volume, brightness, keyboard
  backlight, zoom, tabs, history, undo, desktops and tracks.
- Actions: keystrokes resolved against the active keyboard layout, built-in
  system actions, extra mouse buttons, URLs with placeholders, applications,
  menu items, scripts, typed text, sounds, speech and timed sequences.
- TOML configuration with per-application scopes, Fn-only bindings, live
  reload, line-numbered errors and warnings for overlaps with macOS gestures.
- Menu bar app with an enable switch, binding list and login item.
- `check`, `trace`, `gestures` and `actions` commands.

[1.2.1]: https://github.com/rafaelcaetite/OpenGestures/releases/tag/v1.2.1
[1.2.0]: https://github.com/rafaelcaetite/OpenGestures/releases/tag/v1.2.0
[1.1.0]: https://github.com/rafaelcaetite/OpenGestures/releases/tag/v1.1.0
[1.0.0]: https://github.com/rafaelcaetite/OpenGestures/releases/tag/v1.0.0
