import Foundation
import GitHubAuth
import GitHubIssues
import IssueComposer
import Observation

/// A bug report from inside the app: asked for by a shake (or Help › Report
/// a Bug… on a Mac), it opens the composer with a screenshot of the moment,
/// and files the issue in `repository` with the app's and device's details
/// and its recent logs below what the person wrote.
@MainActor
@Observable
public final class ShakeReport {
    /// Posted to ask for a report: by a shake, the menu command, or the app
    /// (`request()`). Its object is a `Trigger`.
    public static let requested = Notification.Name("ShakeKit.reportRequested")

    /// What asked for a report. A shake opens it only for someone signed in,
    /// so a shake in a build for anyone never springs a sign-in on them; a
    /// deliberate request (the menu command, a Report a Bug button) opens it
    /// either way, offering the sign-in.
    public enum Trigger: Sendable {
        case shake
        case request
    }

    /// Asks for a report deliberately, from the app's own Report a Bug
    /// button: it opens, with the sign-in if needed.
    public static func request() {
        NotificationCenter.default.post(name: requested, object: Trigger.request)
    }

    /// "owner/name", where the issue is filed.
    public let repository: String
    public let configuration: ShakeKitConfiguration
    /// The sign-in the issue is filed with.
    public let credentials: GitHubCredentials
    /// Whether that's the apps' shared sign-in (the host's), rather than
    /// ShakeKit's own: it isn't signed out from here.
    public let usesSharedSignIn: Bool
    /// The issue being written.
    public private(set) var composer: IssueComposerModel!
    /// Whether the composer is showing.
    public var isPresented = false
    /// Whether the logs go into the issue.
    public var includeLogs = true
    /// The app and device, as of the last report asked for.
    public private(set) var environment: ReportEnvironment
    /// The logs as they'll appear in the issue (redacted, capped); nil with none.
    public private(set) var logs: String?
    /// The last issue filed.
    public private(set) var filed: URL?

    @ObservationIgnored private let client: GitHubIssuesClient
    @ObservationIgnored private let logSource: LogSource
    @ObservationIgnored private let screenshot: @MainActor () -> Data?

    /// A report filed in `repository`. By default: the main bundle's
    /// configuration, the apps' shared sign-in when the host has one whose
    /// token reaches far enough (else ShakeKit's own), the app's own logs,
    /// and its key window's screenshot. `credentials`, `logSource`,
    /// `draftStore`, `send` and `screenshot` replace those, for tests and
    /// hosts with their own.
    public init(
        repository: String,
        configuration: ShakeKitConfiguration = .main,
        shared: GitHubSharedSignIn? = .main,
        credentials: GitHubCredentials? = nil,
        logSource: LogSource = AppLogSource(),
        draftStore: DraftStore? = nil,
        send: @escaping GitHubTransport.Send = GitHubTransport.network,
        screenshot: (@MainActor () -> Data?)? = nil
    ) {
        self.repository = repository
        self.configuration = configuration
        let chosen = credentials.map { ($0, false) } ?? Platform.credentials(configuration: configuration, shared: shared)
        self.credentials = chosen.0
        usesSharedSignIn = chosen.1
        self.logSource = logSource
        self.screenshot = screenshot ?? { Platform.keyWindowPNG() }
        environment = .current()
        let signIn = chosen.0
        let client = GitHubIssuesClient(token: { try await signIn.access() }, send: send)
        self.client = client
        let name = repository.replacingOccurrences(of: "/", with: "_")
        composer = IssueComposerModel(
            store: draftStore ?? FileDraftStore(name: "shake-report-\(name)"),
            upload: { attachment in
                try await client.uploadAttachment(
                    repository: repository, name: attachment.name,
                    contentType: attachment.contentType, data: attachment.data)
            },
            submit: { [weak self] submission in
                try await self?.file(submission)
            })
    }

    /// Opens the composer, with a screenshot of the app as it is now added
    /// to the draft. Asked again while it's showing, it does nothing; asked
    /// by a shake while nobody is signed in, neither.
    public func present(_ trigger: Trigger = .request) {
        guard !isPresented else { return }
        if trigger == .shake, credentials.state != .signedIn { return }
        if let png = screenshot() {
            let count = composer.draft.attachments.filter { $0.name.hasPrefix("screenshot-") }.count
            composer.attach(IssueAttachment(name: "screenshot-\(count + 1).png", contentType: "image/png", data: png))
        }
        environment = .current()
        let since = Date().addingTimeInterval(-configuration.logWindow)
        logs = ReportBody.logs(
            logSource.lines(since: since, subsystems: configuration.logSubsystems),
            limit: configuration.logLimit, redactions: configuration.redactions)
        isPresented = true
    }

    /// Files the issue: what the person wrote, then the app and device, then
    /// the logs if kept.
    func file(_ submission: IssueSubmission) async throws {
        let body = ReportBody.compose(
            written: submission.body, environment: environment, logs: includeLogs ? logs : nil)
        do {
            let issue = try await client.createIssue(
                in: repository, title: submission.title, body: body, labels: configuration.labels)
            filed = issue.htmlUrl
        } catch let error as GitHubError where error.status == 401 {
            credentials.refused()
            throw error
        }
    }
}
