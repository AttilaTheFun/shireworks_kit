import Dispatch
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
/// The composer opens at once: the screenshot's image is taken first, but
/// its PNG is made, and the logs read (a second or more), after it shows,
/// off the main actor. Filing waits for both (`gatherTimeout` at most).
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

    /// What the issue says in place of logs still being read when it's filed
    /// (after `gatherTimeout`).
    nonisolated static let logsTooSlow = "The app's logs took too long to read, and were left out."

    /// Asks for a report deliberately, from the app's own Report a Bug
    /// button.
    public static func request() {
        NotificationCenter.default.post(name: requested, object: Trigger.request)
    }

    /// Whether this build offers reports at all: on Apple's systems, where
    /// it carries the shared sign-in (its Info.plist names one); on Isomer's
    /// hosts, always (Report a Bug, filed with the sign-in the host gives
    /// `.shakeToReport(credentials:)`, else answered with the sign-in
    /// notice); on Linux, never.
    public static var isOffered: Bool { Platform.offersReports(shared: GitHubSharedSignIn.main) }

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
    /// The logs as they'll appear in the issue (redacted, capped); nil with
    /// none, or while they're read (`isReadingLogs`).
    public private(set) var logs: String?
    /// What the issue says in their place where the logs aren't read on
    /// this platform (the log source's `omission`); nil where they are.
    public private(set) var logsOmission: String?
    /// Whether the logs are being read: from just before the composer opens
    /// until they're in (`logs`).
    public private(set) var isReadingLogs = false
    /// The last issue filed.
    public private(set) var filed: URL?

    @ObservationIgnored private let client: GitHubIssuesClient
    @ObservationIgnored private let logSource: LogSource
    /// Takes the screenshot, on the main actor, before the composer covers
    /// the window: what it returns makes its PNG, off it.
    @ObservationIgnored private let capture: @MainActor () -> (@Sendable () -> Data?)?
    @ObservationIgnored private let reaches: @MainActor () -> Bool
    /// The screenshot's PNG and the logs being made for the last report
    /// opened; filing waits for them.
    @ObservationIgnored private var gathering: Task<Void, Never>?
    /// Which report opened last, so logs read for an earlier one are dropped.
    @ObservationIgnored private var opened = 0
    /// How long filing waits for the logs and the screenshot before filing
    /// without what isn't in yet.
    @ObservationIgnored var gatherTimeout: Duration = .seconds(15)

    /// A report filed in `repository`. By default: the main bundle's
    /// configuration and shared sign-in, the app's own logs, and its key
    /// window's screenshot. `credentials` (a sign-in in place of the shared
    /// one, whose token is taken to reach far enough), `logSource`,
    /// `draftStore`, `send` and `screenshot` replace those, for tests.
    public convenience init(
        repository: String,
        configuration: ShakeKitConfiguration = .main,
        shared: GitHubSharedSignIn? = .main,
        credentials: GitHubCredentials? = nil,
        logSource: LogSource = AppLogSource(),
        draftStore: DraftStore? = nil,
        send: @escaping GitHubTransport.Send = GitHubTransport.network,
        screenshot: (@MainActor () -> Data?)? = nil
    ) {
        let capture: @MainActor () -> (@Sendable () -> Data?)?
        if let screenshot {
            capture = {
                guard let png = screenshot() else { return nil }
                return { png }
            }
        } else {
            capture = { Platform.keyWindowCapture() }
        }
        self.init(repository: repository, configuration: configuration, shared: shared, credentials: credentials,
                  logSource: logSource, draftStore: draftStore, send: send, capture: capture)
    }

    /// As above, the screenshot taken by `capture` (on the main actor) and
    /// its PNG made by what that returns (off it): for tests of a slow one.
    init(
        repository: String,
        configuration: ShakeKitConfiguration,
        shared: GitHubSharedSignIn?,
        credentials: GitHubCredentials?,
        logSource: LogSource,
        draftStore: DraftStore?,
        send: @escaping GitHubTransport.Send,
        capture: @escaping @MainActor () -> (@Sendable () -> Data?)?
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
        self.capture = capture
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
        composer.preparing = { [weak self] in await self?.gathered() }
    }

    /// Whether a report can be filed now: someone is signed in to the shared
    /// sign-in on this device, with a token reaching the scope.
    public var canReport: Bool {
        guard let credentials, credentials.state == .signedIn else { return false }
        return reaches()
    }

    /// Opens the composer at once, with a screenshot of the app as it is now
    /// added to the draft as soon as its PNG is made, and the logs once
    /// they're read (`isReadingLogs` meanwhile): both after it opens, off the
    /// main actor. It does nothing when asked again while it's showing, or
    /// by a shake that's paused or from someone who can't report; a
    /// deliberate request from them shows the sign-in notice instead.
    public func present(_ trigger: Trigger = .request) {
        guard !isPresented else { return }
        if trigger == .shake, shakesPaused { return }
        // Signed in to the shared sign-in since this was made, perhaps: a
        // keychain read or two, well under a millisecond.
        credentials?.reload()
        guard canReport else {
            if trigger == .request { showsSignInNotice = true }
            return
        }
        // The moment before the composer covers it: the image now, its PNG later.
        let png = capture()
        environment = .current()
        opened += 1
        let report = opened
        logs = nil
        logsOmission = nil
        isReadingLogs = true
        let source = logSource, configuration = configuration
        let since = Date().addingTimeInterval(-configuration.logWindow)
        gathering = Task { [weak self] in
            async let read = Self.offMain {
                ReportBody.logs(source.lines(since: since, subsystems: configuration.logSubsystems),
                                limit: configuration.logLimit, redactions: configuration.redactions)
            }
            if let png, let data = await Self.offMain(png) {
                self?.attachScreenshot(data)
            }
            let logs = await read
            guard let self, opened == report else { return }
            self.logs = logs
            logsOmission = logs == nil ? source.omission : nil
            isReadingLogs = false
        }
        isPresented = true
    }

    /// The next screenshot, added to the draft.
    private func attachScreenshot(_ png: Data) {
        let count = composer.draft.attachments.filter { $0.name.hasPrefix("screenshot-") }.count
        composer.attach(IssueAttachment(name: "screenshot-\(count + 1).png", contentType: "image/png", data: png))
    }

    /// `work` on a queue of its own, not the main actor or Swift's
    /// cooperative threads: reading the logs blocks for a second or more.
    nonisolated private static func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: work()) }
        }
    }

    /// Once the screenshot and the logs being made for the report showing
    /// are in, or `gatherTimeout` has passed.
    func gathered() async {
        guard let gathering else { return }
        let timeout = gatherTimeout
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let once = ResumeOnce(continuation)
            let timer = Task {
                try? await Task.sleep(for: timeout)
                once.resume()
            }
            Task {
                await gathering.value
                timer.cancel()
                once.resume()
            }
        }
    }

    /// Files the issue: what the person wrote, then the app and device, then
    /// the logs if kept (or why there are none).
    func file(_ submission: IssueSubmission) async throws {
        // Still reading them: `gatherTimeout` passed first.
        let unread = isReadingLogs ? Self.logsTooSlow : logsOmission
        let body = ReportBody.compose(
            written: submission.body, environment: environment,
            logs: includeLogs ? logs ?? unread.map { "_\($0)_" } : nil)
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

/// A continuation resumed by whichever of two tasks gets there first.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func resume() {
        let waiting = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        waiting?.resume()
    }
}
