// The sign-in: a token kept by its client id, renewed before it runs out,
// two processes on one store never signing each other out (the one that
// loses the race to renew takes the winner's token), and the sign-ins of
// one process on one store (several screens') hearing each other's sign-in
// and sign-out at once.

import Foundation
@testable import GitHubAuth
import Testing

@MainActor
@Suite struct GitHubCredentialsTests {
    private let clientID = "Iv1.example"
    private let later = Date().addingTimeInterval(8 * 3600)
    private let soon = Date().addingTimeInterval(60)

    /// GitHub's token endpoint, canned: what each renewal answers, and how
    /// many were asked.
    private final class Renewals: Sendable {
        let asked = Locked(0)
        let answer: @Sendable (Int) -> String

        init(_ answer: @escaping @Sendable (Int) -> String) { self.answer = answer }

        var post: GitHubDeviceFlow.Post {
            { _, _ in
                let count = self.asked.withLock { asked in
                    asked += 1
                    return asked
                }
                return Data(self.answer(count).utf8)
            }
        }
    }

    nonisolated private static let renewed = #"{"access_token": "renewed", "refresh_token": "refresh-2", "expires_in": 28800}"#
    nonisolated private static let code = #"{"device_code": "3584d835", "user_code": "WDJB-MJHT", "verification_uri": "https://github.com/login/device", "expires_in": 900, "interval": 0}"#
    nonisolated private static let badRefresh = #"{"error": "bad_refresh_token", "error_description": "The refresh token passed is incorrect or expired."}"#

    @Test func aTokenKeptIsSignedIn() {
        let store = MemoryTokenStore([clientID: GitHubToken(access: "kept", expires: later)])
        let credentials = GitHubCredentials(clientID: clientID, store: store)
        #expect(credentials.state == .signedIn)
        #expect(credentials.signsInByCode)
        #expect(!(GitHubCredentials(clientID: clientID, store: store, canSignInByCode: false).signsInByCode))
        #expect(GitHubCredentials(clientID: "another", store: store).state == .signedOut, "kept by its own client id")
    }

    @Test func renewedBeforeItRunsOut() async throws {
        let store = MemoryTokenStore([clientID: GitHubToken(access: "old", refresh: "refresh-1", expires: soon)])
        let renewals = Renewals { _ in Self.renewed }
        let credentials = GitHubCredentials(clientID: clientID, store: store, post: renewals.post)
        let access = try await credentials.access()
        #expect(access == "renewed")
        #expect(store.token(for: clientID)?.refresh == "refresh-2")
        #expect(renewals.asked.withLock { $0 } == 1)
    }

    /// An OAuth App's token (no end, no refresh token) is sent as it is,
    /// never renewed; nor is one with an end but no refresh token.
    @Test func anOAuthAppsTokenIsNeverRenewed() async throws {
        let store = MemoryTokenStore([clientID: GitHubToken(access: "gho_fixture")])
        let renewals = Renewals { _ in Self.renewed }
        let credentials = GitHubCredentials(clientID: clientID, scope: "public_repo", store: store, post: renewals.post)
        #expect(credentials.state == .signedIn)
        #expect(try await credentials.access() == "gho_fixture")
        #expect(try await credentials.access() == "gho_fixture")
        store.keep(GitHubToken(access: "gho_ending", expires: soon), for: clientID)
        credentials.reload()
        #expect(try await credentials.access() == "gho_ending")
        #expect(renewals.asked.withLock { $0 } == 0)
        #expect(store.token(for: clientID) == GitHubToken(access: "gho_ending", expires: soon))
    }

    /// Signing in by code asks with the scope given, and keeps the OAuth
    /// App's token GitHub answers with.
    @Test func signedInByCodeWithTheScope() async {
        let store = MemoryTokenStore()
        let forms = Locked<[[String: String]]>([])
        let post: GitHubDeviceFlow.Post = { address, form in
            forms.withLock { $0.append(form) }
            return Data((address == GitHubDeviceFlow.codeAddress ? Self.code : #"{"access_token": "gho_fixture", "token_type": "bearer", "scope": "repo"}"#).utf8)
        }
        let credentials = GitHubCredentials(clientID: clientID, scope: "repo", store: store, post: post)
        credentials.signInByCode()
        await credentials.waiting?.value
        #expect(credentials.state == .signedIn)
        #expect(store.token(for: clientID) == GitHubToken(access: "gho_fixture"))
        #expect(forms.withLock { $0 }.first == ["client_id": clientID, "scope": "repo"])
        #expect(forms.withLock { $0 }.last?["scope"] == nil, "the polls send no scope")
    }

    /// A sign-in by code cancelled just as GitHub answers with the token
    /// keeps nothing.
    @Test func aSignInCancelledAsGitHubAnswersKeepsNothing() async {
        let store = MemoryTokenStore()
        let signingIn = Locked<GitHubCredentials?>(nil)
        let post: GitHubDeviceFlow.Post = { address, _ in
            if address == GitHubDeviceFlow.codeAddress { return Data(Self.code.utf8) }
            // Cancelled here, with GitHub's answer on its way.
            await MainActor.run { signingIn.withLock { $0 }?.cancelSignIn() }
            return Data(#"{"access_token": "gho_fixture", "token_type": "bearer", "scope": "public_repo"}"#.utf8)
        }
        let credentials = GitHubCredentials(clientID: clientID, scope: "public_repo", store: store, post: post)
        signingIn.withLock { $0 = credentials }
        let heard = Heard()
        credentials.signedIn = { heard.said.append("in") }
        credentials.signInByCode()
        await credentials.waiting?.value
        #expect(credentials.state == .signedOut)
        #expect(store.token(for: clientID) == nil)
        #expect(heard.said.isEmpty)
        do {
            _ = try await credentials.access()
            Issue.record("no token once cancelled")
        } catch {
            #expect((error as? GitHubError)?.signedOut == true)
        }
    }

    /// Another app sharing the store renewed it already: its token is
    /// taken, and nothing asked of GitHub.
    @Test func anotherAppsRenewalIsTaken() async throws {
        let store = MemoryTokenStore([clientID: GitHubToken(access: "old", refresh: "refresh-1", expires: soon)])
        let renewals = Renewals { _ in Self.badRefresh }
        let credentials = GitHubCredentials(clientID: clientID, store: store, post: renewals.post)
        store.keep(GitHubToken(access: "theirs", refresh: "refresh-2", expires: later), for: clientID)
        let access = try await credentials.access()
        #expect(access == "theirs")
        #expect(renewals.asked.withLock { $0 } == 0)
    }

    /// The race lost: GitHub refuses the refresh token another app has just
    /// used, and the winner's token, kept meanwhile, is taken.
    @Test func aRaceLostTakesTheWinnersToken() async throws {
        let store = MemoryTokenStore([clientID: GitHubToken(access: "old", refresh: "refresh-1", expires: soon)])
        let renewals = Renewals { _ in
            // The other app's renewal lands while this one's is asked.
            store.keep(GitHubToken(access: "theirs", refresh: "refresh-2", expires: Date().addingTimeInterval(8 * 3600)), for: "Iv1.example")
            return Self.badRefresh
        }
        let credentials = GitHubCredentials(clientID: clientID, store: store, post: renewals.post)
        let access = try await credentials.access()
        #expect(access == "theirs")
        #expect(credentials.state == .signedIn)
    }

    /// Refused, and no other app renewed it: signed out, and why.
    @Test func aRefusalSignsOut() async {
        let store = MemoryTokenStore([clientID: GitHubToken(access: "old", refresh: "refresh-1", expires: soon)])
        let renewals = Renewals { _ in Self.badRefresh }
        let credentials = GitHubCredentials(clientID: clientID, store: store, post: renewals.post, retryWait: .milliseconds(10))
        do {
            _ = try await credentials.access()
            Issue.record("a refused renewal throws")
        } catch {
            #expect((error as? GitHubError)?.signedOut == true)
        }
        #expect(credentials.state == .signedOut)
        #expect(credentials.problem != nil)
        #expect(store.token(for: clientID) == nil)
    }

    /// The race lost, the winner's token kept a moment after GitHub refused
    /// this one's: the store read once more, after a wait, finds it.
    @Test func aWinnerKeptLateIsFound() async throws {
        let store = MemoryTokenStore([clientID: GitHubToken(access: "old", refresh: "refresh-1", expires: soon)])
        let renewals = Renewals { _ in
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000)
                store.keep(GitHubToken(access: "theirs", refresh: "refresh-2", expires: Date().addingTimeInterval(8 * 3600)), for: "Iv1.example")
            }
            return Self.badRefresh
        }
        let credentials = GitHubCredentials(clientID: clientID, store: store, post: renewals.post, retryWait: .milliseconds(100))
        let access = try await credentials.access()
        #expect(access == "theirs")
    }

    /// Refused, with another app's new token in the store: that one stays.
    @Test func aRefusalKeepsAnotherAppsToken() {
        let store = MemoryTokenStore([clientID: GitHubToken(access: "mine", expires: later)])
        let credentials = GitHubCredentials(clientID: clientID, store: store)
        store.keep(GitHubToken(access: "theirs", expires: later), for: clientID)
        credentials.refused()
        #expect(credentials.state == .signedOut)
        #expect(store.token(for: clientID)?.access == "theirs")
        // Come to the front again: theirs taken.
        credentials.reload()
        #expect(credentials.state == .signedIn)
    }

    /// Another app signing in, then out: seen at the next reload.
    @Test func reloadSeesOtherApps() {
        let store = MemoryTokenStore()
        let credentials = GitHubCredentials(clientID: clientID, store: store)
        #expect(credentials.state == .signedOut)
        store.keep(GitHubToken(access: "theirs", expires: later), for: clientID)
        credentials.reload()
        #expect(credentials.state == .signedIn)
        store.keep(nil, for: clientID)
        credentials.reload()
        #expect(credentials.state == .signedOut)
    }

    /// A token pasted is kept as one (under ""), once GitHub says whose it is.
    @Test func aTokenPasted() async {
        let store = MemoryTokenStore()
        let send: GitHubTransport.Send = { request in
            request.url.path == "/user" ? GitHubAnswer(status: 200, data: Data(#"{"login": "octocat"}"#.utf8))
                : GitHubAnswer(status: 404, data: Data())
        }
        let credentials = GitHubCredentials(clientID: "", store: store, send: send)
        #expect(!(credentials.signsInByCode))
        let problem = await credentials.signIn(token: "  github_pat_x \n")
        #expect(problem == nil)
        #expect(credentials.state == .signedIn)
        #expect(store.token(for: "")?.access == "github_pat_x")
        let access = try? await credentials.access()
        #expect(access == "github_pat_x")
        credentials.signOut()
        #expect(store.token(for: "") == nil)
        #expect(credentials.state == .signedOut)
    }
    /// A token pasted that GitHub doesn't take is not kept; its request
    /// was GitHub's `/user`, with the token as a bearer's.
    @Test func aTokenPastedThatGitHubRefuses() async {
        let store = MemoryTokenStore()
        let asked = Locked<[GitHubRequest]>([])
        let send: GitHubTransport.Send = { request in
            asked.withLock { $0.append(request) }
            return GitHubAnswer(status: 401, data: Data(#"{"message": "Bad credentials"}"#.utf8))
        }
        let credentials = GitHubCredentials(clientID: "", store: store, send: send)
        #expect(await credentials.signIn(token: "github_pat_bad") == "GitHub doesn't take that token.")
        #expect(await credentials.signIn(token: " \n") == "Paste a token first.")
        #expect(credentials.state == .signedOut)
        #expect(store.token(for: "") == nil)
        let request = asked.withLock { $0 }.first
        #expect(request?.method == "GET")
        #expect(request?.url.absoluteString == "https://api.github.com/user")
        #expect(request?.headers["Authorization"] == "Bearer github_pat_bad")
        #expect(asked.withLock { $0.count } == 1)
    }

    /// Not signed in, there is no token to send.
    @Test func noTokenSignedOut() async {
        let credentials = GitHubCredentials(clientID: clientID, store: MemoryTokenStore())
        do {
            _ = try await credentials.access()
            Issue.record("no token when signed out")
        } catch {
            #expect((error as? GitHubError)?.signedOut == true)
        }
    }

    /// What the sign-ins' signedIn and signedOut said, in order.
    @MainActor private final class Heard {
        var said: [String] = []
    }

    /// Two sign-ins of one process on one store (two screens'):
    /// one signing in signs the other in at once, and its `signedIn` is
    /// asked; one signing out, the same; a store of another key hears
    /// nothing.
    @Test func signInsOnOneStoreHearEachOther() async throws {
        let store = MemoryTokenStore()
        let send: GitHubTransport.Send = { request in
            request.url.path == "/user" ? GitHubAnswer(status: 200, data: Data(#"{"login": "octocat"}"#.utf8))
                : GitHubAnswer(status: 404, data: Data())
        }
        let first = GitHubCredentials(clientID: "", store: store, send: send)
        let second = GitHubCredentials(clientID: "", store: store)
        let elsewhere = GitHubCredentials(clientID: "", store: MemoryTokenStore())
        let heard = Heard()
        second.signedIn = { heard.said.append("in") }
        second.signedOut = { heard.said.append("out") }
        elsewhere.signedIn = { heard.said.append("elsewhere") }
        #expect(await first.signIn(token: "github_pat_x") == nil)
        #expect(second.state == .signedIn)
        #expect(try await second.access() == "github_pat_x")
        first.signOut()
        #expect(second.state == .signedOut)
        #expect(elsewhere.state == .signedOut)
        #expect(heard.said == ["in", "out"])
    }

    /// GitHub refusing one sign-in's token signs the others on its store
    /// out too, each asked its `signedOut`.
    @Test func aRefusalIsHeardByTheOthers() {
        let store = MemoryTokenStore([clientID: GitHubToken(access: "kept", expires: later)])
        let one = GitHubCredentials(clientID: clientID, store: store)
        let other = GitHubCredentials(clientID: clientID, store: store)
        let heard = Heard()
        one.signedOut = { heard.said.append("one") }
        other.signedOut = { heard.said.append("other") }
        one.refused()
        #expect(one.state == .signedOut)
        #expect(other.state == .signedOut)
        #expect(heard.said.sorted() == ["one", "other"])
        #expect(store.token(for: clientID) == nil)
    }
}
