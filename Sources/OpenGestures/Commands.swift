import AppKit
import OpenGesturesCore

enum Commands {
    static let usage = """
        Usage: OpenGestures [command]

        Commands:
          run                 Start the menu bar app (the default)
          check [file]        Validate a configuration file and list overlaps with macOS gestures
          trace [--all]       Print gestures as they are recognized, without running actions;
                              --all reports every discrete gesture, bound or not
          gestures            List every gesture
          actions             List built-in actions, slide presets and action prefixes
          version             Print the version

        Configuration: \(ConfigurationStore.defaultFileURL.path)
        """

    // MARK: - check

    static func check(_ arguments: [String]) -> Int32 {
        let url = arguments.first.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? ConfigurationStore.defaultFileURL
        let store = ConfigurationStore(fileURL: url)
        do {
            let configuration = try store.load()
            print("\(url.path): \(configuration.bindingCount) binding(s), no errors")
            for warning in configuration.warnings {
                print("warning: \(warning)")
            }
            if !Accessibility.isTrusted {
                print("note: Accessibility permission has not been granted to this executable")
            }
            return 0
        } catch let error as ConfigurationError {
            printError("\(url.path): \(error)")
        } catch {
            printError("\(url.path): \(error.localizedDescription)")
        }
        return 1
    }

    // MARK: - trace

    static func trace(_ arguments: [String]) -> Never {
        let applications = FrontmostApplication()
        MainActor.assumeIsolated { applications.startTracking() }

        var configuration = Configuration()
        do {
            configuration = try ConfigurationStore().load()
        } catch {
            printError("warning: configuration not loaded (\(error)); only --all will report gestures")
        }

        let engine = GestureEngine(configuration: configuration, applications: applications)
        engine.performsActions = false
        engine.treatsAllGesturesAsBound = arguments.contains("--all")

        let clock = Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute().second().secondFraction(.fractional(3))
        engine.onEvent = { event in
            var line = "\(Date().formatted(clock))  \(event.device.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0))  "
            line += event.gesture.rawValue
            if let direction = event.direction { line += " \(direction.rawValue)" }
            if let binding = event.binding {
                line += "  →  \(binding.source)"
            } else {
                line += "  (not bound)"
            }
            print(line)
        }

        let fingerCounts = FingerCounter()
        let manager = MultitouchManager { device, contacts, timestamp in
            let touching = contacts.reduce(0) { $0 + ($1.state == 3 || $1.state == 4 ? 1 : 0) }
            if fingerCounts.update(device.id, touching) {
                print("                          \(touching) finger(s)")
            }
            engine.handleFrame(device: device, contacts: contacts, timestamp: timestamp)
        }
        manager.start()
        let devices = manager.connectedDevices
        if devices.isEmpty {
            printError("No multitouch devices found.")
            exit(1)
        }
        print("Tracing \(devices.map(\.displayName).joined(separator: ", ")). Press Ctrl-C to stop.")
        setvbuf(stdout, nil, _IOLBF, 0)
        dispatchMain()
    }

    private final class FingerCounter: @unchecked Sendable {
        private let lock = UnfairLock()
        private var counts: [UInt64: Int] = [:]

        func update(_ device: UInt64, _ count: Int) -> Bool {
            lock.withLock {
                defer { counts[device] = count }
                return counts[device, default: 0] != count
            }
        }
    }

    // MARK: - Listings

    static func listGestures() {
        for category in Gesture.Category.allCases {
            print("\(category.rawValue):")
            for gesture in Gesture.allCases where gesture.category == category {
                let devices = gesture.supportedDevices.map(\.sectionName).sorted().joined(separator: ", ")
                print("  \(gesture.rawValue.padding(toLength: 32, withPad: " ", startingAt: 0))\(devices.padding(toLength: 17, withPad: " ", startingAt: 0))\(gesture.summary)")
            }
            print("")
        }
        print("Prefix any gesture with fn+ to bind it only while Fn is held.")
    }

    static func listActions() {
        print("Built-in actions:")
        for action in BuiltInAction.allCases {
            print("  \(action.rawValue.padding(toLength: 24, withPad: " ", startingAt: 0))\(action.summary)")
        }
        print("  mouse-3 … mouse-32       Click an extra mouse button at the pointer")
        print("\nSlide presets:")
        for preset in SlidePreset.allCases {
            print("  \(preset.rawValue.padding(toLength: 24, withPad: " ", startingAt: 0))\(preset.summary)")
        }
        print("""

            Other actions:
              cmd+shift+4             A keystroke; modifiers are cmd, shift, opt, ctrl and fn
              url:https://…           Open a URL; {{clipboard|urlencode}}, {{date}}, {{time}} are expanded
              app:Safari              Open an application by name or bundle identifier
              menu:File > New Window  Choose a menu item in the frontmost application
              script:~/bin/tool       Run an executable; OPENGESTURES_* variables describe the gesture
              text:Hello              Type text
              sound:Glass             Play a system sound or a sound file
              say:Done                Speak text
              wait:200                Pause a sequence, in milliseconds
            """)
    }

    private static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
