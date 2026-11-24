import Foundation
import GitHubAuth
import GitHubIssues
import IssueComposer
import Observation

/// A bug report from inside the app: asked for by a shake (or Help › Report
/// a Bug… on a Mac), it opens the composer with a screenshot of the moment,
/// and files the issue in `repository` with the app's and device's details
/// and its recent logs below what the person wrote.
///
/// ShakeKit has no sign-in of its own. It files with the sign-in the host's
/// apps share (`GitHubSharedSignIn`, from its Info.plist): someone signed in
/// to that on this device can report; nobody else is ever shown a sign-in.
@MainActor
@Observable
public final class ShakeReport {
    /// Posted to ask for a report: by a shake, the menu command, or the app
    /// (`request()`). Its object is a `Trigger`.
    public static let requested = Notification.Name("ShakeKit.reportRequested")

    /// What asked for a report. A shake from someone who can't report does
    /// nothing; a deliberate request (the menu command, a Report a Bug
    /// button) from them says how to (`showsSignInNotice`).
    public enum Trigger: Sendable {
        case shake
        case request
    }

    /// What a deliberate request from someone who can't report says.
    nonisolated public static let signInNotice = "Sign in to Shireworks on this device to report bugs."

    /// Asks for a report deliberately, from the app's own Report a Bug
    /// button.
    public static func request() {
        NotificationCenter.default.post(name: requested, object: Trigger.request)
    }

    /// Whether this build offers reports at all: it carries the shared
    /// sign-in (its Info.plist names one) on a platform ShakeKit runs on.
    public static var isOffered: Bool { Platform.isSupported && GitHubSharedSignIn.main != nil }

    /// "owner/name", where the issue is filed.
    public let repository: String
    public let configuration: ShakeKitConfiguration
    /// The shared sign-in the issue is filed with; nil where the build
    /// carries none (or can't reach its lock).
    public let credentials: GitHubCredentials?
    /// The issue being written.
    public private(set) var composer: IssueComposerModel!
    /// Whether the composer is showing.
    public var isPresented = false
    /// Whether "Sign in to Shireworks on this device" is showing.
    public var showsSignInNotice = false
    /// Whether the logs go into the issue.
    public var includeLogs = true
    /// Whether shakes are ignored for now: a view that needs the shake
    /// itself pauses them (`.shakeToReportPaused(_:)`). A deliberate request
    /// still works.
    public var shakesPaused = false
    /// The app and device, as of the last report asked for.
    public private(set) var environment: ReportEnvironment
    /// The logs as they'll appear in the issue (redacted, capped); nil with none.
    public private(set) var logs: String?
    /// The last issue filed.
    public private(set) var filed: URL?

    @ObservationIgnored private let client: GitHubIssuesClient
    @ObservationIgnored private let logSource: LogSource
    @ObservationIgnored private let screenshot: @MainActor () -> Data?
    @ObservationIgnored private let reaches: @MainActor () -> Bool

    /// A report filed in `repository`. By default: the main bundle's
    /// configuration and shared sign-in, the app's own logs, and its key
    /// window's screenshot. `credentials` (a sign-in in place of the shared
    /// one, whose token is taken to reach far enough), `logSource`,
    /// `draftStore`, `send` and `screenshot` replace those, for tests.
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
        if let credentials {
            self.credentials = credentials
            reaches = { true }
        } else if let found = Platform.sharedSignIn(shared, scope: configuration.scope) {
            self.credentials = found.credentials
            reaches = found.reaches
        } else {
            self.credentials = nil
            reaches = { false }
        }
        self.logSource = logSource
        self.screenshot = screenshot ?? { Platform.keyWindowPNG() }
        environment = .current()
        let signIn = self.credentials
        let client = GitHubIssuesClient(token: {
            guard let signIn else { throw GitHubError(status: 401, message: ShakeReport.signInNotice) }
            return try await signIn.access()
        }, send: send)
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

    /// Whether a report can be filed now: someone is signed in to the shared
    /// sign-in on this device, with a token reaching the scope.
    public var canReport: Bool {
        guard let credentials, credentials.state == .signedIn else { return false }
        return reaches()
    }

    /// Opens the composer, with a screenshot of the app as it is now added
    /// to the draft. It does nothing when asked again while it's showing, or
    /// by a shake that's paused or from someone who can't report; a
    /// deliberate request from them shows the sign-in notice instead.
    public func present(_ trigger: Trigger = .request) {
        guard !isPresented else { return }
        if trigger == .shake, shakesPaused { return }
        // Signed in to the shared sign-in since this was made, perhaps.
        credentials?.reload()
        guard canReport else {
            if trigger == .request { showsSignInNotice = true }
            return
        }
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
            credentials?.refused()
            throw error
        }
    }
}
