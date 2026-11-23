import Foundation
import GitHubAuth
import GitHubIssues
import IssueComposer
import Testing

@testable import ShakeKit

struct ConfigurationTests {
    @Test func offWithoutInfo() {
        let configuration = ShakeKitConfiguration.from(info: nil)
        #expect(!configuration.isEnabled)
        #expect(!ShakeKitConfiguration.from(info: ["CFBundleName": "App"]).isEnabled)
    }

    @Test func onWhenABuildOptsIn() {
        let configuration = ShakeKitConfiguration.from(info: ["ShakeKitClientID": "Ov23example", "ShakeKitScope": " repo "])
        #expect(configuration.isEnabled)
        #expect(configuration.clientID == "Ov23example")
        #expect(configuration.scope == "repo")
    }

    @Test func anEmptyValueTurnsItOnWithTheDefaults() {
        let configuration = ShakeKitConfiguration.from(info: ["ShakeKitScope": ""])
        #expect(configuration.isEnabled)
        #expect(configuration.clientID == ShakeKitConfiguration.defaultClientID)
        #expect(configuration.scope == ShakeKitConfiguration.defaultScope)
    }

    @Test func unfilledValuesCountAsAbsent() {
        let configuration = ShakeKitConfiguration.from(info: ["ShakeKitClientID": "$(SHAKE_KIT_CLIENT_ID)"])
        #expect(!configuration.isEnabled)
    }

    @Test func aConfigurationInCodeIsOn() {
        #expect(ShakeKitConfiguration().isEnabled)
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
            configuration: ShakeKitConfiguration(clientID: "Ov23example"),
            shared: nil,
            credentials: credentials,
            logSource: FixedLogs(lines: logs),
            draftStore: MemoryDraftStore(),
            send: github.send,
            screenshot: { Data([0x89, 0x50, 0x4E, 0x47]) })
    }

    @Test func presentAttachesAScreenshotAndGathersLogs() {
        let report = report(github: FakeGitHub())
        report.present()
        #expect(report.isPresented)
        #expect(report.composer.draft.attachments.map(\.name) == ["screenshot-1.png"])
        #expect(report.logs?.contains("tapped Save") == true)
        // A second shake while it's showing does nothing.
        report.present()
        #expect(report.composer.draft.attachments.count == 1)
    }

    @Test func eachShakeAddsTheNextScreenshot() {
        let report = report(github: FakeGitHub())
        report.present()
        report.isPresented = false
        report.present()
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
