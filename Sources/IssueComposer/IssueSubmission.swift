/// What the host's submit receives: the issue as GitHub should get it, its
/// attachments already uploaded and their placeholders rewritten to URLs.
public struct IssueSubmission: Sendable, Equatable {
    public var title: String
    public var body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}
