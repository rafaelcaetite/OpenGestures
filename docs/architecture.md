# Architecture

OpenGestures is a Swift package with three targets:

| Target | Purpose |
| --- | --- |
| `CMultitouch` | About 280 lines of C that load `MultitouchSupport.framework` with `dlopen`, declare its contact layout, and forward frames to a single handler. |
| `OpenGesturesCore` | Recognition, configuration, actions and the engine that connects them. Free of UI code and covered by tests. |
| `OpenGestures` | The executable: menu bar app, launch agent, file watcher and command-line interface. |

## Data flow

```
MultitouchSupport thread                          actions queue
────────────────────────                          ─────────────
contact frame ─▶ GestureEngine.handleFrame        ActionRunner
                   │  (unfair lock)                 ▲
                   ├─ convert contacts in place     │ only when a gesture
                   ├─ GestureRecognizer.process     │ completes
                   └─ resolve binding ──────────────┘

main thread
───────────
ClickInterceptor (event tap, only while click gestures are bound)
ConfigurationWatcher (DispatchSource on the file and its directory)
IOKit device notifications, wake notifications, menu
```

### Frames

`MultitouchSupport` calls back about a hundred times a second per device
while fingers are touching, and stops when the surface is clear. Frames are
processed synchronously on that thread instead of being queued, under one
`os_unfair_lock` shared with the click handler. Each device keeps a
preallocated touch buffer that is refilled in place, so a frame causes no
heap allocation. Frames that arrive with no fingers and no gesture in
progress return immediately.

### Recognition

`GestureRecognizer` is a state machine per device. A session runs from the
first finger landing to the last one lifting. Per finger it keeps landing
time, start position, current position and maximum travel, in small arrays
scanned linearly; with at most ten fingers, that is faster than hashing.

- Holds are decided as each finger lifts.
- Swipes and slides are decided while fingers move: after 3 mm the
  movement commits to an axis, and the binding decides whether it becomes a
  slide, a swipe, or is ignored.
- Taps and brushes are decided when the session ends.

The recognizer only asks the configuration what is bound at those decision
points, through the `GestureBindings` protocol, never on ordinary frames.
That keeps the per-frame cost to arithmetic: about 0.25 µs for a
four-finger slide on an Intel Core i9-9980HK.

Single taps that might become double taps are held back with a token, and
the engine schedules one timer to release them. Nothing is scheduled unless
the double tap is bound.

### Clicks

Click gestures need to swallow the click that triggered them, which only an
event tap can do. `ClickInterceptor` installs one for primary-button events
when, and only when, the configuration binds a click gesture. On a button
press it asks the engine to classify the fingers currently resting on the
trackpad; if a binding matches, the press, any drag and the release are all
consumed.

### Actions

`ActionRunner` runs bindings on one serial queue, so sequences never
interleave and the input thread never waits. Keystrokes press each modifier
as its own key event before the key, which some global hotkey listeners
require. Characters are mapped to key codes through the active keyboard
layout; the map is rebuilt on the main thread when the input source changes
and read from any thread afterwards. Media and brightness keys
are posted as system-defined events so macOS shows its usual overlays.

### Configuration

`TOMLParser` handles the subset of TOML the configuration needs and keeps
key order, line numbers and trailing comments, which feed error messages and
the bindings menu. `ConfigurationParser` validates gesture names (with
suggestions for typos), device support and value types, then
`SystemGestures` compares the bindings against the trackpad preferences
macOS keeps and reports overlaps.

## Idle cost

There are no timers or polling loops. The app wakes for touch frames,
device attach and detach notifications from IOKit, wake from sleep, changes
to the configuration file, changes to the Accessibility permission list, and
menu interaction. With the trackpad untouched it uses no CPU.

## Testing

`make test` runs the suite. Recognizer tests build touch frames from finger
positions and timestamps, so every gesture can be exercised without
hardware. `OpenGestures trace` is the complement on a real device.
