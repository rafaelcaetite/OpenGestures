import AppKit
import OpenGesturesCore

// Finder and launchd may pass a process serial number argument; it is not ours.
let arguments = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-psn_") }

switch arguments.first {
case nil, "run":
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) {
        application.run()
    }
case "check":
    exit(Commands.check(Array(arguments.dropFirst())))
case "trace":
    Commands.trace(Array(arguments.dropFirst()))
case "gestures":
    Commands.listGestures()
case "actions":
    Commands.listActions()
case "version", "--version", "-v":
    print(Version.current)
case "help", "--help", "-h":
    print(Commands.usage)
default:
    FileHandle.standardError.write(Data("Unknown command \"\(arguments.first ?? "")\".\n\n\(Commands.usage)\n".utf8))
    exit(64)
}
