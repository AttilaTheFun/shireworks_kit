import Foundation

/// An issue as GitHub's REST API says it. Its issues list says pull
/// requests too, each with a `pullRequest` part (`isPullRequest`).
public struct GitHubIssue: Codable, Sendable, Hashable, Identifiable {
    public let id: Int64
    /// Its GraphQL id, for what only GraphQL does (deleting it).
    public let nodeId: String?
    public let number: Int
    public let title: String
    public let body: String?
    /// "open" or "closed".
    public let state: String
    /// Why it closed: "completed", "not_planned", "reopened", or nil.
    public let stateReason: String?
    public let labels: [GitHubLabel]
    public let user: GitHubUser?
    public let assignees: [GitHubUser]?
    /// How many comments its conversation has.
    public let comments: Int?
    public let htmlUrl: URL?
    public let createdAt: Date
    public let updatedAt: Date
    public let closedAt: Date?
    public let pullRequest: PullRequestPart?

    /// What marks a pull request among issues.
    public struct PullRequestPart: Codable, Sendable, Hashable {
        public let url: URL?
        public init(url: URL? = nil) { self.url = url }
    }

    public init(id: Int64, number: Int, title: String, body: String? = nil, state: String = "open", stateReason: String? = nil,
                labels: [GitHubLabel] = [], user: GitHubUser? = nil, assignees: [GitHubUser]? = nil, comments: Int? = 0,
                htmlUrl: URL? = nil, createdAt: Date, updatedAt: Date, closedAt: Date? = nil, pullRequest: PullRequestPart? = nil,
                nodeId: String? = nil) {
        self.id = id
        self.nodeId = nodeId
        self.number = number
        self.title = title
        self.body = body
        self.state = state
        self.stateReason = stateReason
        self.labels = labels
        self.user = user
        self.assignees = assignees
        self.comments = comments
        self.htmlUrl = htmlUrl
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.closedAt = closedAt
        self.pullRequest = pullRequest
    }

    /// A pull request, which GitHub lists among issues.
    public var isPullRequest: Bool { pullRequest != nil }
    public var isOpen: Bool { state == "open" }
}
