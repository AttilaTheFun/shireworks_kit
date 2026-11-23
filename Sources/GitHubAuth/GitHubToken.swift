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
    /// What GitHub granted an OAuth App's token (its answer's `scope`, comma-separated: `repo,workflow`); nil for a
    /// GitHub App's, which has none, or a token pasted.
    public var scope: String?

    public init(access: String, refresh: String? = nil, expires: Date? = nil, refreshExpires: Date? = nil, scope: String? = nil) {
        self.access = access
        self.refresh = refresh
        self.expires = expires
        self.refreshExpires = refreshExpires
        self.scope = scope
    }

    /// Whether it was granted every scope of `wanted` (space- or comma-separated): `repo` covers `public_repo`; a
    /// token with no scope said (a GitHub App's, whose reach is its permissions) is taken to.
    public func covers(_ wanted: String) -> Bool {
        guard let scope else { return true }
        let granted = Set(scope.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init))
        return wanted.split(whereSeparator: { $0 == "," || $0 == " " }).allSatisfy { part in
            granted.contains(String(part)) || (part == "public_repo" && granted.contains("repo"))
        }
    }

    /// Whether to renew it before using it: within five minutes of its
    /// end; never, with no end.
    public func expiresSoon(now: Date = Date()) -> Bool {
        expires.map { $0.timeIntervalSince(now) < 300 } ?? false
    }
}
