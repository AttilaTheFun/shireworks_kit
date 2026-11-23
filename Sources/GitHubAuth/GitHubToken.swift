import Foundation

/// The user's token from the device flow. An OAuth App's (`gho_`) has no
/// end and no refresh token; a GitHub App's (`ghu_`) has eight hours of
/// access and the refresh token that renews it for six months; a token
/// pasted has neither. Each part but the access token is optional, and a
/// token kept without them (in the store, as JSON) reads back the same.
public struct GitHubToken: Codable, Sendable, Equatable {
    public var access: String
    /// The refresh token: a GitHub App's alone.
    public var refresh: String?
    /// When the access token runs out: nil for never (an OAuth App's).
    public var expires: Date?
    /// When the refresh token runs out.
    public var refreshExpires: Date?

    public init(access: String, refresh: String? = nil, expires: Date? = nil, refreshExpires: Date? = nil) {
        self.access = access
        self.refresh = refresh
        self.expires = expires
        self.refreshExpires = refreshExpires
    }

    /// Whether to renew it before using it: within five minutes of its
    /// end; never, with no end.
    public func expiresSoon(now: Date = Date()) -> Bool {
        expires.map { $0.timeIntervalSince(now) < 300 } ?? false
    }
}
