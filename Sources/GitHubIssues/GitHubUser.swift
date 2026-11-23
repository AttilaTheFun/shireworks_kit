import Foundation

/// Someone on GitHub: a person, or an app's bot (`example-app[bot]`).
public struct GitHubUser: Codable, Sendable, Hashable {
    public let login: String
    /// "User", or "Bot".
    public let type: String?
    public let name: String?
    public let avatarUrl: URL?

    public init(login: String, type: String? = nil, name: String? = nil, avatarUrl: URL? = nil) {
        self.login = login
        self.type = type
        self.name = name
        self.avatarUrl = avatarUrl
    }

    /// The name to show: an app's bot without its "[bot]".
    public var shownName: String {
        login.hasSuffix("[bot]") ? String(login.dropLast("[bot]".count)) : login
    }
}
