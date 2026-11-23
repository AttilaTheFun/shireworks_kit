import Foundation

/// What GitHub said when it refused, in its words where it gave some.
public struct GitHubError: Error, LocalizedError, Sendable, Equatable {
    /// The HTTP status; 0 when it did not come to one (a sign-in refused).
    public let status: Int
    public let message: String

    public init(status: Int, message: String) {
        self.status = status
        self.message = message
    }

    public var errorDescription: String? { message }

    /// The token is no good any more: sign in again.
    public var signedOut: Bool { status == 401 }
}
