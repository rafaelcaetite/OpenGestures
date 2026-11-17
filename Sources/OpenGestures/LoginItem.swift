import Foundation

/// Starts OpenGestures at login through a per-user launch agent.
///
/// A launch agent works for ad-hoc signed builds, unlike SMAppService, and
/// `KeepAlive.SuccessfulExit = false` restarts the app after a crash while
/// leaving it closed after Quit.
struct LoginItem {
    let label: String

    var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    func enable(executable: String) throws {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: plistURL, options: .atomic)
    }

    func disable() throws {
        if isEnabled {
            try FileManager.default.removeItem(at: plistURL)
        }
    }
}
