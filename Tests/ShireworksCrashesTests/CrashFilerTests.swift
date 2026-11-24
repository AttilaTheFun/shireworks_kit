// Crashes filed against GitHub's answers as it writes them, with no
// network: a new crash opens an issue with its markers and labels; one seen
// before comments on its issue, opening a closed one again only for a
// version newer than any it was seen in; a refused sign-in keeps them all.

import Foundation
import GitHubAuth
import GitHubIssues
import Testing
@testable import ShireworksCrashes

@Suite struct CrashFilerTests {
    /// GitHub, canned: each request answered by `answer`, and kept.
    private final class FakeGitHub: Sendable {
        private let asked = Locked<[GitHubRequest]>([])
        private let answer: @Sendable (GitHubRequest) -> GitHubAnswer

        init(_ answer: @escaping @Sendable (GitHubRequest) -> GitHubAnswer) { self.answer = answer }

        var requests: [GitHubRequest] { asked.withLock { $0 } }

        /// "GET /search/issues", "POST /repos/owner/app/issues", ….
        var asks: [String] { requests.map { $0.method + " " + $0.url.path } }

        func filer() -> CrashFiler {
            let client = GitHubIssuesClient(token: { "gho_fixture" }, send: { request in
                self.asked.withLock { $0.append(request) }
                return self.answer(request)
            })
            return CrashFiler(client: client, repository: "owner/app")
        }
    }

    private static func answer(_ status: Int, _ object: Any) -> GitHubAnswer {
        GitHubAnswer(status: status, data: (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
    }

    private static func issue(number: Int = 7, state: String = "open", body: String) -> [String: Any] {
        ["id": 3_500_000_000 + number, "number": number, "title": "Crash: EXC_BAD_ACCESS", "body": body, "state": state,
         "labels": [["name": "crash", "color": "ededed"]], "html_url": "https://github.com/owner/app/issues/\(number)",
         "created_at": "2026-11-01T09:41:00Z", "updated_at": "2026-11-02T09:41:00Z"]
    }

    private static func found(_ issues: [[String: Any]]) -> [String: Any] {
        ["total_count": issues.count, "incomplete_results": false, "items": issues]
    }

    private static var comment: [String: Any] { ["id": 42, "body": "Again", "created_at": "2026-11-01T09:41:00Z"] }

    private static func body(_ request: GitHubRequest?) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: request?.body ?? Data())) as? [String: Any] ?? [:]
    }

    /// An issue's body for `report`, recording `version`.
    private static func issueBody(_ report: CrashReport, version: String) -> String {
        CrashIssue.body(CrashIssue.body(for: report), recording: version)
    }

    /// GitHub with `existing` as the search's answer, and the rest as asked.
    private static func github(finding existing: [[String: Any]]) -> FakeGitHub {
        let search = answer(200, found(existing))
        return FakeGitHub { request in
            switch (request.method, request.url.path) {
            case ("GET", "/search/issues"): search
            case ("POST", "/repos/owner/app/issues"): answer(201, issue(number: 9, body: body(request)["body"] as? String ?? ""))
            case ("POST", _): answer(201, comment)
            case ("PATCH", _): answer(200, issue(state: body(request)["state"] as? String ?? "open", body: "patched"))
            default: answer(200, issue(number: Int(request.url.lastPathComponent) ?? 7, body: ""))
            }
        }
    }

    @Test func aNewCrashOpensAnIssue() async throws {
        let report = Fixtures.report()
        let github = Self.github(finding: [])
        #expect(try await github.filer().file(report) == .opened(9))
        #expect(github.asks == ["GET /search/issues", "POST /repos/owner/app/issues"])
        let search = try #require(github.requests.first?.url.query)
        #expect(search.contains("q=repo%3Aowner%2Fapp%20is%3Aissue%20in%3Abody%20%22shireworks-crash%3A%20\(report.signature)%22"))
        let opened = Self.body(github.requests.last)
        #expect(opened["title"] as? String == CrashIssue.title(for: report))
        #expect(opened["labels"] as? [String] == ["crash"])
        let body = try #require(opened["body"] as? String)
        #expect(body.contains("<!-- shireworks-crash: \(report.signature) -->"))
        #expect(body.contains("<!-- shireworks-crash-version: 1.2.0 -->"))
    }

    /// The search matches words: an issue without the exact marker isn't the crash's.
    @Test func onlyTheMarkerDecides() async throws {
        let github = Self.github(finding: [Self.issue(body: "shireworks-crash: something else")])
        #expect(try await github.filer().file(Fixtures.report()) == .opened(9))
    }

    @Test func seenBeforeComments() async throws {
        let report = Fixtures.report()
        let github = Self.github(finding: [Self.issue(body: Self.issueBody(report, version: "1.2.0"))])
        #expect(try await github.filer().file(report) == .commented(7))
        #expect(github.asks == ["GET /search/issues", "POST /repos/owner/app/issues/7/comments"])
        let said = try #require(Self.body(github.requests.last)["body"] as? String)
        #expect(said.hasPrefix("Again in 1.2.0 (42), iPhone17,1, iOS 27.2, 2026-11-01T09:41:00Z"))
        #expect(said.contains("Example.List.item(at:)"))
    }

    /// An open issue (preferred to a closed one) seen in a newer version
    /// records it: no state sent, so it stays open.
    @Test func aNewerVersionRecorded() async throws {
        let report = Fixtures.report(version: "1.3.0")
        let github = Self.github(finding: [Self.issue(number: 5, state: "closed", body: Self.issueBody(report, version: "1.0.0")),
                                           Self.issue(body: Self.issueBody(report, version: "1.2.0"))])
        #expect(try await github.filer().file(report) == .commented(7))
        #expect(github.asks == ["GET /search/issues", "POST /repos/owner/app/issues/7/comments", "PATCH /repos/owner/app/issues/7"])
        let edit = Self.body(github.requests.last)
        #expect(edit["state"] == nil)
        #expect(CrashIssue.recordedVersion(in: edit["body"] as? String ?? "") == "1.3.0")
    }

    /// Closed, and the crash comes from a version after any it was seen
    /// in: the fix didn't hold, so it opens again.
    @Test func closedAndNewerReopens() async throws {
        let report = Fixtures.report(version: "1.10.0")
        let github = Self.github(finding: [Self.issue(state: "closed", body: Self.issueBody(report, version: "1.9.3"))])
        #expect(try await github.filer().file(report) == .reopened(7))
        #expect(github.asks == ["GET /search/issues", "POST /repos/owner/app/issues/7/comments", "PATCH /repos/owner/app/issues/7"])
        let edit = Self.body(github.requests.last)
        #expect(edit["state"] as? String == "open")
        #expect(CrashIssue.recordedVersion(in: edit["body"] as? String ?? "") == "1.10.0")
    }

    /// Closed, and the crash comes from the same version or an older one
    /// (a build still in someone's hands): a comment alone.
    @Test func closedAndNotNewerOnlyComments() async throws {
        for (recorded, crashed) in [("1.2.0", "1.2.0"), ("1.3.0", "1.2.0")] {
            let report = Fixtures.report(version: crashed)
            let github = Self.github(finding: [Self.issue(state: "closed", body: Self.issueBody(report, version: recorded))])
            #expect(try await github.filer().file(report) == .commented(7))
            #expect(github.asks == ["GET /search/issues", "POST /repos/owner/app/issues/7/comments"])
        }
    }

    /// An issue opened in this run is found again without the search,
    /// which may not know it yet.
    @Test func openedThisRunIsRemembered() async throws {
        let report = Fixtures.report()
        let github = Self.github(finding: [])
        let filer = github.filer()
        #expect(try await filer.file(report) == .opened(9))
        #expect(try await filer.file(Fixtures.report(id: "crash-2")) == .commented(9))
        #expect(github.asks == ["GET /search/issues", "POST /repos/owner/app/issues", "GET /repos/owner/app/issues/9",
                                "POST /repos/owner/app/issues/9/comments"])
    }

    /// The store's crashes filed, oldest first, each let go once filed.
    @Test func theStoreFiled() async throws {
        let store = CrashStore(folder: Fixtures.folder())
        try store.add(Fixtures.report(id: "first", date: Date(timeIntervalSince1970: 1_793_526_000)))
        try store.add(Fixtures.report(id: "second", type: "EXC_BREAKPOINT", date: Date(timeIntervalSince1970: 1_793_526_060)))
        let github = Self.github(finding: [])
        let outcomes = try await github.filer().fileStored(in: store)
        #expect(outcomes == [.opened(9), .opened(9)])
        #expect(store.reports().isEmpty)
    }

    /// A refused sign-in stops the filing and keeps every crash.
    @Test func aRefusedSignInKeepsThem() async throws {
        let store = CrashStore(folder: Fixtures.folder())
        try store.add(Fixtures.report(id: "first"))
        try store.add(Fixtures.report(id: "second", type: "EXC_BREAKPOINT"))
        let github = FakeGitHub { _ in Self.answer(401, ["message": "Bad credentials"]) }
        await #expect(throws: GitHubError(status: 401, message: "GitHub: Bad credentials")) {
            try await github.filer().fileStored(in: store)
        }
        #expect(github.requests.count == 1)
        #expect(store.reports().map(\.id).sorted() == ["first", "second"])
    }

    /// A crash GitHub refuses on its own (a 422) stays kept; the next is filed.
    @Test func oneRefusedTheNextFiled() async throws {
        let store = CrashStore(folder: Fixtures.folder())
        try store.add(Fixtures.report(id: "first", date: Date(timeIntervalSince1970: 1_793_526_000)))
        try store.add(Fixtures.report(id: "second", type: "EXC_BREAKPOINT", date: Date(timeIntervalSince1970: 1_793_526_060)))
        let created = Locked(0)
        let github = FakeGitHub { request in
            guard request.method == "POST" else { return Self.answer(200, Self.found([])) }
            let count = created.withLock { count -> Int in
                count += 1
                return count
            }
            return count == 1 ? Self.answer(422, ["message": "Validation Failed"]) : Self.answer(201, Self.issue(number: 9, body: ""))
        }
        #expect(try await github.filer().fileStored(in: store) == [.opened(9)])
        #expect(store.reports().map(\.id) == ["first"])
    }
}

/// Started where crashes are caught (iOS and macOS: Sentry's SDK, for real,
/// with no crash), and nowhere else; started once.
@MainActor
@Suite struct ShireworksCrashesStartTests {
    @Test func startsWhereSupported() {
        let store = CrashStore(folder: Fixtures.folder())
        let configuration = CrashesConfiguration(repository: "owner/app", files: false)
        let started = ShireworksCrashes.start(configuration: configuration, store: store, shared: nil)
        #expect(started == ShireworksCrashes.isSupported)
        #expect(ShireworksCrashes.isStarted == started)
        #expect(ShireworksCrashes.start(configuration: configuration, store: store, shared: nil) == started)
        #expect(store.reports().isEmpty)
        #if os(iOS) || os(macOS)
        #expect(started)
        #endif
    }

    @Test func configuredByTheInfoPlist() {
        #expect(CrashesConfiguration.from(info: ["ShireworksRepository": " owner/app "]).repository == "owner/app")
        #expect(CrashesConfiguration.from(info: ["ShireworksRepository": "$(SHIREWORKS_REPOSITORY)"]).repository == nil)
        #expect(CrashesConfiguration.from(info: nil) == CrashesConfiguration())
        #expect(CrashesConfiguration().labels == ["crash"])
        #expect(CrashesConfiguration().maxStored == 20)
    }
}
