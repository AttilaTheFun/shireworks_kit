// Signing in by code, against GitHub's answers as it writes them: the code
// asked for, then each poll's answer taken in turn (waiting, slowed down,
// signed in, cancelled, out of time), with no network and no waiting.

import Foundation
@testable import GitHubAuth
import Testing

@Suite struct GitHubDeviceFlowTests {
    private let now = Date(timeIntervalSince1970: 1_793_094_060)

    /// GitHub's answers, one a poll, and what was asked of it.
    private final class Answers: Sendable {
        private let state: Locked<(answers: [String], asked: [String], waits: [Int])>

        init(_ answers: [String]) { state = Locked((answers, [], [])) }

        var asked: [String] { state.withLock { $0.asked } }
        var waits: [Int] { state.withLock { $0.waits } }

        var post: GitHubDeviceFlow.Post {
            { address, form in
                self.state.withLock { state in
                    state.asked.append(address + " " + (form["grant_type"] ?? form["client_id"] ?? ""))
                    return Data((state.answers.isEmpty ? "{}" : state.answers.removeFirst()).utf8)
                }
            }
        }

        var wait: GitHubDeviceFlow.Wait { { seconds in self.state.withLock { $0.waits.append(seconds) } } }
    }

    private func code() -> DeviceCode {
        DeviceCode(deviceCode: "3584d83530557fdd1f46af8289938c8ef79f9dc5", userCode: "WDJB-MJHT",
                   verificationURI: URL(string: "https://github.com/login/device")!, expires: now.addingTimeInterval(900), interval: 5)
    }

    @Test func theCodeToShow() async throws {
        let answers = Answers([#"{"device_code": "3584d835", "user_code": "WDJB-MJHT", "verification_uri": "https://github.com/login/device", "expires_in": 900, "interval": 5}"#])
        let code = try await GitHubDeviceFlow.start(clientID: "Iv1.example", now: now, post: answers.post)
        #expect(code.userCode == "WDJB-MJHT")
        #expect(code.verificationURI.absoluteString == "https://github.com/login/device")
        #expect(code.expires == now.addingTimeInterval(900))
        #expect(code.interval == 5)
        #expect(answers.asked == ["https://github.com/login/device/code Iv1.example"])
    }

    /// An OAuth App's code is asked for with the host's scope; a GitHub
    /// App's, with none sent.
    @Test func theScopeIsSentOnlyWhenGiven() async throws {
        let forms = Locked<[[String: String]]>([])
        let post: GitHubDeviceFlow.Post = { address, form in
            #expect(address == "https://github.com/login/device/code")
            forms.withLock { $0.append(form) }
            return Data(#"{"device_code": "3584d835", "user_code": "WDJB-MJHT", "verification_uri": "https://github.com/login/device", "expires_in": 900, "interval": 5}"#.utf8)
        }
        _ = try await GitHubDeviceFlow.start(clientID: "Iv1.example", scope: "public_repo", now: now, post: post)
        _ = try await GitHubDeviceFlow.start(clientID: "Iv1.example", scope: "repo", now: now, post: post)
        _ = try await GitHubDeviceFlow.start(clientID: "Iv1.example", now: now, post: post)
        #expect(forms.withLock { $0 } == [["client_id": "Iv1.example", "scope": "public_repo"], ["client_id": "Iv1.example", "scope": "repo"],
                                          ["client_id": "Iv1.example"]])
    }

    /// An OAuth App's token, as GitHub gives it: no end, no refresh token.
    @Test func anOAuthAppsTokenHasNoEnd() async throws {
        let answers = Answers([#"{"access_token": "gho_fixture", "token_type": "bearer", "scope": "public_repo"}"#])
        let now = now
        let token = try await GitHubDeviceFlow.token(clientID: "Iv1.example", for: code(), clock: { now }, post: answers.post, wait: answers.wait)
        #expect(token == GitHubToken(access: "gho_fixture", scope: "public_repo"))
        #expect(token.refresh == nil && token.expires == nil && token.refreshExpires == nil)
        #expect(!token.expiresSoon(now: now.addingTimeInterval(365 * 86400)))
    }

    @Test func anAppWithoutTheDeviceFlowSaysSo() async {
        let answers = Answers([#"{"error": "device_flow_disabled", "error_description": "Device Flow must be explicitly enabled for this App"}"#])
        do {
            _ = try await GitHubDeviceFlow.start(clientID: "Iv1.example", now: now, post: answers.post)
            Issue.record("no code without the device flow")
        } catch {
            #expect(error.localizedDescription == "Device Flow must be explicitly enabled for this App")
        }
    }

    /// Each poll's answer, and what comes of it.
    @Test func eachAnswerIsAStep() {
        func step(_ json: String, interval: Int = 5) -> GitHubDeviceFlow.Step {
            GitHubDeviceFlow.step(after: Data(json.utf8), interval: interval, now: now)
        }
        #expect(step(#"{"error": "authorization_pending"}"#) == .wait(5))
        #expect(step(#"{"error": "slow_down", "interval": 10}"#) == .wait(10))
        #expect(step(#"{"error": "slow_down"}"#, interval: 10) == .wait(15), "five seconds more when it says no interval")
        #expect(step(#"{"error": "access_denied"}"#) == .failed("The sign-in was cancelled on GitHub."))
        #expect(step(#"{"error": "expired_token"}"#) == .failed("The code ran out of time: sign in again."))
        #expect(step(#"{"error": "incorrect_client_credentials", "error_description": "The client_id is not valid."}"#) == .failed("The client_id is not valid."))
        #expect(step("not json") == .failed("GitHub's answer could not be read"))
        #expect(step(#"{"access_token": "ghu_fixture", "refresh_token": "ghr_fixture", "expires_in": 28800, "refresh_token_expires_in": 15724800}"#) == .signedIn(GitHubToken(access: "ghu_fixture", refresh: "ghr_fixture", expires: now.addingTimeInterval(28800),
                                             refreshExpires: now.addingTimeInterval(15_724_800))))
        #expect(step(#"{"access_token": "github_pat_fixture", "token_type": "bearer"}"#) == .signedIn(GitHubToken(access: "github_pat_fixture")))
    }

    /// Waiting, slowed down, then signed in: asked three times, five, five
    /// and ten seconds apart.
    @Test func waitedOutUntilSignedIn() async throws {
        let answers = Answers([#"{"error": "authorization_pending"}"#, #"{"error": "slow_down", "interval": 10}"#,
                               #"{"access_token": "ghu_fixture", "expires_in": 28800}"#])
        let now = now
        let token = try await GitHubDeviceFlow.token(clientID: "Iv1.example", for: code(), clock: { now }, post: answers.post, wait: answers.wait)
        #expect(token.access == "ghu_fixture")
        #expect(answers.waits == [5, 5, 10])
        #expect(answers.asked.count == 3)
        #expect(answers.asked.allSatisfy { $0 == "https://github.com/login/oauth/access_token urn:ietf:params:oauth:grant-type:device_code" })
    }

    @Test func cancelledOnGitHub() async {
        let answers = Answers([#"{"error": "authorization_pending"}"#, #"{"error": "access_denied"}"#])
        let now = now
        do {
            _ = try await GitHubDeviceFlow.token(clientID: "Iv1.example", for: code(), clock: { now }, post: answers.post, wait: answers.wait)
            Issue.record("no token once cancelled")
        } catch {
            #expect(error.localizedDescription == "The sign-in was cancelled on GitHub.")
            #expect(answers.waits == [5, 5])
        }
    }

    /// A code whose time is up is not asked after.
    @Test func outOfTime() async {
        let answers = Answers([])
        let later = now.addingTimeInterval(901)
        do {
            _ = try await GitHubDeviceFlow.token(clientID: "Iv1.example", for: code(), clock: { later }, post: answers.post, wait: answers.wait)
            Issue.record("no token after the code's time")
        } catch {
            #expect(error.localizedDescription == "The code ran out of time: sign in again.")
            #expect(answers.asked == [])
        }
    }

    @Test func renewedWithItsRefreshToken() async throws {
        let answers = Answers([#"{"access_token": "ghu_renewed", "refresh_token": "ghr_renewed", "expires_in": 28800}"#])
        let renewed = try await GitHubDeviceFlow.refresh(clientID: "Iv1.example", token: GitHubToken(access: "ghu_old", refresh: "ghr_old"),
                                                         post: answers.post)
        #expect(renewed.access == "ghu_renewed")
        #expect(renewed.refresh == "ghr_renewed")
        #expect(answers.asked == ["https://github.com/login/oauth/access_token refresh_token"])
        do {
            _ = try await GitHubDeviceFlow.refresh(clientID: "Iv1.example", token: GitHubToken(access: "github_pat_fixture"), post: answers.post)
            Issue.record("a token with no refresh token is not renewed")
        } catch let error as GitHubError {
            #expect(error.signedOut)
        }
    }
}
