// The issues client against GitHub's answers as it writes them, with no
// network: each request's method, address, headers and body checked; an
// issue closed keeping its labels; lists read page by page; and an
// attachment's upload, its exact request, and the 404 GitHub gives a token
// it doesn't take there.

import Foundation
import GitHubAuth
@testable import GitHubIssues
import Testing

@Suite struct GitHubIssuesClientTests {
    /// GitHub, canned: each request answered by `answer`, and kept.
    private final class FakeGitHub: Sendable {
        private let asked = Locked<[GitHubRequest]>([])
        private let answer: @Sendable (GitHubRequest) -> GitHubAnswer

        init(_ answer: @escaping @Sendable (GitHubRequest) -> GitHubAnswer) { self.answer = answer }

        var requests: [GitHubRequest] { asked.withLock { $0 } }

        var send: GitHubTransport.Send {
            { request in
                self.asked.withLock { $0.append(request) }
                return self.answer(request)
            }
        }

        func client(token: String = "gho_fixture") -> GitHubIssuesClient {
            GitHubIssuesClient(token: { token }, send: send)
        }
    }

    private static func answer(_ status: Int, _ json: String) -> GitHubAnswer {
        GitHubAnswer(status: status, data: Data(json.utf8))
    }

    private static func answer(_ json: String) -> GitHubAnswer { answer(200, json) }

    private static func body(_ request: GitHubRequest?) -> String {
        String(decoding: request?.body ?? Data(), as: UTF8.self)
    }

    private static let bug = #"{"name": "bug", "color": "d73a4a", "description": "Something isn't working"}"#
    private static let shakeReport = #"{"name": "shake-report", "color": "ededed", "description": null}"#

    private static func issue(state: String = "open", reason: String? = nil) -> String {
        #"{"id": 3500000001, "node_id": "I_kwDOexample", "number": 7, "title": "Crash on launch", "body": "Steps", "state": "\#(state)", "#
            + #""state_reason": \#(reason.map { "\"\($0)\"" } ?? "null"), "labels": [\#(bug), \#(shakeReport)], "#
            + #""user": {"login": "octocat", "type": "User", "avatar_url": "https://avatars.githubusercontent.com/u/1"}, "assignees": [], "#
            + #""comments": 2, "html_url": "https://github.com/owner/app/issues/7", "created_at": "2026-11-01T09:41:00Z", "#
            + #""updated_at": "2026-11-02T09:41:00Z", "closed_at": \#(state == "closed" ? "\"2026-11-02T09:41:00Z\"" : "null")}"#
    }

    private static func comment(_ id: Int64, body: String = "Seen it too") -> String {
        #"{"id": \#(id), "body": "\#(body)", "user": {"login": "octocat", "type": "User"}, "html_url": "https://github.com/owner/app/issues/7#issuecomment-\#(id)", "created_at": "2026-11-01T09:41:00Z", "updated_at": "2026-11-01T09:41:00Z"}"#
    }

    @Test func anIssueOpened() async throws {
        let github = FakeGitHub { _ in Self.answer(201, Self.issue()) }
        let issue = try await github.client().createIssue(in: "owner/app", title: "Crash on launch", body: "Steps", labels: ["shake-report"])
        #expect(issue.number == 7)
        #expect(issue.id == 3_500_000_001)
        #expect(issue.nodeId == "I_kwDOexample")
        #expect(issue.labels.map(\.name) == ["bug", "shake-report"])
        #expect(issue.user?.avatarUrl?.absoluteString == "https://avatars.githubusercontent.com/u/1")
        #expect(issue.htmlUrl?.absoluteString == "https://github.com/owner/app/issues/7")
        #expect(issue.createdAt == Date(timeIntervalSince1970: 1_793_526_060))
        #expect(issue.isOpen && !issue.isPullRequest && issue.closedAt == nil)
        let request = github.requests.first
        #expect(request?.method == "POST")
        #expect(request?.url.absoluteString == "https://api.github.com/repos/owner/app/issues")
        #expect(request?.headers == ["Authorization": "Bearer gho_fixture", "Accept": "application/vnd.github+json",
                                     "X-GitHub-Api-Version": "2022-11-28", "Content-Type": "application/json"])
        #expect(Self.body(request) == #"{"body":"Steps","labels":["shake-report"],"title":"Crash on launch"}"#)
    }

    @Test func anIssueRead() async throws {
        let github = FakeGitHub { _ in Self.answer(Self.issue()) }
        let issue = try await github.client().issue(7, in: "owner/app")
        #expect(issue.title == "Crash on launch")
        #expect(github.requests.first?.method == "GET")
        #expect(github.requests.first?.url.absoluteString == "https://api.github.com/repos/owner/app/issues/7")
        #expect(github.requests.first?.body == nil)
        #expect(github.requests.first?.headers["Content-Type"] == nil)
    }

    /// An edit sends only the parts given; labels given (none, even)
    /// replace the issue's.
    @Test func anIssueEdited() async throws {
        let github = FakeGitHub { _ in Self.answer(Self.issue()) }
        let client = github.client()
        _ = try await client.editIssue(7, in: "owner/app", IssueChange(title: "Crash on launch, every time"))
        _ = try await client.editIssue(7, in: "owner/app", IssueChange(labels: []))
        #expect(github.requests.map(\.method) == ["PATCH", "PATCH"])
        #expect(github.requests.first?.url.absoluteString == "https://api.github.com/repos/owner/app/issues/7")
        #expect(github.requests.map { Self.body($0) } == [#"{"title":"Crash on launch, every time"}"#, #"{"labels":[]}"#])
        #expect(IssueChange().isEmpty)
        #expect(!IssueChange(labels: []).isEmpty)
    }

    /// Closing sends the state and its reason alone, so the labels stay;
    /// reopening, the state alone.
    @Test func closedKeepingItsLabels() async throws {
        let github = FakeGitHub { request in
            Self.body(request).contains(#""closed""#) ? Self.answer(Self.issue(state: "closed", reason: "not_planned"))
                : Self.answer(Self.issue(state: "open", reason: "reopened"))
        }
        let client = github.client()
        let closed = try await client.closeIssue(7, in: "owner/app", reason: "not_planned")
        #expect(closed.state == "closed")
        #expect(closed.stateReason == "not_planned")
        #expect(closed.closedAt != nil)
        #expect(closed.labels.map(\.name) == ["bug", "shake-report"])
        _ = try await client.closeIssue(7, in: "owner/app")
        let reopened = try await client.reopenIssue(7, in: "owner/app")
        #expect(reopened.isOpen)
        #expect(github.requests.map(\.method) == ["PATCH", "PATCH", "PATCH"])
        #expect(github.requests.map { Self.body($0) } == [#"{"state":"closed","state_reason":"not_planned"}"#,
                                                          #"{"state":"closed","state_reason":"completed"}"#, #"{"state":"open"}"#])
    }

    @Test func commentedOnEditedAndDeleted() async throws {
        let github = FakeGitHub { request in
            switch request.method {
            case "POST": Self.answer(201, Self.comment(42))
            case "PATCH": Self.answer(Self.comment(42, body: "Seen it twice"))
            default: GitHubAnswer(status: 204, data: Data())
            }
        }
        let client = github.client()
        let said = try await client.comment("Seen it too", on: 7, in: "owner/app")
        #expect(said.id == 42)
        #expect(said.user?.login == "octocat")
        let edited = try await client.editComment(42, in: "owner/app", body: "Seen it twice")
        #expect(edited.body == "Seen it twice")
        try await client.deleteComment(42, in: "owner/app")
        let requests = github.requests
        #expect(requests.map(\.method) == ["POST", "PATCH", "DELETE"])
        #expect(requests.map(\.url.absoluteString) == ["https://api.github.com/repos/owner/app/issues/7/comments",
                                                       "https://api.github.com/repos/owner/app/issues/comments/42",
                                                       "https://api.github.com/repos/owner/app/issues/comments/42"])
        #expect(requests.map { Self.body($0) } == [#"{"body":"Seen it too"}"#, #"{"body":"Seen it twice"}"#, ""])
    }

    /// Labels a hundred a page: a full page asks for the next, a short one
    /// ends it.
    @Test func labelsPageByPage() async throws {
        let full = "[" + (1...100).map { #"{"name": "label-\#($0)", "color": "ededed", "description": null}"# }.joined(separator: ", ") + "]"
        let github = FakeGitHub { request in
            Self.answer(request.url.query?.hasSuffix("&page=1") == true ? full : "[\(Self.bug)]")
        }
        let labels = try await github.client().labels(in: "owner/app")
        #expect(labels.count == 101)
        #expect(labels.first == GitHubLabel(name: "label-1", color: "ededed"))
        #expect(labels.last == GitHubLabel(name: "bug", color: "d73a4a", description: "Something isn't working"))
        #expect(github.requests.map(\.url.absoluteString) == ["https://api.github.com/repos/owner/app/labels?per_page=100&page=1",
                                                              "https://api.github.com/repos/owner/app/labels?per_page=100&page=2"])
        #expect(github.requests.allSatisfy { $0.method == "GET" })
    }

    /// Comments the same way, and no more pages than asked for.
    @Test func commentsPageByPage() async throws {
        let full = "[" + (1...100).map { Self.comment(Int64($0)) }.joined(separator: ", ") + "]"
        let github = FakeGitHub { _ in Self.answer(full) }
        let comments = try await github.client().comments(on: 7, in: "owner/app", pages: 2)
        #expect(comments.count == 200)
        #expect(github.requests.map(\.url.absoluteString) == ["https://api.github.com/repos/owner/app/issues/7/comments?per_page=100&page=1",
                                                              "https://api.github.com/repos/owner/app/issues/7/comments?per_page=100&page=2"])
    }

    @Test func aLabelMade() async throws {
        let github = FakeGitHub { _ in Self.answer(201, Self.shakeReport) }
        let made = try await github.client().createLabel(GitHubLabel(name: "shake-report", color: "ededed"), in: "owner/app")
        #expect(made.name == "shake-report")
        #expect(github.requests.first?.method == "POST")
        #expect(github.requests.first?.url.absoluteString == "https://api.github.com/repos/owner/app/labels")
        #expect(Self.body(github.requests.first) == #"{"color":"ededed","name":"shake-report"}"#)
    }

    /// GitHub's refusal, in its words and with its status: the reasons
    /// beside its message where it gave some.
    @Test func refusalsInGitHubsWords() async {
        let github = FakeGitHub { request in
            request.method == "POST"
                ? Self.answer(422, #"{"message": "Validation Failed", "errors": [{"resource": "Issue", "code": "missing_field", "field": "title"}]}"#)
                : Self.answer(401, #"{"message": "Bad credentials"}"#)
        }
        let client = github.client()
        await #expect(throws: GitHubError(status: 422, message: "GitHub: title missing_field")) {
            try await client.createIssue(in: "owner/app", title: "", body: "")
        }
        do {
            _ = try await client.issue(7, in: "owner/app")
            Issue.record("a refused token throws")
        } catch let error as GitHubError {
            #expect(error == GitHubError(status: 401, message: "GitHub: Bad credentials"))
            #expect(error.signedOut)
        } catch {
            Issue.record("not GitHub's refusal: \(error)")
        }
    }

    /// Each request asks for the token as it goes (renewed by the sign-in
    /// where it must); one that can't be had stops the request.
    @Test func theTokenIsAskedEachTime() async throws {
        let tokens = Locked(0)
        let github = FakeGitHub { _ in Self.answer(Self.issue()) }
        let client = GitHubIssuesClient(token: {
            tokens.withLock { count in
                count += 1
                return "ghu_fixture_\(count)"
            }
        }, send: github.send)
        _ = try await client.issue(7, in: "owner/app")
        _ = try await client.issue(7, in: "owner/app")
        #expect(github.requests.map { $0.headers["Authorization"] } == ["Bearer ghu_fixture_1", "Bearer ghu_fixture_2"])
        let signedOut = GitHubIssuesClient(token: { throw GitHubError(status: 401, message: "Not signed in") }, send: github.send)
        await #expect(throws: GitHubError(status: 401, message: "Not signed in")) { try await signedOut.issue(7, in: "owner/app") }
        #expect(github.requests.count == 2)
    }

    // MARK: Attachments

    private static let repository = #"{"id": 123456789, "node_id": "R_kgDOexample", "full_name": "owner/app", "private": false}"#
    private static let uploaded = #"{"url": "https://github.com/user-attachments/assets/0b9d4f9e-1111-4222-8333-944455556666"}"#

    /// The upload as GitHub's CLI sends it: one POST to uploads.github.com
    /// naming the file, its type and the repository's numeric id (asked
    /// once), the token with the `token` scheme, the file as the body.
    @Test func anAttachmentUploaded() async throws {
        let github = FakeGitHub { request in
            request.url.host == "api.github.com" ? Self.answer(Self.repository) : Self.answer(201, Self.uploaded)
        }
        let client = github.client()
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let url = try await client.uploadAttachment(repository: "owner/app", name: "Screenshot 1.png", contentType: "image/png", data: png)
        #expect(url.absoluteString == "https://github.com/user-attachments/assets/0b9d4f9e-1111-4222-8333-944455556666")
        let requests = github.requests
        #expect(requests.count == 2)
        #expect(requests.first?.method == "GET")
        #expect(requests.first?.url.absoluteString == "https://api.github.com/repos/owner/app")
        let upload = requests.last
        #expect(upload?.method == "POST")
        #expect(upload?.url.absoluteString
            == "https://uploads.github.com/user-attachments/assets?name=Screenshot%201.png&content_type=image%2Fpng&repository_id=123456789")
        #expect(upload?.headers == ["Authorization": "token gho_fixture", "Accept": "application/vnd.github+json",
                                    "X-GitHub-Api-Version": "2022-11-28", "Content-Type": "application/octet-stream"])
        #expect(upload?.body == png)

        // The repository's id is remembered (its name in any case).
        _ = try await client.uploadAttachment(repository: "Owner/App", name: "diagram.svg", contentType: "image/svg+xml", data: Data("<svg/>".utf8))
        #expect(github.requests.filter { $0.url.host == "api.github.com" }.count == 1)
        #expect(github.requests.last?.url.query == "name=diagram.svg&content_type=image%2Fsvg%2Bxml&repository_id=123456789")
    }

    /// A 404 from the upload (a GitHub App's token, or no write access):
    /// its own error, for the composer to file the issue without it.
    @Test func anAttachmentNotTaken() async {
        let github = FakeGitHub { request in
            request.url.host == "api.github.com" ? Self.answer(Self.repository) : Self.answer(404, #"{"message": "Not Found"}"#)
        }
        let client = github.client(token: "ghu_fixture")
        await #expect(throws: GitHubIssuesError.attachmentsNotAllowed) {
            try await client.uploadAttachment(repository: "owner/app", name: "shot.png", contentType: "image/png", data: Data([1]))
        }
        #expect(GitHubIssuesError.attachmentsNotAllowed.errorDescription?.isEmpty == false)
    }

    /// Anything else refused is GitHub's error, as the API's are; and a
    /// repository GitHub doesn't show is its 404, not the upload's.
    @Test func anUploadRefusedOtherwise() async {
        let tooBig = FakeGitHub { request in
            request.url.host == "api.github.com" ? Self.answer(Self.repository) : Self.answer(422, #"{"message": "File is too large"}"#)
        }
        await #expect(throws: GitHubError(status: 422, message: "GitHub: File is too large")) {
            try await tooBig.client().uploadAttachment(repository: "owner/app", name: "clip.mov", contentType: "video/quicktime", data: Data([1]))
        }
        let noRepository = FakeGitHub { _ in Self.answer(404, #"{"message": "Not Found"}"#) }
        await #expect(throws: GitHubError(status: 404, message: "GitHub: Not Found")) {
            try await noRepository.client().uploadAttachment(repository: "owner/gone", name: "shot.png", contentType: "image/png", data: Data([1]))
        }
        #expect(noRepository.requests.count == 1)
    }
}
