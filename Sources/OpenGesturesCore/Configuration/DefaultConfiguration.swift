import Foundation

public enum DefaultConfiguration {
    /// Written to disk the first time OpenGestures runs.
    public static let text = #"""
# OpenGestures configuration
#
# Changes are picked up as soon as this file is saved. Run
# `OpenGestures check` to validate it from the terminal.
#
# Full reference: https://github.com/rafaelcaetite/OpenGestures/blob/main/docs/configuration.md

[GENERAL]

haptic-feedback = true      # Tap the trackpad when a gesture fires
show-menu-bar-icon = true
dominant-hand = "right"     # Decides index-to-pinky vs pinky-to-index
# tap-duration = 300        # Milliseconds a finger may rest and still tap
# double-tap-interval = 300 # Milliseconds allowed between two taps
# swipe-distance = 18       # Millimetres a swipe must travel
# slide-step = 5            # Millimetres between two steps of a slide
# edge-size = 0.15          # Width of the edge zones for area clicks

# ----------------------------------------------------------------------------
# Trackpad bindings. Remove the # in front of a line to enable it.
#
# macOS keeps handling its own gestures. Before binding a gesture macOS
# already uses, turn that gesture off in System Settings > Trackpad.
# `OpenGestures check` lists every overlap.

[TRACKPAD]

# Continuous: slide four fingers up or down to change the volume.
# four-finger-slide = "volume"

# three-finger-double-tap = "play-pause"
# four-finger-tap = "mission-control"
# hold-left-tap-right = "next-tab"
# hold-right-tap-left = "previous-tab"
# bottom-right-corner-click = "show-desktop"
# index-to-pinky = "cmd+shift+4"   # Screenshot of a selection

# Bindings that only apply while Fn is held:
# fn+four-finger-slide = "brightness"

# A slide can drive any pair of actions:
# three-finger-slide = { left = "cmd+z", right = "cmd+shift+z", step = 10 }

# ----------------------------------------------------------------------------
# Bindings for one application, or every application except some:
#
# [TRACKPAD."Safari, Google Chrome"]
# four-finger-slide = "tabs"
#
# [TRACKPAD."!Terminal"]
# hold-left-tap-right = "return"

# ----------------------------------------------------------------------------
# Magic Mouse bindings.

[MOUSE]

# two-finger-tap = "middle-click"
# two-finger-slide = "volume"
"""#
}
