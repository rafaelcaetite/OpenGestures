import AppKit
import CMultitouch
import IOKit.hidsystem

/// Runs bindings off the input thread, one at a time and in order.
public final class ActionRunner: @unchecked Sendable {
    public struct Context: Sendable {
        public var gesture: Gesture
        public var direction: Direction?
        public var device: DeviceKind
        public var application: ApplicationIdentity?
        public var processIdentifier: pid_t?
    }

    private let queue = DispatchQueue(label: "\(Log.subsystem).actions", qos: .userInteractive)

    public init() {}

    public func perform(_ binding: ActionBinding, context: Context) {
        queue.async {
            for step in binding.steps {
                Self.run(step, context: context)
            }
        }
    }

    private static func run(_ step: ActionStep, context: Context) {
        switch step {
        case .keystroke(let keystroke):
            EventPoster.post(keystroke)
        case .builtIn(let action):
            perform(action)
        case .mouseButton(let number):
            EventPoster.click(button: number)
        case .openURL(let template):
            openURL(template)
        case .runScript(let path):
            runScript(path, context: context)
        case .menuCommand(let path):
            guard let pid = context.processIdentifier else { return }
            Accessibility.pressMenuItem(path, processIdentifier: pid)
        case .openApplication(let name):
            openApplication(name)
        case .typeText(let text):
            EventPoster.type(text)
        case .playSound(let name):
            DispatchQueue.main.async {
                let sound = NSSound(named: NSSound.Name(name)) ?? NSSound(contentsOfFile: (name as NSString).expandingTildeInPath, byReference: true)
                sound?.play()
            }
        case .speak(let text):
            launch("/usr/bin/say", arguments: [text])
        case .wait(let milliseconds):
            usleep(useconds_t(milliseconds) * 1000)
        }
    }

    private static func perform(_ action: BuiltInAction) {
        switch action {
        case .missionControl:
            dock("com.apple.expose.awake", fallback: "ctrl+up")
        case .appExpose:
            dock("com.apple.expose.front.awake", fallback: "ctrl+down")
        case .showDesktop:
            dock("com.apple.showdesktop.awake", fallback: "fn+f11")
        case .launchpad:
            let apps = URL(fileURLWithPath: "/System/Applications/Apps.app")
            if FileManager.default.fileExists(atPath: apps.path) {
                NSWorkspace.shared.open(apps)
            } else {
                dock("com.apple.launchpad.toggle", fallback: nil)
            }
        case .nextApp: ApplicationSwitcher.shared.cycle(forward: true)
        case .previousApp: ApplicationSwitcher.shared.cycle(forward: false)
        case .lastApp: keys("cmd+tab")
        case .nextTab: keys("ctrl+tab")
        case .previousTab: keys("ctrl+shift+tab")
        case .newTab: keys("cmd+t")
        case .closeTab: keys("cmd+w")
        case .reopenTab: keys("cmd+shift+t")
        case .maximize: Accessibility.zoomFocusedWindow()
        case .fullScreen: Accessibility.toggleFullScreen()
        case .minimize: Accessibility.minimizeFocusedWindow()
        case .playPause: EventPoster.postSystemKey(NX_KEYTYPE_PLAY)
        case .nextTrack: EventPoster.postSystemKey(NX_KEYTYPE_NEXT)
        case .previousTrack: EventPoster.postSystemKey(NX_KEYTYPE_PREVIOUS)
        case .mute: EventPoster.postSystemKey(NX_KEYTYPE_MUTE)
        case .volumeUp: EventPoster.postSystemKey(NX_KEYTYPE_SOUND_UP)
        case .volumeDown: EventPoster.postSystemKey(NX_KEYTYPE_SOUND_DOWN)
        case .brightnessUp: EventPoster.postSystemKey(NX_KEYTYPE_BRIGHTNESS_UP)
        case .brightnessDown: EventPoster.postSystemKey(NX_KEYTYPE_BRIGHTNESS_DOWN)
        case .keyboardBacklightUp: EventPoster.postSystemKey(NX_KEYTYPE_ILLUMINATION_UP)
        case .keyboardBacklightDown: EventPoster.postSystemKey(NX_KEYTYPE_ILLUMINATION_DOWN)
        case .volumeUpFine: EventPoster.postSystemKey(NX_KEYTYPE_SOUND_UP, fine: true)
        case .volumeDownFine: EventPoster.postSystemKey(NX_KEYTYPE_SOUND_DOWN, fine: true)
        case .brightnessUpFine: EventPoster.postSystemKey(NX_KEYTYPE_BRIGHTNESS_UP, fine: true)
        case .brightnessDownFine: EventPoster.postSystemKey(NX_KEYTYPE_BRIGHTNESS_DOWN, fine: true)
        case .keyboardBacklightUpFine: EventPoster.postSystemKey(NX_KEYTYPE_ILLUMINATION_UP, fine: true)
        case .keyboardBacklightDownFine: EventPoster.postSystemKey(NX_KEYTYPE_ILLUMINATION_DOWN, fine: true)
        case .middleClick: EventPoster.click(button: 3)
        }
    }

    private static func keys(_ text: String) {
        if let keystroke = try? Keystroke.parse(text) {
            EventPoster.post(keystroke)
        }
    }

    private static func dock(_ notification: String, fallback: String?) {
        if !OGDockSendNotification(notification as CFString), let fallback {
            keys(fallback)
        }
    }

    private static func openURL(_ template: String) {
        let context = Template.Context(clipboard: {
            DispatchQueue.main.sync { NSPasteboard.general.string(forType: .string) ?? "" }
        })
        let text = Template.render(template, context: context)
        guard let url = URL(string: text) else {
            Log.actions.error("Not a valid URL: \(text, privacy: .public)")
            return
        }
        NSWorkspace.shared.open(url)
    }

    private static func openApplication(_ name: String) {
        let workspace = NSWorkspace.shared
        if let url = workspace.urlForApplication(withBundleIdentifier: name) {
            workspace.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            launch("/usr/bin/open", arguments: ["-a", name])
        }
    }

    private static func runScript(_ path: String, context: Context) {
        var environment = ProcessInfo.processInfo.environment
        environment["OPENGESTURES_GESTURE"] = context.gesture.rawValue
        environment["OPENGESTURES_DEVICE"] = context.device.rawValue
        environment["OPENGESTURES_DIRECTION"] = context.direction?.rawValue
        environment["OPENGESTURES_APP"] = context.application?.name
        environment["OPENGESTURES_BUNDLE_ID"] = context.application?.bundleIdentifier
        launch((path as NSString).expandingTildeInPath, arguments: [], environment: environment)
    }

    private static func launch(_ path: String, arguments: [String], environment: [String: String]? = nil) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { finished in
            if finished.terminationStatus != 0 {
                Log.actions.error("\(path, privacy: .public) exited with status \(finished.terminationStatus)")
            }
        }
        do {
            try process.run()
        } catch {
            Log.actions.error("Could not run \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
