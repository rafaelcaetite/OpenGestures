# Troubleshooting

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

## Gestures stop after sleep or reconnecting a trackpad

OpenGestures restarts its devices after waking and whenever a multitouch
device is attached or removed. If they still stop, toggle **Enabled** in the
menu and report the issue with the output of `log show --last 10m
--predicate 'subsystem == "io.github.rafaelcaetite.opengestures"' --info`.

## A slide is too fast or too slow

Lower `step` for more steps per distance, raise it for fewer:

```toml
four-finger-slide = { preset = "volume", step = 3 }
```

or change `slide-step` in `[GENERAL]` for every slide.

## Taps are missed or fire by accident

Raise `tap-duration` if deliberate taps are missed. If a single tap feels
delayed, it is waiting for a possible double tap; that only happens when the
double tap with the same number of fingers is bound.
