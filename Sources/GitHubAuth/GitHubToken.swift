import Foundation

/// The user's token from the device flow: eight hours of access (as
/// GitHub gives a GitHub App's), and the refresh token that renews it for
/// six months.
public struct GitHubToken: Codable, Sendable, Equatable {
    public var access: String
    public var refresh: String?
    public var expires: Date?
    public var refreshExpires: Date?

    public init(access: String, refresh: String? = nil, expires: Date? = nil, refreshExpires: Date? = nil) {
        self.access = access
        self.refresh = refresh
        self.expires = expires
        self.refreshExpires = refreshExpires
    }

    /// Whether to renew it before using it: within five minutes of its end.
    public func expiresSoon(now: Date = Date()) -> Bool {
        expires.map { $0.timeIntervalSince(now) < 300 } ?? false
    }
}
