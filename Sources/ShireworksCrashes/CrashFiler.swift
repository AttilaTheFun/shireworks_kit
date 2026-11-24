import Foundation
import GitHubAuth
import GitHubIssues

/// Files crashes as GitHub issues in `repository`, one issue a crash (its
/// signature): the first time a crash is seen it opens one; each time after,
/// it comments on it ("Again in 1.2.0 (42), …"), and opens it again if it
/// was closed and the crash comes from a version newer than any it was seen
/// in before (a fix that didn't hold; a crash from an older build, still
/// in someone's hands, only comments).
///
/// An issue is found by its signature's marker in its body, through
/// GitHub's search (`repo:owner/name is:issue in:body "shireworks-crash:
/// <signature>"`): one request, whatever the number of crash issues, open or
/// closed, and found even when someone has taken its label off. Listing the
/// `crash` label's issues and reading their bodies would take a request a
/// hundred issues, and miss one relabelled. The search trails a new issue
/// by a little, so the issues this filer opens are also remembered by
/// signature, and a crash filed twice in one run finds its issue.
///
/// A public repository's issues are anyone's to read, so there an issue
/// leaves out the exception's reason and the breadcrumbs (`CrashIssue`'s
/// `details`), unless the host files them anyway (`publicDetails`). Each
/// filing (`file`, or a pass of `fileStored`) asks GitHub first whether the
/// repository is private; one it can't say of counts as public.
public final class CrashFiler: Sendable {
    /// What filing a crash did, and the issue's number.
    public enum Outcome: Sendable, Equatable {
        case opened(Int)
        case commented(Int)
        case reopened(Int)
    }

    public let repository: String
    public let labels: [String]
    public let redactions: [String]
    /// Whether the reason and the breadcrumbs go in even where the
    /// repository is public.
    public let publicDetails: Bool
    private let client: GitHubIssuesClient
    /// The issues opened in this run, by signature (the search may not find them yet).
    private let opened = Locked<[String: Int]>([:])

    /// `client`: as the signed-in user. `labels`: a new issue's.
    /// `redactions`: extra patterns blanked out of what is filed.
    /// `publicDetails`: the reason and the breadcrumbs filed in a public
    /// repository too.
    public init(client: GitHubIssuesClient, repository: String, labels: [String] = ["crash"], redactions: [String] = [],
                publicDetails: Bool = false) {
        self.client = client
        self.repository = repository
        self.labels = labels
        self.redactions = redactions
        self.publicDetails = publicDetails
    }

    /// Whether the reason and the breadcrumbs go in: where the host says so
    /// (`publicDetails`), or GitHub says the repository is private. Where
    /// GitHub can't say (unreachable, refused, an answer it can't read), it
    /// counts as public; a 401 is thrown (the sign-in is no good any more).
    public func details() async throws -> Bool {
        if publicDetails { return true }
        do {
            return try await client.isPrivate(repository: repository)
        } catch let error as GitHubError where error.status == 401 {
            throw error
        } catch {
            return false
        }
    }

    /// Files one crash: an issue opened, or commented on (and opened again),
    /// with its details or without them (`details()`, asked first). What
    /// GitHub refuses is thrown (GitHubError; a 401: the sign-in is no good
    /// any more).
    public func file(_ report: CrashReport) async throws -> Outcome {
        try await file(report, details: try await details())
    }

    /// Files one crash, with its reason and breadcrumbs or without them.
    func file(_ report: CrashReport, details: Bool) async throws -> Outcome {
        let signature = report.signature(withReason: details)
        guard let issue = try await existingIssue(for: signature) else {
            let issue = try await client.createIssue(
                in: repository, title: CrashIssue.title(for: report, redactions: redactions, details: details),
                body: CrashIssue.body(for: report, redactions: redactions, details: details), labels: labels)
            opened.withLock { $0[signature] = issue.number }
            return .opened(issue.number)
        }
        try await client.comment(CrashIssue.comment(for: report, redactions: redactions), on: issue.number, in: repository)
        // The newest version seen, recorded; and a closed issue opened again
        // by a version after it.
        let body = issue.body ?? ""
        let newer = CrashIssue.recordedVersion(in: body).map { CrashIssue.isVersion(report.appVersion, newerThan: $0) } ?? false
        guard newer else { return .commented(issue.number) }
        let reopen = !issue.isOpen
        _ = try await client.editIssue(issue.number, in: repository, IssueChange(
            body: CrashIssue.body(body, recording: report.appVersion), state: reopen ? "open" : nil))
        return reopen ? .reopened(issue.number) : .commented(issue.number)
    }

    /// The crash's issue: an open one where there is one, else the closed
    /// one most recently changed; nil for none.
    func existingIssue(for signature: String) async throws -> GitHubIssue? {
        if let number = opened.withLock({ $0[signature] }) { return try await client.issue(number, in: repository) }
        let found = try await client.searchIssues("repo:\(repository) is:issue in:body \"shireworks-crash: \(signature)\"")
        // The search matches words; the marker, exactly, decides.
        let marker = CrashIssue.marker(signature)
        let matching = found.filter { !$0.isPullRequest && ($0.body ?? "").contains(marker) }
        return matching.first(where: \.isOpen) ?? matching.max { $0.updatedAt < $1.updatedAt }
    }

    /// Files the store's crashes, oldest first, each removed once filed:
    /// what each did. Whether the repository is private is asked once, for
    /// them all (`details()`). It stops, leaving the rest kept, at the first refusal
    /// that the next would meet too (a 401, 403 or 404: signed out, not
    /// allowed, or no such repository) or a failure to reach GitHub, and
    /// throws it; a crash GitHub refuses otherwise (a 422) stays kept, and
    /// the next is filed.
    @discardableResult
    public func fileStored(in store: CrashStore) async throws -> [Outcome] {
        let reports = store.reports()
        guard !reports.isEmpty else { return [] }
        let details = try await details()
        var outcomes: [Outcome] = []
        for report in reports {
            do {
                outcomes.append(try await file(report, details: details))
                store.remove(report.id)
            } catch let error as GitHubError where ![0, 401, 403, 404].contains(error.status) {
                continue
            }
        }
        return outcomes
    }
}
