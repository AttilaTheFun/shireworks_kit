import Foundation

/// One of a repository's labels: its name, colour (six hex digits, no #)
/// and what it is for. Sent as it is to make one (`createLabel`).
public struct GitHubLabel: Codable, Sendable, Hashable {
    public let name: String
    public let color: String?
    public let description: String?

    public init(name: String, color: String? = nil, description: String? = nil) {
        self.name = name
        self.color = color
        self.description = description
    }
}
