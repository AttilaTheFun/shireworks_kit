import Foundation

/// Where ShakeKit reads the app's recent logs. On Apple's systems,
/// `OSLogStore` for the app's own process (`AppLogSource`); a host on
/// another platform, or with a logger of its own, gives its own.
public protocol LogSource: Sendable {
    /// The log lines from `since` on, oldest first, from `subsystems` (the
    /// app's bundle id alone when empty).
    func lines(since: Date, subsystems: [String]) -> [String]
    /// What the report says in place of the logs where this source reads
    /// none on this platform; nil (the default) where it reads them.
    var omission: String? { get }
}

extension LogSource {
    public var omission: String? { nil }
}

/// No logs: for tests, and where none can be read.
public struct NoLogs: LogSource {
    public init() {}
    public func lines(since: Date, subsystems: [String]) -> [String] { [] }
}

/// The current process's logs from `OSLogStore`, where it exists: on
/// Apple's systems. Elsewhere (Isomer's hosts) it reads none, and the report
/// says so (`omission`).
public struct AppLogSource: LogSource {
    /// What a report says where the app's logs aren't read.
    public static let notRead = "The app's logs aren't read on this platform yet."

    public init() {}

    public var omission: String? { Platform.readsLogs ? nil : Self.notRead }

    public func lines(since: Date, subsystems: [String]) -> [String] {
        Platform.logLines(since: since, subsystems: subsystems.isEmpty
            ? [Bundle.main.bundleIdentifier].compactMap { $0 } : subsystems)
    }
}
