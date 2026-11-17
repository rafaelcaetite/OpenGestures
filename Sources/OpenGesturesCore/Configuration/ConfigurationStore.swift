import Foundation

/// Locates, creates and reads the configuration file.
public struct ConfigurationStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = ConfigurationStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    /// `$XDG_CONFIG_HOME/opengestures/config.toml`, or
    /// `~/.config/opengestures/config.toml` when the variable is unset.
    public static var defaultFileURL: URL {
        let environment = ProcessInfo.processInfo.environment
        let base: URL
        if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            base = URL(fileURLWithPath: xdg, isDirectory: true)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config", isDirectory: true)
        }
        return base.appendingPathComponent("opengestures", isDirectory: true).appendingPathComponent("config.toml")
    }

    public var directoryURL: URL { fileURL.deletingLastPathComponent() }

    /// Writes the default configuration if no file exists. Returns true if it
    /// created one.
    @discardableResult
    public func createIfMissing() throws -> Bool {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return false }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try DefaultConfiguration.text.write(to: fileURL, atomically: true, encoding: .utf8)
        return true
    }

    public func load() throws -> Configuration {
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        var configuration = try ConfigurationParser.parse(text)
        configuration.warnings += SystemGestures.conflicts(in: configuration)
        return configuration
    }
}
