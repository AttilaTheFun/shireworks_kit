import Foundation

/// What an edit of an issue changes: each part given is set, the rest left
/// as it is (sent in snake case, the parts not given left out). Labels
/// given replace the issue's: none clears them.
public struct IssueChange: Codable, Sendable, Hashable {
    public var title: String?
    public var body: String?
    public var labels: [String]?
    /// "open" or "closed".
    public var state: String?
    /// With a closing state: "completed" or "not_planned".
    public var stateReason: String?

    public init(title: String? = nil, body: String? = nil, labels: [String]? = nil, state: String? = nil, stateReason: String? = nil) {
        self.title = title
        self.body = body
        self.labels = labels
        self.state = state
        self.stateReason = stateReason
    }

    /// Nothing to change.
    public var isEmpty: Bool { title == nil && body == nil && labels == nil && state == nil }
}
