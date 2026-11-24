import Foundation

/// Where ShakeKit reads the app's recent logs. On Apple's systems,
/// `OSLogStore` for the app's own process (`AppLogSource`); a host on
/// another platform, or with a logger of its own, gives its own.
public protocol LogSource: Sendable {
    /// The log lines from `since` on, oldest first, from `subsystems` (the
    /// app's bundle id alone when empty).
    func lines(since: Date, subsystems: [String]) -> [String]
}

/// No logs: for tests, and where none can be read.
public struct NoLogs: LogSource {
    public init() {}
    public func lines(since: Date, subsystems: [String]) -> [String] { [] }
}

/// The current process's logs from `OSLogStore`, where it exists.
public struct AppLogSource: LogSource {
    public init() {}

    public func lines(since: Date, subsystems: [String]) -> [String] {
        Platform.logLines(since: since, subsystems: subsystems.isEmpty
            ? [Bundle.main.bundleIdentifier].compactMap { $0 } : subsystems)
    }
}
