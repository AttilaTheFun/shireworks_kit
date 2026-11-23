// The shared sign-in as an Info.plist names it, and the scope a token was granted.

import Foundation
@testable import GitHubAuth
import Testing

@Suite struct GitHubSharedSignInTests {
    @Test func readFromTheInfoPlistOnlyWhenWhole() {
        let info: [String: Any] = [GitHubSharedSignIn.clientIDKey: "Ov23.example", GitHubSharedSignIn.keychainGroupKey: "TEAMID.com.example.github",
                                   GitHubSharedSignIn.lockGroupKey: "group.com.example.github"]
        #expect(GitHubSharedSignIn.from(info: info) == GitHubSharedSignIn(clientID: "Ov23.example", keychainGroup: "TEAMID.com.example.github",
                                                                         lockGroup: "group.com.example.github"))
        var named = info
        named[GitHubSharedSignIn.keychainServiceKey] = "com.example.github"
        #expect(GitHubSharedSignIn.from(info: named)?.keychainService == "com.example.github")
        var partial = info
        partial[GitHubSharedSignIn.lockGroupKey] = nil
        #expect(GitHubSharedSignIn.from(info: partial) == nil)
        var unfilled = info
        unfilled[GitHubSharedSignIn.clientIDKey] = "$(SHARED_CLIENT_ID)"
        #expect(GitHubSharedSignIn.from(info: unfilled) == nil)
        #expect(GitHubSharedSignIn.from(info: nil) == nil)
        let shared = GitHubSharedSignIn.from(info: info)!
        #expect(shared.lockPath(in: URL(fileURLWithPath: "/tmp/group")) == "/tmp/group/GitHubSharedSignIn.lock")
    }

    @Test func aTokenCoversTheScopesItWasGranted() {
        let token = GitHubToken(access: "gho_x", scope: "repo,workflow")
        #expect(token.covers("repo"))
        #expect(token.covers("public_repo"))
        #expect(token.covers("repo workflow"))
        #expect(!token.covers("read:org"))
        #expect(!GitHubToken(access: "gho_y", scope: "public_repo").covers("repo"))
        #expect(GitHubToken(access: "ghu_z").covers("repo"), "a GitHub App's has no scope: its permissions are its reach")
    }

    @Test func theGrantedScopeIsKeptFromGitHubsAnswerAndOldTokensStillRead() async throws {
        let post: GitHubDeviceFlow.Post = { _, _ in
            Data(#"{"access_token": "gho_new", "refresh_token": "r2", "expires_in": 28800, "scope": "repo,workflow", "token_type": "bearer"}"#.utf8)
        }
        let renewed = try await GitHubDeviceFlow.refresh(clientID: "Ov23.example", token: GitHubToken(access: "gho_old", refresh: "r1"), post: post)
        #expect(renewed.scope == "repo,workflow")
        // A renewal that says no scope keeps the one the token had.
        let quiet: GitHubDeviceFlow.Post = { _, _ in Data(#"{"access_token": "gho_newer", "refresh_token": "r3", "expires_in": 28800}"#.utf8) }
        let kept = try await GitHubDeviceFlow.refresh(clientID: "Ov23.example", token: renewed, post: quiet)
        #expect(kept.scope == "repo,workflow")
        let old = try JSONDecoder().decode(GitHubToken.self, from: Data(#"{"access": "gho_a", "refresh": "r"}"#.utf8))
        #expect(old.scope == nil)
    }
}
