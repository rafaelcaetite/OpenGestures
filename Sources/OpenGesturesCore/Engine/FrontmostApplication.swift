import AppKit

/// Tracks the frontmost application without querying it on every gesture.
public final class FrontmostApplication: @unchecked Sendable {
    private let lock = UnfairLock()
    private var identity: ApplicationIdentity?
    private var pid: pid_t?

    public init() {}

    @MainActor
    public func startTracking() {
        update(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.update(application)
        }
    }

    public var current: ApplicationIdentity? {
        lock.withLock { identity }
    }

    public var processIdentifier: pid_t? {
        lock.withLock { pid }
    }

    private func update(_ application: NSRunningApplication?) {
        let identity = application.map {
            ApplicationIdentity(name: $0.localizedName, bundleIdentifier: $0.bundleIdentifier)
        }
        let pid = application?.processIdentifier
        lock.withLock {
            self.identity = identity
            self.pid = pid
        }
    }
}
