import Foundation

/// What the issue says about the app and the device it ran on.
public struct ReportEnvironment: Sendable, Equatable {
    public var appName: String
    public var bundleID: String
    public var version: String
    public var build: String
    public var system: String
    public var model: String
    public var locale: String
    public var timeZone: String
    public var date: Date

    public init(appName: String, bundleID: String, version: String, build: String, system: String,
                model: String, locale: String, timeZone: String, date: Date) {
        self.appName = appName
        self.bundleID = bundleID
        self.version = version
        self.build = build
        self.system = system
        self.model = model
        self.locale = locale
        self.timeZone = timeZone
        self.date = date
    }

    /// The running app's, at `date`.
    public static func current(date: Date = Date(), bundle: Bundle = .main) -> ReportEnvironment {
        let info = bundle.infoDictionary ?? [:]
        let process = ProcessInfo.processInfo
        return ReportEnvironment(
            appName: (info["CFBundleDisplayName"] ?? info["CFBundleName"]) as? String ?? process.processName,
            bundleID: bundle.bundleIdentifier ?? "",
            version: info["CFBundleShortVersionString"] as? String ?? "",
            build: info["CFBundleVersion"] as? String ?? "",
            system: process.operatingSystemVersionString,
            model: Platform.deviceModel,
            locale: Locale.current.identifier,
            timeZone: TimeZone.current.identifier,
            date: date)
    }

    /// As a Markdown table.
    public var markdown: String {
        let rows: [(String, String)] = [
            ("App", "\(appName) (\(bundleID))"),
            ("Version", build.isEmpty ? version : "\(version) (\(build))"),
            ("System", system),
            ("Device", model),
            ("Locale", "\(locale), \(timeZone)"),
            ("Reported", Self.iso8601(date)),
        ]
        return (["| | |", "| --- | --- |"] + rows.map { "| \($0.0) | \(Self.escaped($0.1)) |" })
            .joined(separator: "\n")
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|")
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
