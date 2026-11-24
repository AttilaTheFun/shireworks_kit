import Foundation

/// What GitHub refused that the host acts on, beside GitHubAuth's
/// GitHubError (GitHub's own words, and its status).
public enum GitHubIssuesError: Error, LocalizedError, Sendable, Equatable {
    /// GitHub took no attachment from this sign-in: the upload answered
    /// 404, as it does for a token it doesn't take there (a GitHub App's),
    /// or for a user without write access to the repository. The composer
    /// files the issue without its attachments, and says so.
    case attachmentsNotAllowed

    public var errorDescription: String? {
        switch self {
        case .attachmentsNotAllowed: "GitHub doesn't take attachments from this sign-in: the issue goes without them."
        }
    }
}
