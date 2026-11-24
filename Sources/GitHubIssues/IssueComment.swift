import Foundation

/// A comment in an issue's (or a pull request's) conversation. Its author
/// and body are nil where GitHub gives none (a deleted account's).
public struct IssueComment: Codable, Sendable, Hashable, Identifiable {
    /// GitHub's id: past what a 32-bit Int holds (wasm's).
    public let id: Int64
    public let body: String?
    public let user: GitHubUser?
    public let htmlUrl: URL?
    public let createdAt: Date
    public let updatedAt: Date?

    public init(id: Int64, body: String?, user: GitHubUser?, htmlUrl: URL? = nil, createdAt: Date, updatedAt: Date? = nil) {
        self.id = id
        self.body = body
        self.user = user
        self.htmlUrl = htmlUrl
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// An issues browser's name for it.
public typealias GitHubComment = IssueComment
