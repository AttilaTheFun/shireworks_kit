// Whose a token is, against GitHub's `/user` answers as it writes them,
// with no network.

import Foundation
@testable import GitHubAuth
import Testing

@Suite struct GitHubTransportTests {
    @Test func theLoginOfAToken() async throws {
        let send: GitHubTransport.Send = { request in
            #expect(request.headers["Accept"] == "application/vnd.github+json")
            #expect(request.headers["X-GitHub-Api-Version"] == "2022-11-28")
            return GitHubAnswer(status: 200, data: Data(#"{"login": "octocat", "id": 1, "type": "User"}"#.utf8))
        }
        #expect(try await GitHubTransport.login(token: "ghu_fixture", send: send) == "octocat")
    }

    @Test func aRefusalInGitHubsWords() async {
        let send: GitHubTransport.Send = { _ in GitHubAnswer(status: 401, data: Data(#"{"message": "Bad credentials"}"#.utf8)) }
        do {
            _ = try await GitHubTransport.login(token: "ghu_fixture", send: send)
            Issue.record("a refused token throws")
        } catch let error as GitHubError {
            #expect(error == GitHubError(status: 401, message: "GitHub: Bad credentials"))
            #expect(error.signedOut)
        } catch {
            Issue.record("not GitHub's refusal: \(error)")
        }
    }

    @Test func aRefusalWithoutWords() {
        #expect(GitHubTransport.refusal(GitHubAnswer(status: 502, data: Data("<html>".utf8))).message == "GitHub answered 502")
    }
}
