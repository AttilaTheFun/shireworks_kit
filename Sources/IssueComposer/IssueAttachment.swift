import Foundation

/// A file the person attached to an issue they're writing: a screenshot, an
/// image they picked, or the app's logs. It stays on the device until the
/// issue is submitted, when the host's upload turns it into a URL.
public struct IssueAttachment: Sendable, Equatable, Identifiable, Codable {
    public let id: UUID
    /// The file's name, as GitHub shows it ("screenshot-1.png").
    public var name: String
    /// Its MIME type ("image/png").
    public var contentType: String
    public var data: Data
    /// Describes the image for screen readers; the name if empty.
    public var altText: String

    public init(
        id: UUID = UUID(),
        name: String,
        contentType: String,
        data: Data,
        altText: String = ""
    ) {
        self.id = id
        self.name = name
        self.contentType = contentType
        self.data = data
        self.altText = altText
    }

    /// Where the attachment goes in the body until it is uploaded:
    /// `attachment:<id>`, rewritten to its URL at submit.
    public var placeholder: String { "attachment:\(id.uuidString)" }

    /// Its Markdown, as written into the body while drafting.
    public var markdown: String {
        "![\(altText.isEmpty ? name : altText)](\(placeholder))"
    }
}
