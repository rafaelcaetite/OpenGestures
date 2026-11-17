import Foundation

/// Calls back when the configuration file changes.
///
/// Editors either rewrite a file in place or replace it atomically, so both
/// the file and its directory are watched. Events are coalesced and compared
/// against the file's modification date, so one save means one reload.
@MainActor
final class ConfigurationWatcher {
    private let url: URL
    private let onChange: @MainActor () -> Void
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private var lastModified: Date?

    init(url: URL, onChange: @escaping @MainActor () -> Void) {
        self.url = url
        self.onChange = onChange
        lastModified = modificationDate()
        directorySource = watch(url.deletingLastPathComponent().path, events: .write)
        fileSource = watch(url.path, events: [.write, .extend, .delete, .rename])
    }

    private func watch(_ path: String, events: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: events, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleCheck() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }

    private func scheduleCheck() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.check() }
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    private func check() {
        // An atomic save replaced the file; watch the new one.
        fileSource?.cancel()
        fileSource = watch(url.path, events: [.write, .extend, .delete, .rename])

        let modified = modificationDate()
        guard modified != nil, modified != lastModified else { return }
        lastModified = modified
        onChange()
    }

    private func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
