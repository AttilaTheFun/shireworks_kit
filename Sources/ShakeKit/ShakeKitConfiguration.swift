import Foundation

/// How ShakeKit reports, from the host's Info.plist (stamped by its CI) or
/// given in code. Whether it reports at all is the shared sign-in's to say
/// (`GitHubSharedSignIn`): ShakeKit has no sign-in of its own.
public struct ShakeKitConfiguration: Sendable, Equatable {
    /// What the shared sign-in's token must reach for ShakeKit to file with
    /// it: `public_repo` for a public repository, `repo` for a private one.
    public static let defaultScope = "public_repo"

    public static let scopeKey = "ShakeKitScope"

    public var scope: String
    /// How far back the logs go.
    public var logWindow: TimeInterval
    /// The most log text put in the issue, newest kept. GitHub takes 65,536
    /// characters in a body.
    public var logLimit: Int
    /// The log subsystems included; empty for the app's bundle id alone.
    public var logSubsystems: [String]
    /// The labels the issue gets.
    public var labels: [String]
    /// Extra patterns (regular expressions) blanked out of the logs.
    public var redactions: [String]

    public init(
        scope: String = Self.defaultScope,
        logWindow: TimeInterval = 15 * 60,
        logLimit: Int = 40_000,
        logSubsystems: [String] = [],
        labels: [String] = ["shake-report"],
        redactions: [String] = []
    ) {
        self.scope = scope
        self.logWindow = logWindow
        self.logLimit = logLimit
        self.logSubsystems = logSubsystems
        self.labels = labels
        self.redactions = redactions
    }

    /// The configuration an Info.plist gives: its `ShakeKitScope` where set
    /// (a value a build didn't fill in, `$(…)`, counts as none), the default
    /// otherwise.
    public static func from(info: [String: Any]?) -> ShakeKitConfiguration {
        var configuration = ShakeKitConfiguration()
        if let text = (info?[scopeKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty, !text.hasPrefix("$(") {
            configuration.scope = text
        }
        return configuration
    }

    /// The main bundle's.
    public static var main: ShakeKitConfiguration { from(info: Bundle.main.infoDictionary) }
}
