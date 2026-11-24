import Foundation
import GitHubAuth

/// GitHub's issues, as the user: an issue opened, read, edited, closed,
/// reopened or commented on, a comment edited or deleted, a repository's
/// labels and conversations read, and an attachment uploaded
/// (`uploadAttachment`). A repository is named as GitHub writes it,
/// "owner/name".
///
/// Each request carries the token `token` gives at the time
/// (GitHubCredentials.access: renewed first where it runs out), and goes
/// through `send` (the network's, unless a test answers). What GitHub
/// refuses is thrown as a GitHubError, in its words, with its status (a
/// 401: the token is no good any more, `GitHubCredentials.refused()`).
public final class GitHubIssuesClient: Sendable {
    /// The token to send: the access token of the user's sign-in.
    public typealias Token = @Sendable () async throws -> String

    /// Where GitHub takes attachments.
    public static let uploads = URL(string: "https://uploads.github.com")!

    private let token: Token
    private let send: GitHubTransport.Send
    /// GitHub's addresses, with no "/" at the end.
    private let apiBase: String
    private let uploadsBase: String
    /// Each repository's numeric id, asked once (the uploads want it).
    private let repositoryIDs = Locked<[String: Int64]>([:])

    /// `token`: the user's (GitHubCredentials.access). `send`: a test's
    /// GitHub, in place of the network's. `api` and `uploads`: GitHub's
    /// addresses.
    public init(token: @escaping Token, send: @escaping GitHubTransport.Send = GitHubTransport.network,
                api: URL = GitHubTransport.api, uploads: URL = GitHubIssuesClient.uploads) {
        self.token = token
        self.send = send
        apiBase = Self.trimmed(api)
        uploadsBase = Self.trimmed(uploads)
    }

    private static func trimmed(_ url: URL) -> String {
        var text = url.absoluteString
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    // MARK: Issues

    private struct NewIssue: Encodable {
        let title: String
        let body: String
        let labels: [String]
    }

    /// Opens an issue: what GitHub made of it, its number among it.
    public func createIssue(in repository: String, title: String, body: String, labels: [String] = []) async throws -> GitHubIssue {
        try await sendEncoded("POST", "/repos/\(repository)/issues", NewIssue(title: title, body: body, labels: labels))
    }

    /// Issue (or pull request) `number`, as GitHub has it now.
    public func issue(_ number: Int, in repository: String) async throws -> GitHubIssue {
        try await get("/repos/\(repository)/issues/\(number)")
    }

    /// Changes an issue's title, description, labels or state.
    public func editIssue(_ number: Int, in repository: String, _ change: IssueChange) async throws -> GitHubIssue {
        try await sendEncoded("PATCH", "/repos/\(repository)/issues/\(number)", change)
    }

    /// Closes an issue, as completed (`reason`: "completed") or not
    /// planned ("not_planned"): what GitHub made of it. Only the state and
    /// its reason are sent, so its labels stay as they are.
    public func closeIssue(_ number: Int, in repository: String, reason: String = "completed") async throws -> GitHubIssue {
        try await editIssue(number, in: repository, IssueChange(state: "closed", stateReason: reason))
    }

    /// Opens a closed issue again: what GitHub made of it.
    public func reopenIssue(_ number: Int, in repository: String) async throws -> GitHubIssue {
        try await editIssue(number, in: repository, IssueChange(state: "open"))
    }

    // MARK: Comments

    private struct CommentBody: Encodable {
        let body: String
    }

    /// Says something in its conversation: what GitHub made of it.
    @discardableResult
    public func comment(_ body: String, on number: Int, in repository: String) async throws -> IssueComment {
        try await sendEncoded("POST", "/repos/\(repository)/issues/\(number)/comments", CommentBody(body: body))
    }

    /// Changes a comment's words (by its id, in any issue of the
    /// repository): the user's own, or anyone's for a maintainer of it.
    /// What GitHub made of it.
    public func editComment(_ id: Int64, in repository: String, body: String) async throws -> IssueComment {
        try await sendEncoded("PATCH", "/repos/\(repository)/issues/comments/\(id)", CommentBody(body: body))
    }

    /// Deletes a comment for good (by its id), as `editComment` may change it.
    public func deleteComment(_ id: Int64, in repository: String) async throws {
        _ = try await data("DELETE", "/repos/\(repository)/issues/comments/\(id)")
    }

    /// An issue's (or a pull request's) conversation, oldest first: up to
    /// `pages` hundred.
    public func comments(on number: Int, in repository: String, pages: Int = 3) async throws -> [IssueComment] {
        try await paged("/repos/\(repository)/issues/\(number)/comments", pages: pages)
    }

    // MARK: Labels

    /// A repository's labels: up to `pages` hundred.
    public func labels(in repository: String, pages: Int = 3) async throws -> [GitHubLabel] {
        try await paged("/repos/\(repository)/labels", pages: pages)
    }

    /// Makes a label in the repository (one the host's issues use, made on
    /// first use): what GitHub made of it.
    @discardableResult
    public func createLabel(_ label: GitHubLabel, in repository: String) async throws -> GitHubLabel {
        try await sendEncoded("POST", "/repos/\(repository)/labels", label)
    }

    // MARK: Requests

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    /// A list a hundred at a time, page after page until one comes short
    /// (or `pages` are read).
    private func paged<T: Decodable>(_ path: String, pages: Int) async throws -> [T] {
        var all: [T] = []
        for page in 1...max(pages, 1) {
            let some: [T] = try await get(path + "?per_page=100&page=\(page)")
            all += some
            if some.count < 100 { break }
        }
        return all
    }

    func get<T: Decodable>(_ path: String) async throws -> T {
        try Self.read(try await data("GET", path))
    }

    /// A body of its own type, sent in snake case (what is nil left out),
    /// and GitHub's answer read.
    private func sendEncoded<T: Decodable, Body: Encodable>(_ method: String, _ path: String, _ body: Body) async throws -> T {
        try Self.read(try await data(method, path, body: try Self.encoder.encode(body)))
    }

    private static func read<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw GitHubError(status: 0, message: "GitHub's answer could not be read")
        }
    }

    /// One request to the API, as the user (the token as a bearer's): the
    /// answer's body, or GitHub's refusal thrown.
    private func data(_ method: String, _ path: String, body: Data? = nil) async throws -> Data {
        guard let url = URL(string: apiBase + path) else { throw GitHubError(status: 0, message: "No such address: \(path)") }
        let access = try await token()
        var headers = GitHubTransport.headers(token: access)
        if body != nil { headers["Content-Type"] = "application/json" }
        let answer = try await send(GitHubRequest(method: method, url: url, headers: headers, body: body))
        guard (200..<300).contains(answer.status) else { throw Self.refusal(answer) }
        return answer.data
    }

    /// What GitHub says when it refuses: its message, and the reasons
    /// beside it ("Validation Failed" says little without them), each a
    /// string or an object with a message.
    private struct Refusal: Decodable {
        let message: String?
        let errors: [Reason]?

        struct Reason: Decodable {
            let text: String?
            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let text = try? container.decode(String.self) {
                    self.text = text
                } else {
                    struct Object: Decodable { let message: String?; let code: String?; let field: String? }
                    let object = try container.decode(Object.self)
                    text = object.message ?? [object.field, object.code].compactMap { $0 }.joined(separator: " ")
                }
            }
        }

        /// The reasons where GitHub gave some, else its message.
        var words: String? {
            let reasons = (errors ?? []).compactMap(\.text).filter { !$0.isEmpty }
            return reasons.isEmpty ? message : reasons.joined(separator: "; ")
        }
    }

    static func refusal(_ answer: GitHubAnswer) -> GitHubError {
        let said = (try? JSONDecoder().decode(Refusal.self, from: answer.data))?.words
        return GitHubError(status: answer.status, message: said.map { "GitHub: " + $0 } ?? "GitHub answered \(answer.status)")
    }

    // MARK: Attachments

    /// A repository's numeric id (what an upload names it by): asked of
    /// GitHub once, then remembered.
    public func repositoryID(of repository: String) async throws -> Int64 {
        let key = repository.lowercased()
        if let id = repositoryIDs.withLock({ $0[key] }) { return id }
        struct Repository: Decodable { let id: Int64 }
        let found: Repository = try await get("/repos/\(repository)")
        repositoryIDs.withLock { $0[key] = found.id }
        return found.id
    }

    /// Uploads a file as GitHub's own attachment, against `repository`: its
    /// `https://github.com/user-attachments/assets/…` address, for the
    /// issue's body (`![name](url)`). `contentType`: its MIME type
    /// (`image/png`); GitHub takes images and videos only.
    ///
    /// Best-effort: the endpoint is the one GitHub's CLI uses
    /// (`gh issue create --attach`), not in the REST reference, and GitHub
    /// takes it only from some tokens (an OAuth App's, a personal access
    /// token; not a GitHub App's) and only from a user with write access.
    /// Refused that way (a 404) it throws
    /// `GitHubIssuesError.attachmentsNotAllowed`, so the composer can file
    /// the issue without its attachments; anything else refused, a
    /// GitHubError.
    ///
    /// One POST, the token sent with the `token` scheme (a bearer's gets a
    /// 404), the file as the body; the repository's id is asked first,
    /// once (`repositoryID(of:)`).
    public func uploadAttachment(repository: String, name: String, contentType: String, data: Data) async throws -> URL {
        let id = try await repositoryID(of: repository)
        let query = [("name", name), ("content_type", contentType), ("repository_id", String(id))]
            .map { $0.0 + "=" + Self.queryEncoded($0.1) }.joined(separator: "&")
        guard let url = URL(string: uploadsBase + "/user-attachments/assets?" + query) else {
            throw GitHubError(status: 0, message: "No such address for \(name)")
        }
        let access = try await token()
        let headers = ["Authorization": "token " + access, "Accept": "application/vnd.github+json",
                       "X-GitHub-Api-Version": "2022-11-28", "Content-Type": "application/octet-stream"]
        let answer = try await send(GitHubRequest(method: "POST", url: url, headers: headers, body: data))
        if answer.status == 404 { throw GitHubIssuesError.attachmentsNotAllowed }
        guard (200..<300).contains(answer.status) else { throw Self.refusal(answer) }
        struct Uploaded: Decodable { let url: URL }
        guard let uploaded = try? JSONDecoder().decode(Uploaded.self, from: answer.data) else {
            throw GitHubError(status: answer.status, message: "GitHub's answer could not be read")
        }
        return uploaded.url
    }

    /// A query value with everything but letters, digits and `-._~`
    /// escaped (a "+" or "/" in a MIME type, a space in a name).
    static func queryEncoded(_ value: String) -> String {
        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
