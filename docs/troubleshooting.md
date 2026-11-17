# Troubleshooting

## macOS says the app cannot be opened

Releases are not notarized. Open System Settings > Privacy & Security,
find the message about OpenGestures near the bottom and choose **Open
Anyway**. This is needed once per download.

## A trackpad or mouse is not recognized

Run `OpenGestures trace`; it names every device it listens to. Only Apple
multitouch devices are supported: built-in trackpads, Magic Trackpads and
Magic Mice (see [compatibility.md](compatibility.md)). If yours is one of
them and is missing, or listed as the wrong kind, please send a
[device report](https://github.com/rafaelcaetite/OpenGestures/issues/new?template=device-report.yml).

## Nothing happens

1. Check the menu bar icon. A warning triangle means Accessibility
   permission is missing or the configuration has an error; open the menu
   for details.
2. Run `OpenGestures check` to validate the configuration.
3. Run `OpenGestures trace` and perform the gesture. If it is printed with
   `(not bound)`, the name in the configuration does not match, or the
   binding is limited to another application. If nothing is printed, try
   `OpenGestures trace --all`.

## Keystrokes are not sent

Accessibility permission is missing or stale. Open System Settings >
Privacy & Security > Accessibility, remove OpenGestures with the minus
button, then add `~/Applications/OpenGestures.app` again or relaunch it to
get the prompt.

Builds made with `make` keep the same code signing requirement, so the
permission survives rebuilds. A build signed some other way may need to be
granted again.

## macOS also reacts to my gesture

macOS keeps handling its own gestures. Turn off the overlapping one in
System Settings > Trackpad > More Gestures. `OpenGestures check` names
each overlap.

## The page scrolls during a three- or four-finger gesture

macOS starts scrolling as soon as two fingers move. OpenGestures drops
scroll events once three or more fingers drive a bound gesture, which needs
the Accessibility permission. If scrolling still leaks through, check that
OpenGestures is enabled in System Settings > Privacy & Security >
Accessibility.

## Gestures stop after sleep or reconnecting a trackpad

OpenGestures restarts its devices after waking and whenever a multitouch
device is attached or removed. If they still stop, toggle **Enabled** in the
menu and report the issue with the output of `log show --last 10m
--predicate 'subsystem == "io.github.rafaelcaetite.opengestures"' --info`.

## A slide is too fast or too slow

Move the **Sensitivity** slider in the gesture editor, or set `step` in the
file. Lower values mean more steps per distance:

```toml
four-finger-slide = { preset = "volume", step = 0.5 }
```

Volume, brightness and keyboard backlight move in quarter steps, so the
default 0.8 mm covers the whole range in about 5 cm.

or change `slide-step` in `[GENERAL]` for every slide.

## Taps are missed or fire by accident

Raise `tap-duration` if deliberate taps are missed. If a single tap feels
delayed, it is waiting for a possible double tap; that only happens when the
double tap with the same number of fingers is bound.
