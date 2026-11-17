import os

public enum Log {
    public static let subsystem = "io.github.rafaelcaetite.opengestures"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let input = Logger(subsystem: subsystem, category: "input")
    public static let actions = Logger(subsystem: subsystem, category: "actions")
    public static let configuration = Logger(subsystem: subsystem, category: "configuration")
}
