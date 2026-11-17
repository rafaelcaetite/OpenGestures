import AppKit

/// Brings the next or previous open application forward.
///
/// Applications are ordered as the Dock shows them: Finder, then the kept
/// applications in their Dock order, then the others in launch order, so
/// repeated swipes walk across the Dock instead of bouncing between the two
/// most recent applications.
///
/// `NSRunningApplication.activate` is ignored when called from a background
/// app on recent macOS, so the application is opened instead, which brings
/// the running copy forward like a click on its Dock icon. Only used from the
/// action queue.
final class ApplicationSwitcher: @unchecked Sendable {
    static let shared = ApplicationSwitcher()

    /// The application most recently asked to come forward. Activation
    /// takes a moment, so quick repeated steps count from here rather than
    /// from a frontmost application that has not caught up yet.
    private var lastTarget: (pid: pid_t, time: TimeInterval)?

    func cycle(forward: Bool) {
        let workspace = NSWorkspace.shared
        let applications = Self.ordered(workspace.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated && $0.bundleURL != nil
        })
        guard applications.count > 1 else { return }

        let now = ProcessInfo.processInfo.systemUptime
        var current = workspace.frontmostApplication?.processIdentifier
        if let lastTarget, now - lastTarget.time < 0.6 {
            current = lastTarget.pid
        }
        let index = applications.firstIndex { $0.processIdentifier == current }
        let next: Int
        if let index {
            next = (index + (forward ? 1 : -1) + applications.count) % applications.count
        } else {
            next = forward ? 0 : applications.count - 1
        }

        let target = applications[next]
        guard let url = target.bundleURL else { return }
        lastTarget = (target.processIdentifier, now)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.openApplication(at: url, configuration: configuration)
    }

    private static func ordered(_ applications: [NSRunningApplication]) -> [NSRunningApplication] {
        let dock = ["com.apple.finder"] + dockApplications()
        func rank(_ application: NSRunningApplication) -> Int {
            application.bundleIdentifier.flatMap { dock.firstIndex(of: $0) } ?? dock.count
        }
        // Sorting by rank keeps launch order among applications not in the Dock.
        return applications.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    private static func dockApplications() -> [String] {
        let items = CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString) as? [[String: Any]]
        return (items ?? []).compactMap { item in
            (item["tile-data"] as? [String: Any])?["bundle-identifier"] as? String
        }
    }
}
