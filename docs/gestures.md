# Gestures

Every gesture name below can be used as a key in the `[TRACKPAD]` or
`[MOUSE]` section, as listed in the device column. Prefix a name with `fn+`
to bind it only while Fn is held. `OpenGestures gestures` prints the same
list.

```
Taps:
  one-finger-tap                  MOUSE            Tap with one finger
  two-finger-tap                  MOUSE, TRACKPAD  Tap with two fingers
  three-finger-tap                MOUSE, TRACKPAD  Tap with three fingers
  four-finger-tap                 TRACKPAD         Tap with four fingers
  five-finger-tap                 TRACKPAD         Tap with five fingers

Double taps:
  one-finger-double-tap           MOUSE            Double-tap with one finger
  two-finger-double-tap           MOUSE, TRACKPAD  Double-tap with two fingers
  three-finger-double-tap         MOUSE, TRACKPAD  Double-tap with three fingers
  four-finger-double-tap          TRACKPAD         Double-tap with four fingers
  five-finger-double-tap          TRACKPAD         Double-tap with five fingers

Hold and tap:
  hold-left-tap-right             MOUSE, TRACKPAD  Hold one finger, tap another to its right
  hold-right-tap-left             MOUSE, TRACKPAD  Hold one finger, tap another to its left
  hold-two-tap-left               MOUSE, TRACKPAD  Hold two fingers, tap to their left
  hold-two-tap-right              MOUSE, TRACKPAD  Hold two fingers, tap to their right
  hold-two-tap-between            MOUSE, TRACKPAD  Hold two fingers, tap between them
  hold-three-tap-left             MOUSE, TRACKPAD  Hold three fingers, tap to their left
  hold-three-tap-right            MOUSE, TRACKPAD  Hold three fingers, tap to their right

Swipes:
  one-finger-swipe                MOUSE            Swipe one finger in any direction
  one-finger-swipe-left           MOUSE            Swipe one finger left
  one-finger-swipe-right          MOUSE            Swipe one finger right
  one-finger-swipe-up             MOUSE            Swipe one finger up
  one-finger-swipe-down           MOUSE            Swipe one finger down
  two-finger-swipe                MOUSE            Swipe two fingers in any direction
  two-finger-swipe-left           MOUSE            Swipe two fingers left
  two-finger-swipe-right          MOUSE            Swipe two fingers right
  two-finger-swipe-up             MOUSE            Swipe two fingers up
  two-finger-swipe-down           MOUSE            Swipe two fingers down
  three-finger-swipe              TRACKPAD         Swipe three fingers in any direction
  three-finger-swipe-left         TRACKPAD         Swipe three fingers left
  three-finger-swipe-right        TRACKPAD         Swipe three fingers right
  three-finger-swipe-up           TRACKPAD         Swipe three fingers up
  three-finger-swipe-down         TRACKPAD         Swipe three fingers down
  four-finger-swipe               TRACKPAD         Swipe four fingers in any direction
  four-finger-swipe-left          TRACKPAD         Swipe four fingers left
  four-finger-swipe-right         TRACKPAD         Swipe four fingers right
  four-finger-swipe-up            TRACKPAD         Swipe four fingers up
  four-finger-swipe-down          TRACKPAD         Swipe four fingers down

Slides (continuous):
  two-finger-slide                MOUSE            Slide two fingers and keep moving
  three-finger-slide              TRACKPAD         Slide three fingers and keep moving
  four-finger-slide               TRACKPAD         Slide four fingers and keep moving
  hold-slide                      TRACKPAD         Hold one finger still and slide another

Brushes:
  index-to-pinky                  TRACKPAD         Land four fingers one after another, index first
  pinky-to-index                  TRACKPAD         Land four fingers one after another, little finger first

Physical clicks:
  three-finger-click              TRACKPAD         Press the trackpad with three fingers
  four-finger-click               TRACKPAD         Press the trackpad with four fingers
  edge-click                      TRACKPAD         Press with one finger near any edge
  corner-click                    TRACKPAD         Press with one finger in any corner
  left-edge-click                 TRACKPAD         Press with one finger in the left edge area
  right-edge-click                TRACKPAD         Press with one finger in the right edge area
  top-edge-click                  TRACKPAD         Press with one finger in the top edge area
  bottom-edge-click               TRACKPAD         Press with one finger in the bottom edge area
  left-edge-top-half-click        TRACKPAD         Press with one finger in the left edge top half area
  left-edge-bottom-half-click     TRACKPAD         Press with one finger in the left edge bottom half area
  right-edge-top-half-click       TRACKPAD         Press with one finger in the right edge top half area
  right-edge-bottom-half-click    TRACKPAD         Press with one finger in the right edge bottom half area
  top-edge-left-half-click        TRACKPAD         Press with one finger in the top edge left half area
  top-edge-right-half-click       TRACKPAD         Press with one finger in the top edge right half area
  bottom-edge-left-half-click     TRACKPAD         Press with one finger in the bottom edge left half area
  bottom-edge-right-half-click    TRACKPAD         Press with one finger in the bottom edge right half area
  left-edge-top-third-click       TRACKPAD         Press with one finger in the left edge top third area
  left-edge-middle-third-click    TRACKPAD         Press with one finger in the left edge middle third area
  left-edge-bottom-third-click    TRACKPAD         Press with one finger in the left edge bottom third area
  right-edge-top-third-click      TRACKPAD         Press with one finger in the right edge top third area
  right-edge-middle-third-click   TRACKPAD         Press with one finger in the right edge middle third area
  right-edge-bottom-third-click   TRACKPAD         Press with one finger in the right edge bottom third area
  top-edge-left-third-click       TRACKPAD         Press with one finger in the top edge left third area
  top-edge-middle-third-click     TRACKPAD         Press with one finger in the top edge middle third area
  top-edge-right-third-click      TRACKPAD         Press with one finger in the top edge right third area
  bottom-edge-left-third-click    TRACKPAD         Press with one finger in the bottom edge left third area
  bottom-edge-middle-third-click  TRACKPAD         Press with one finger in the bottom edge middle third area
  bottom-edge-right-third-click   TRACKPAD         Press with one finger in the bottom edge right third area
  top-left-corner-click           TRACKPAD         Press with one finger in the top left corner area
  top-right-corner-click          TRACKPAD         Press with one finger in the top right corner area
  bottom-left-corner-click        TRACKPAD         Press with one finger in the bottom left corner area
  bottom-right-corner-click       TRACKPAD         Press with one finger in the bottom right corner area
```

## How each kind is recognized

Distances are measured in millimetres on the surface, using the size the
device reports, so thresholds feel the same on a 13-inch MacBook and a Magic
Trackpad. Default values can be changed in `[GENERAL]`; see
[configuration.md](configuration.md#general-settings).

**Taps.** All fingers land within 150 ms, none moves more than 3 mm, each
lifts within `tap-duration` (300 ms), and no finger lands twice.

**Double taps.** Two taps with the same number of fingers, the second
starting within `double-tap-interval` (300 ms) of the first. A single tap is
delayed by that interval only when the matching double tap is bound;
otherwise it fires immediately.

**Hold and tap.** One to three fingers rest without moving more than 4 mm,
having landed at least 120 ms earlier, while another finger taps beside
them. The tap is classified by where it lands relative to the resting
fingers: left of all of them, right of all of them, or between two. Holds can
repeat while the fingers keep resting.

**Swipes.** Three or four fingers (one or two on a Magic Mouse) move
together. Once the centroid has moved 3 mm the gesture commits to the
dominant axis, and it fires once when it has travelled `swipe-distance`
(18 mm) along that axis. A swipe with a direction takes precedence over the
any-direction form.

**Slides.** Same start as a swipe, but a slide keeps firing: one step every
`step` millimetres (the binding's own, the preset's, or `slide-step`) in either direction along
the committed axis, for as long as the fingers stay down. Reversing the
movement reverses the steps. A slide only claims the axes its binding uses,
so a vertical-only slide leaves horizontal movement alone. When a slide and a
swipe are bound for the same fingers and axis, the slide wins.

**Hold slide.** One finger rests and a second finger, landing at least
120 ms later, moves. The moving finger drives the slide.

**Brushes.** Four fingers land one after another, in left-to-right or
right-to-left order, over 80 to 600 ms, and lift without moving. With the
right hand, left to right is index to pinky; set `dominant-hand = "left"` to
mirror this.

**Physical clicks.** Clicking the trackpad with three or four fingers
resting, or with a single finger inside an edge zone (`edge-size`, 15% of
the surface by default). A click that triggers a binding is consumed and
never reaches the application underneath. Area clicks are matched from the
most specific name to the most general: a named corner, `corner-click`, a
third of an edge, a half of an edge, a named edge, then `edge-click`. In a
corner without a corner binding, the edge the finger is deepest into is used.
