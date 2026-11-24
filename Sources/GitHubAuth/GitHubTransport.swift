import Foundation
// URLSession, on the toolchain's Foundation (Linux, Windows).
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One request to GitHub's API: its method, address, headers and body. Its
/// own type, not URLRequest, so that a test's transport and the network's
/// take the same value on every platform.
public struct GitHubRequest: Sendable, Equatable {
    public let method: String
    public let url: URL
    public let headers: [String: String]
    public let body: Data?

    public init(method: String, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

/// What GitHub answered one request with: its status, its headers and its
/// body.
public struct GitHubAnswer: Sendable, Equatable {
    public let status: Int
    public let headers: [String: String]
    public let data: Data

    public init(status: Int, headers: [String: String] = [:], data: Data) {
        self.status = status
        self.headers = headers
        self.data = data
    }
}

/// How a request reaches GitHub: `Send` gives back GitHub's answer, the
/// network's (`network`, through URLSession) unless a test answers in its
/// place.
public enum GitHubTransport {
    public typealias Send = @Sendable (_ request: GitHubRequest) async throws -> GitHubAnswer

    /// The network's: the request sent with URLSession, ephemeral (no
    /// cookies, and no answer from a cache of the system's), its answer's
    /// status, headers and body.
    public static let network: Send = { asked in
        var request = URLRequest(url: asked.url)
        request.httpMethod = asked.method
        for (name, value) in asked.headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = asked.body
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)
        let http = response as? HTTPURLResponse
        var headers: [String: String] = [:]
        for (name, value) in http?.allHeaderFields ?? [:] {
            if let name = name as? String, let value = value as? String { headers[name] = value }
        }
        return GitHubAnswer(status: http?.statusCode ?? 0, headers: headers, data: data)
    }

    /// GitHub's REST API.
    public static let api = URL(string: "https://api.github.com")!

    /// The headers every request to the API carries: the token, as a
    /// bearer's, and the API's media type and version.
    public static func headers(token: String) -> [String: String] {
        ["Authorization": "Bearer " + token, "Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"]
    }

    /// What GitHub says when it refuses: its `message`, where its answer
    /// has one.
    static func refusal(_ answer: GitHubAnswer) -> GitHubError {
        struct Message: Decodable { let message: String }
        let said = (try? JSONDecoder().decode(Message.self, from: answer.data))?.message
        return GitHubError(status: answer.status, message: said.map { "GitHub: " + $0 } ?? "GitHub answered \(answer.status)")
    }

    /// Whose a token is: GitHub's `/user`, as its bearer. Throws GitHub's
    /// refusal (a 401 for a token it doesn't take).
    static func login(token: String, api: URL = api, send: Send) async throws -> String {
        struct User: Decodable { let login: String }
        let answer = try await send(GitHubRequest(method: "GET", url: api.appendingPathComponent("user"), headers: headers(token: token)))
        guard (200..<300).contains(answer.status) else { throw refusal(answer) }
        guard let user = try? JSONDecoder().decode(User.self, from: answer.data) else {
            throw GitHubError(status: answer.status, message: "GitHub's answer could not be read")
        }
        return user.login
    }
}
