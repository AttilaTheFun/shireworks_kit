import Dispatch
import Foundation
import GitHubAuth
import GitHubIssues
import IssueComposer
import Testing

@testable import ShireworksShake

struct ConfigurationTests {
    @Test func defaultScopeWithoutInfo() {
        #expect(ShakeKitConfiguration.from(info: nil).scope == "public_repo")
    }

    @Test func infoSetsTheScope() {
        #expect(ShakeKitConfiguration.from(info: ["ShakeKitScope": " repo "]).scope == "repo")
    }

    @Test func unfilledOrEmptyScopeTakesTheDefault() {
        #expect(ShakeKitConfiguration.from(info: ["ShakeKitScope": "$(SHAKE_KIT_SCOPE)"]).scope == "public_repo")
        #expect(ShakeKitConfiguration.from(info: ["ShakeKitScope": ""]).scope == "public_repo")
    }
}

struct PlatformTests {
    /// The app's logs are read on Apple's systems alone; elsewhere the report says why there are none.
    @Test func appLogsReadOnAppleSystemsAlone() {
        #if canImport(Darwin)
        #expect(AppLogSource().omission == nil)
        #else
        #expect(AppLogSource().omission == AppLogSource.notRead)
        #expect(AppLogSource().lines(since: .distantPast, subsystems: []).isEmpty)
        #endif
    }

    /// Reports are offered by the shared sign-in on Apple's systems, always on Isomer's hosts, never on Linux.
    @Test func reportsOfferedWhereThereAreViews() {
        let shared = GitHubSharedSignIn(clientID: "Ov23example", keychainGroup: "group", lockGroup: "lock")
        #if canImport(UIKit) || canImport(AppKit)
        #expect(Platform.offersReports(shared: shared) && !Platform.offersReports(shared: nil))
        #elseif canImport(SwiftUI)
        #expect(Platform.offersReports(shared: shared) && Platform.offersReports(shared: nil))
        #else
        #expect(!Platform.offersReports(shared: shared) && !Platform.offersReports(shared: nil))
        #endif
    }
}

struct ReportBodyTests {
    @Test func redactsTokensEmailsAndQueries() {
        let line = "sent ghp_abcdefghij0123456789 for someone@example.com to https://api.example.com/x?key=secret&b=2"
        let redacted = ReportBody.redacted(line)
        #expect(!redacted.contains("ghp_abcdefghij"))
        #expect(!redacted.contains("someone@example.com"))
        #expect(!redacted.contains("key=secret"))
        #expect(redacted.contains("https://api.example.com/x?<redacted>"))
    }

    @Test func redactsTheHostsOwnPatterns() {
        #expect(ReportBody.redacted("user 12345 signed in", extra: [#"user \d+"#]) == "<redacted> signed in")
    }

    @Test func keepsTheNewestLinesUnderTheLimit() throws {
        let lines = (1...100).map { "line \($0)" }
        let logs = try #require(ReportBody.logs(lines, limit: 60))
        #expect(logs.contains("line 100"))
        #expect(!logs.contains("line 1\n"))
        #expect(logs.contains("of 100 lines"))
        #expect(logs.hasPrefix("<details>"))
    }

    @Test func noLogsNoSection() {
        #expect(ReportBody.logs([], limit: 100) == nil)
    }

    @Test func aFenceTheLogsCantClose() throws {
        let logs = try #require(ReportBody.logs(["```", "after"], limit: 100))
        #expect(logs.contains("~~~~"))
    }

    @Test func composesWrittenThenEnvironmentThenLogs() {
        let body = ReportBody.compose(written: "It crashed.\n", environment: .fixture, logs: "LOGS")
        let written = body.range(of: "It crashed.")!.lowerBound
        let table = body.range(of: "| App |")!.lowerBound
        let logs = body.range(of: "LOGS")!.lowerBound
        #expect(written < table && table < logs)
    }

    @Test func theTableEscapesPipes() {
        var environment = ReportEnvironment.fixture
        environment.appName = "A|B"
        #expect(environment.markdown.contains("A\\|B"))
    }
}

extension ReportEnvironment {
    static let fixture = ReportEnvironment(
        appName: "Example", bundleID: "com.example.app", version: "1.2.0", build: "42",
        system: "Version 27.2", model: "iPhone17,1", locale: "en_US", timeZone: "America/New_York",
        date: Date(timeIntervalSince1970: 1_793_526_060))
}

private struct FixedLogs: LogSource {
    let lines: [String]
    func lines(since: Date, subsystems: [String]) -> [String] { lines }
}

/// Holds whoever waits on it until the test opens it: a log read or a screenshot's PNG as slow as the test needs.
private final class Gate: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    func wait() {
        semaphore.wait()
        semaphore.signal()
    }
    func open() { semaphore.signal() }
}

/// Logs that take until `gate` opens to read, as OSLogStore's take a second or more.
private struct SlowLogs: LogSource {
    let gate: Gate
    let lines: [String]
    func lines(since: Date, subsystems: [String]) -> [String] {
        gate.wait()
        return lines
    }
}

/// A source that reads none here, as AppLogSource on Isomer's hosts.
private struct UnreadLogs: LogSource {
    func lines(since: Date, subsystems: [String]) -> [String] { [] }
    var omission: String? { AppLogSource.notRead }
}

private final class FakeGitHub: @unchecked Sendable {
    private let lock = NSLock()
    private var asked: [GitHubRequest] = []
    var requests: [GitHubRequest] { lock.withLock { asked } }

    lazy var send: GitHubTransport.Send = { [self] request in
        lock.withLock { asked.append(request) }
        let path = request.url.path
        if request.url.host == "uploads.github.com" {
            return GitHubAnswer(status: 201, data: Data(#"{"url": "https://github.com/user-attachments/assets/abc"}"#.utf8))
        }
        if path == "/repos/owner/app", request.method == "GET" {
            return GitHubAnswer(status: 200, data: Data(#"{"id": 1234}"#.utf8))
        }
        if path == "/repos/owner/app/issues", request.method == "POST" {
            return GitHubAnswer(status: 201, data: Data(Self.issue.utf8))
        }
        return GitHubAnswer(status: 404, data: Data(#"{"message": "Not Found"}"#.utf8))
    }

    static let issue = #"{"id": 1, "node_id": "I_1", "number": 7, "title": "Crash", "body": "", "state": "open", "#
        + #""state_reason": null, "labels": [], "user": {"login": "octocat", "type": "User"}, "assignees": [], "#
        + #""comments": 0, "html_url": "https://github.com/owner/app/issues/7", "created_at": "2026-11-01T09:41:00Z", "#
        + #""updated_at": "2026-11-01T09:41:00Z", "closed_at": null}"#
}

@MainActor
struct ShakeReportTests {
    private func report(github: FakeGitHub, logs: [String] = ["12:00:00.000 [ui] tapped Save"]) -> ShakeReport {
        let store = MemoryTokenStore(["Ov23example": GitHubToken(access: "gho_fixture", scope: "public_repo")])
        let credentials = GitHubCredentials(clientID: "Ov23example", scope: "public_repo", store: store)
        return ShakeReport(
            repository: "owner/app",
            configuration: ShakeKitConfiguration(),
            shared: nil,
            credentials: credentials,
            logSource: FixedLogs(lines: logs),
            draftStore: MemoryDraftStore(),
            send: github.send,
            screenshot: { Data([0x89, 0x50, 0x4E, 0x47]) })
    }

    /// A signed-in report whose logs take until `logs` opens to read, and whose screenshot's PNG until `png` does.
    private func slowReport(github: FakeGitHub, logs: Gate, png: Gate) -> ShakeReport {
        let store = MemoryTokenStore(["Ov23example": GitHubToken(access: "gho_fixture", scope: "public_repo")])
        return ShakeReport(
            repository: "owner/app", configuration: ShakeKitConfiguration(), shared: nil,
            credentials: GitHubCredentials(clientID: "Ov23example", scope: "public_repo", store: store),
            logSource: SlowLogs(gate: logs, lines: ["12:00:00.000 [ui] tapped Save"]), draftStore: MemoryDraftStore(),
            send: github.send,
            capture: {
                { () -> Data? in
                    png.wait()
                    return Data([0x89, 0x50, 0x4E, 0x47])
                }
            })
    }

    @Test func presentAttachesAScreenshotAndGathersLogs() async {
        let report = report(github: FakeGitHub())
        report.present()
        #expect(report.isPresented)
        await report.gathered()
        #expect(report.composer.draft.attachments.map(\.name) == ["screenshot-1.png"])
        #expect(report.logs?.contains("tapped Save") == true)
        #expect(!report.isReadingLogs)
        // A second shake while it's showing does nothing.
        report.present()
        await report.gathered()
        #expect(report.composer.draft.attachments.count == 1)
    }

    /// The sheet opens at once, while the logs are read: they come in after.
    @Test func presentOpensBeforeSlowLogsAreRead() async {
        let logs = Gate(), png = Gate()
        png.open()
        let report = slowReport(github: FakeGitHub(), logs: logs, png: png)
        report.present(.shake)
        #expect(report.isPresented)
        #expect(report.isReadingLogs)
        #expect(report.logs == nil && report.logsOmission == nil)
        logs.open()
        await report.gathered()
        #expect(!report.isReadingLogs)
        #expect(report.logs?.contains("tapped Save") == true)
    }

    /// The sheet opens at once, while the screenshot's PNG is made: it's attached after.
    @Test func presentOpensBeforeASlowScreenshotIsMade() async {
        let logs = Gate(), png = Gate()
        logs.open()
        let report = slowReport(github: FakeGitHub(), logs: logs, png: png)
        report.present(.shake)
        #expect(report.isPresented)
        #expect(report.composer.draft.attachments.isEmpty)
        png.open()
        await report.gathered()
        #expect(report.composer.draft.attachments.map(\.name) == ["screenshot-1.png"])
    }

    /// Created before the logs and the screenshot are in, the issue waits for them and files them both.
    @Test func filingWaitsForTheLogsAndScreenshotStillComing() async throws {
        let github = FakeGitHub()
        let logs = Gate(), png = Gate()
        let report = slowReport(github: github, logs: logs, png: png)
        report.present()
        report.composer.draft.title = "Crash on save"
        let submitting = Task { await report.composer.submit() }
        try await Task.sleep(for: .milliseconds(100))
        #expect(report.composer.state == .submitting)
        #expect(github.requests.isEmpty)
        png.open()
        logs.open()
        await submitting.value

        #expect(report.composer.state == .submitted)
        let create = try #require(github.requests.first { $0.url.path == "/repos/owner/app/issues" })
        let body = (try JSONSerialization.jsonObject(with: create.body ?? Data()) as? [String: Any])?["body"] as? String ?? ""
        #expect(body.contains("tapped Save"))
        #expect(body.contains("https://github.com/user-attachments/assets/abc"))
        #expect(!body.contains("couldn't be uploaded"))
    }

    /// Logs that never come in hold the issue back only so long: it's filed without them, saying so.
    @Test func filingGivesUpOnLogsAfterTheTimeout() async throws {
        let github = FakeGitHub()
        let logs = Gate(), png = Gate()
        png.open()
        defer { logs.open() }
        let report = slowReport(github: github, logs: logs, png: png)
        report.gatherTimeout = .milliseconds(200)
        report.present()
        report.composer.draft.title = "Crash"
        await report.composer.submit()

        #expect(report.composer.state == .submitted)
        let create = try #require(github.requests.first { $0.url.path == "/repos/owner/app/issues" })
        let body = (try JSONSerialization.jsonObject(with: create.body ?? Data()) as? [String: Any])?["body"] as? String ?? ""
        #expect(body.contains("_\(ShakeReport.logsTooSlow)_"))
        #expect(!body.contains("tapped Save"))
    }

    @Test func signedOutAShakeDoesNothingAndARequestSaysToSignIn() {
        let github = FakeGitHub()
        let signedOut = GitHubCredentials(clientID: "Ov23example", store: MemoryTokenStore(), canSignInByCode: false)
        let report = ShakeReport(
            repository: "owner/app", configuration: ShakeKitConfiguration(), shared: nil,
            credentials: signedOut, logSource: FixedLogs(lines: []), draftStore: MemoryDraftStore(),
            send: github.send, screenshot: { Data([1]) })
        #expect(!report.canReport)
        report.present(.shake)
        #expect(!report.isPresented && !report.showsSignInNotice)
        #expect(report.composer.draft.attachments.isEmpty)
        report.present(.request)
        #expect(!report.isPresented)
        #expect(report.showsSignInNotice)
    }

    @Test func withoutASharedSignInNothingCanReport() {
        let report = ShakeReport(
            repository: "owner/app", configuration: ShakeKitConfiguration(), shared: nil,
            logSource: FixedLogs(lines: []), draftStore: MemoryDraftStore(), send: FakeGitHub().send,
            screenshot: { Data([1]) })
        #expect(report.credentials == nil)
        #expect(!report.canReport)
        report.present(.request)
        #expect(!report.isPresented && report.showsSignInNotice)
    }

    @Test func aPausedShakeDoesNothingButARequestStillOpens() {
        let report = report(github: FakeGitHub())
        report.shakesPaused = true
        report.present(.shake)
        #expect(!report.isPresented)
        report.present(.request)
        #expect(report.isPresented)
    }

    @Test func aShakeOpensItWhenSignedIn() {
        let report = report(github: FakeGitHub())
        report.present(.shake)
        #expect(report.isPresented)
    }

    @Test func eachShakeAddsTheNextScreenshot() async {
        let report = report(github: FakeGitHub())
        report.present()
        await report.gathered()
        report.isPresented = false
        report.present()
        await report.gathered()
        #expect(report.composer.draft.attachments.map(\.name) == ["screenshot-1.png", "screenshot-2.png"])
    }

    @Test func filesTheIssueWithScreenshotEnvironmentAndLogs() async throws {
        let github = FakeGitHub()
        let report = report(github: github)
        report.present()
        report.composer.draft.title = "Crash on save"
        await report.composer.submit()

        #expect(report.composer.state == .submitted)
        #expect(report.filed?.absoluteString == "https://github.com/owner/app/issues/7")
        let create = try #require(github.requests.first { $0.url.path == "/repos/owner/app/issues" })
        let sent = try JSONSerialization.jsonObject(with: create.body ?? Data()) as? [String: Any]
        let body = sent?["body"] as? String ?? ""
        #expect(sent?["title"] as? String == "Crash on save")
        #expect(sent?["labels"] as? [String] == ["shake-report"])
        #expect(body.contains("https://github.com/user-attachments/assets/abc"))
        #expect(body.contains("| App |"))
        #expect(body.contains("tapped Save"))
        let upload = try #require(github.requests.first { $0.url.host == "uploads.github.com" })
        #expect(upload.url.query?.contains("repository_id=1234") == true)
    }

    @Test func logsNotReadHereAreSaidSo() async throws {
        let github = FakeGitHub()
        let store = MemoryTokenStore(["Ov23example": GitHubToken(access: "gho_fixture", scope: "public_repo")])
        let report = ShakeReport(
            repository: "owner/app", configuration: ShakeKitConfiguration(), shared: nil,
            credentials: GitHubCredentials(clientID: "Ov23example", scope: "public_repo", store: store),
            logSource: UnreadLogs(), draftStore: MemoryDraftStore(), send: github.send, screenshot: { nil })
        report.present()
        await report.gathered()
        #expect(report.logs == nil)
        #expect(report.logsOmission == AppLogSource.notRead)
        #expect(report.composer.draft.attachments.isEmpty)
        report.composer.draft.title = "Crash"
        await report.composer.submit()
        let create = try #require(github.requests.first { $0.url.path == "/repos/owner/app/issues" })
        let body = (try JSONSerialization.jsonObject(with: create.body ?? Data()) as? [String: Any])?["body"] as? String ?? ""
        #expect(body.contains("_\(AppLogSource.notRead)_"))
    }

    @Test func noLogsAreNoOmission() async {
        let report = report(github: FakeGitHub(), logs: [])
        report.present()
        await report.gathered()
        #expect(report.logs == nil && report.logsOmission == nil)
    }

    @Test func logsLeftOutWhenTurnedOff() async throws {
        let github = FakeGitHub()
        let report = report(github: github)
        report.present()
        report.includeLogs = false
        report.composer.draft.title = "Crash"
        await report.composer.submit()
        let create = try #require(github.requests.first { $0.url.path == "/repos/owner/app/issues" })
        let body = (try JSONSerialization.jsonObject(with: create.body ?? Data()) as? [String: Any])?["body"] as? String ?? ""
        #expect(!body.contains("tapped Save"))
        #expect(body.contains("| App |"))
    }
}
