# Compatibility

OpenGestures runs on every Mac that runs **macOS 13 Ventura or later**, on
both Apple silicon and Intel. Releases ship as a single universal app.

- [System requirements](#system-requirements)
- [Macs](#macs)
- [Input devices](#input-devices)
- [Features that depend on hardware](#features-that-depend-on-hardware)
- [Permissions](#permissions)
- [What has been tested](#what-has-been-tested)
- [Reporting a device](#reporting-a-device)

## System requirements

| | |
| --- | --- |
| macOS | 13 Ventura, 14 Sonoma, 15 Sequoia, 26 Tahoe, and later |
| Processor | Apple silicon (arm64) or Intel (x86_64), one universal binary |
| Input | A built-in trackpad, a Magic Trackpad or a Magic Mouse |
| Permission | Accessibility, to send keys and read clicks |
| Disk | About 2 MB |
| Memory | About 8 MB while idle |

The minimum is enforced by the build: the app is compiled for macOS 13
with the current SDK, so it cannot call an API that macOS 13 lacks.

## Macs

These are the Macs that run macOS 13 or later, per Apple's
[macOS Ventura compatibility list](https://support.apple.com/102861), and
so the Macs OpenGestures runs on.

| Family | Models |
| --- | --- |
| MacBook Pro | 2017 and later, including every Apple silicon model |
| MacBook Air | 2018 and later, including every Apple silicon model |
| MacBook | 12-inch, 2017 |
| iMac | 2017 and later, and iMac Pro |
| Mac mini | 2018 and later |
| Mac Studio | All models |
| Mac Pro | 2019 and later |

Laptops use their built-in trackpad. Desktops need a Magic Trackpad or a
Magic Mouse; a laptop with the lid closed works the same way.

## Input devices

OpenGestures reads touches through MultitouchSupport, the framework macOS
itself uses for gestures, so it sees Apple's multitouch devices only.

| Device | Gestures | Haptic feedback | Click gestures |
| --- | --- | --- | --- |
| Built-in trackpad, MacBook Pro 2017+, MacBook Air 2018+, MacBook 2017 | All trackpad gestures | Yes | Yes |
| Magic Trackpad 2 (2015) and Magic Trackpad with USB-C (2024) | All trackpad gestures | Yes | Yes |
| Magic Trackpad, first generation (2010) | All trackpad gestures | No: it has no Taptic Engine | Yes |
| Magic Mouse, Magic Mouse 2 and Magic Mouse with USB-C | Mouse gestures | No | No |
| Other mice | None, but `mouse-natural-scrolling` applies to their wheels | No | No |
| Third-party trackpads | None: they do not report touches through it | No | No |
| Touch Bar | Ignored | | |

**Trackpad gestures** are every gesture in [gestures.md](gestures.md)
marked for the trackpad: taps and double taps with two to five fingers, hold
and tap, swipes and slides with three or four fingers, hold-slide, finger
rolls, and multi-finger, edge and corner clicks.

**Mouse gestures** are taps and double taps with one to three fingers,
swipes with one or two fingers, the two-finger slide, and hold and tap.

Several trackpads and mice can be connected at once; each has its own
recognizer, and `[TRACKPAD]` bindings apply to every trackpad.

### How devices are told apart

Each multitouch device is matched to its entry in the I/O Registry, and its
product name decides what it is: a device named as a Magic Mouse is a mouse,
built-in devices are always trackpads, and surfaces with four sensor rows or
fewer, such as the Touch Bar, are skipped. MultitouchSupport family numbers
are only a fallback, because they differ between models; family 113, for
example, is a Magic Mouse on some Macs and the built-in trackpad on some
MacBook Pros.

## Features that depend on hardware

| Feature | Needs | Otherwise |
| --- | --- | --- |
| Haptic feedback | A Force Touch trackpad | Gestures work without the tap |
| Volume slides that follow the fingers | An output whose volume macOS can set, such as built-in speakers, headphones or Bluetooth audio | One volume key per step, as with the keyboard; HDMI and DisplayPort outputs often have no volume control at all |
| Brightness slides that follow the fingers | A built-in display | Brightness keys, which macOS applies to Apple displays |
| Keyboard backlight slides | A backlit keyboard | Nothing happens |
| Blocking scroll during three- and four-finger gestures | Accessibility permission | The page may scroll during the gesture |
| Separate scroll direction for trackpad and mouse | Accessibility permission | The system setting applies to both |

## Permissions

OpenGestures needs **Accessibility** permission to send keystrokes, press
modifier keys for the app switcher, read physical clicks and adjust scroll
events. macOS asks on first launch; it can also be turned on in System
Settings > Privacy & Security > Accessibility.

On Macs managed by an organization, a configuration profile can prevent
granting Accessibility to unsigned apps. OpenGestures cannot work there
until an administrator allows it.

## What has been tested

| Configuration | How |
| --- | --- |
| MacBook Pro 16-inch 2019 (Intel), built-in trackpad, macOS 26 Tahoe | Used daily |
| Apple silicon, macOS 15 Sequoia | Every change is built for both architectures and the test suite runs on GitHub's Apple silicon runners |

The other configurations above are expected to work for the reasons given:
same framework, same APIs, same binary. They have not all been tried by
hand. If you use one that has not, a short report helps.

MultitouchSupport is a private framework, so a future macOS release could
change it. OpenGestures loads it at run time and reports an error instead
of crashing if it is missing.

## Reporting a device

Open an issue with the
[device report template](https://github.com/rafaelcaetite/OpenGestures/issues/new?template=device-report.yml),
including the output of:

```sh
sw_vers -productVersion
sysctl -n hw.model
OpenGestures trace     # names each device it listens to
```
