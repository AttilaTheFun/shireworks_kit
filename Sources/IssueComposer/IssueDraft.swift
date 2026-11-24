import Foundation

/// An issue being written: what the composer edits, keeps as a draft, and
/// hands to the host at submit.
public struct IssueDraft: Sendable, Equatable, Codable {
    public var title: String
    /// Markdown. Attachments appear in it by their placeholders until they
    /// are uploaded.
    public var body: String
    public var attachments: [IssueAttachment]

    public init(title: String = "", body: String = "", attachments: [IssueAttachment] = []) {
        self.title = title
        self.body = body
        self.attachments = attachments
    }

    /// Whether it can be submitted: GitHub needs a title.
    public var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Adds an attachment and its Markdown at the end of the body.
    public mutating func attach(_ attachment: IssueAttachment) {
        attachments.append(attachment)
        let separator = body.isEmpty || body.hasSuffix("\n\n") ? "" : (body.hasSuffix("\n") ? "\n" : "\n\n")
        body += separator + attachment.markdown + "\n"
    }

    /// Removes an attachment and every reference to it in the body.
    public mutating func detach(_ id: IssueAttachment.ID) {
        guard let attachment = attachments.first(where: { $0.id == id }) else { return }
        attachments.removeAll { $0.id == id }
        body = body.replacingOccurrences(of: attachment.markdown + "\n", with: "")
            .replacingOccurrences(of: attachment.markdown, with: "")
    }

    /// The body with each uploaded attachment's placeholder replaced by its
    /// URL. Attachments missing from `uploaded` (an upload that failed) are
    /// dropped from the body, and a note says how many.
    public func body(uploaded: [IssueAttachment.ID: URL]) -> String {
        var result = body
        var missing = 0
        for attachment in attachments {
            if let url = uploaded[attachment.id] {
                result = result.replacingOccurrences(of: attachment.placeholder, with: url.absoluteString)
            } else {
                missing += 1
                result = result.replacingOccurrences(of: attachment.markdown + "\n", with: "")
                    .replacingOccurrences(of: attachment.markdown, with: "")
            }
        }
        if missing > 0 {
            let noun = missing == 1 ? "attachment" : "attachments"
            result += (result.hasSuffix("\n") ? "\n" : "\n\n") + "_\(missing) \(noun) couldn't be uploaded._\n"
        }
        return result
    }
}
