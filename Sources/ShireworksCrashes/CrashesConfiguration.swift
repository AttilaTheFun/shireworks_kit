import Foundation

/// How Crashes files, from the host's Info.plist (stamped by its CI) or
/// given in code. Whether it files at all is the shared sign-in's to say
/// (`GitHubSharedSignIn`): Crashes has no sign-in of its own.
public struct CrashesConfiguration: Sendable, Equatable {
    /// The Info.plist key naming the repository crashes are filed in.
    public static let repositoryKey = "ShireworksRepository"
    /// The Info.plist key (a Boolean) that files the reason and the
    /// breadcrumbs in a public repository too.
    public static let publicDetailsKey = "ShireworksCrashesPublicDetails"

    /// "owner/name", where crashes are filed; nil for none (they're kept,
    /// and filed by a build that names one).
    public var repository: String?
    /// The labels a crash's issue gets.
    public var labels: [String]
    /// Extra patterns (regular expressions) blanked out of what is filed,
    /// beside GitHubIssues' `IssueRedaction.builtIn`.
    public var redactions: [String]
    /// The most crashes kept unfiled: the newest.
    public var maxStored: Int
    /// How long a crash is kept unfiled.
    public var maxAge: TimeInterval
    /// Whether crashes are filed at launch (or only kept, for a build that
    /// files them later, or a test).
    public var files: Bool
    /// Whether an issue in a public repository carries the exception's
    /// reason and the breadcrumbs, as a private one's does. Off by default:
    /// they may carry what the user typed or saw, which redaction can't
    /// tell apart, and a public repository's issues are anyone's to read.
    public var publicDetails: Bool

    public init(
        repository: String? = nil,
        labels: [String] = ["crash"],
        redactions: [String] = [],
        maxStored: Int = 20,
        maxAge: TimeInterval = 30 * 24 * 60 * 60,
        files: Bool = true,
        publicDetails: Bool = false
    ) {
        self.repository = repository
        self.labels = labels
        self.redactions = redactions
        self.maxStored = maxStored
        self.maxAge = maxAge
        self.files = files
        self.publicDetails = publicDetails
    }

    /// The configuration an Info.plist gives: its `ShireworksRepository`
    /// where set (a value a build didn't fill in, `$(…)`, counts as none),
    /// and `ShireworksCrashesPublicDetails` where it's the Boolean true; the
    /// defaults otherwise.
    public static func from(info: [String: Any]?) -> CrashesConfiguration {
        var configuration = CrashesConfiguration()
        if let text = (info?[repositoryKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty, !text.contains("$("), text.contains("/") {
            configuration.repository = text
        }
        configuration.publicDetails = info?[publicDetailsKey] as? Bool == true
        return configuration
    }

    /// The main bundle's.
    public static var main: CrashesConfiguration { from(info: Bundle.main.infoDictionary) }
}
