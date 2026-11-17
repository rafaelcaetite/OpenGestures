# Contributing

Bug reports and pull requests are welcome.

## Reporting a problem

Please include your macOS version, Mac model, the device involved (built-in
trackpad, Magic Trackpad or Magic Mouse), the relevant part of your
configuration, and what `OpenGestures trace` prints while you perform the
gesture.

## Making changes

```sh
make test         # Unit tests
make app          # Build the app bundle
make install      # Build, install to ~/Applications and relaunch
```

Guidelines:

- Keep the input path cheap. `GestureEngine.handleFrame` and
  `GestureRecognizer.process` run about a hundred times a second; they must
  not allocate, block or dispatch on ordinary frames.
- Add a recognizer test for every gesture change. The `Harness` in
  `GestureRecognizerTests.swift` builds frames from finger positions.
- New gestures need an entry in `Gesture`, a line in `docs/gestures.md`, and
  device support in `Gesture.supportedDevices`.
- New actions need parsing in `BindingParser`, execution in `ActionRunner`,
  and documentation in `docs/configuration.md`.
- Update `CHANGELOG.md` under an Unreleased heading.

## Releasing

1. Update `Version.current` in `Sources/OpenGestures/Version.swift` and the
   changelog.
2. Tag the commit `vX.Y.Z` and push the tag. The release workflow builds a
   universal app and attaches it to a GitHub release.
