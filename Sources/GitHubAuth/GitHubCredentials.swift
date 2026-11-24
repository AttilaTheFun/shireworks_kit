import Foundation
import Observation

/// An app's sign-in to GitHub, as the user: a token from GitHub's device
/// flow (a code entered at github.com/login/device) through an OAuth App
/// or a GitHub App (its `clientID`); or, where the app has no client id or
/// can't sign in by code (a web page: github.com's device flow answers no
/// other site's page), a token pasted, a fine-grained personal access
/// token. Kept in `store`, by the client id that issued it.
///
/// An OAuth App's token (`gho_`, of the `scope` asked for) never runs out
/// and has no refresh token: it is kept until signed out or refused. A
/// GitHub App's (`ghu_`) is renewed with its refresh token before it runs
/// out. Either works with no change here but the client id and the scope.
///
/// The client id, the scope and the store are the host's: its own OAuth
/// App or GitHub App, and a store in its own keychain group
/// (`KeychainTokenStore`), never one another app's GitHub sign-in uses.
///
/// A GitHub App's refresh token changes with every renewal, so two
/// renewals at once (from two processes on one store, an app and its
/// extension, say) would sign one of them out: before renewing, the store
/// is read again (another may have renewed it already), and when GitHub
/// refuses the renewal, again (another won the race), before giving up.
///
/// Where several apps share one sign-in (a store in a keychain group they all
/// carry), a `renewalLock` they share too (`FileRenewalLock`, in an app
/// group's container) makes each renewal one at a time across them: the
/// store read again, the token renewed and the renewed one kept, all under
/// the lock, so none spends a refresh token another has spent already.
///
/// In one process (several screens, each with a sign-in of its own on one
/// store) the sign-ins on one store (its `sharingKey`) hear each other at
/// once: whatever one of them keeps or finds changed (signed in, renewed,
/// signed out, refused) the others read again, each saying so through
/// `signedIn` and `signedOut`. Another process' change is read when the app
/// comes to the front (`reload()`).
@MainActor
@Observable
public final class GitHubCredentials {
    /// The OAuth App's or GitHub App's client id; "" for none (a token
    /// pasted).
    public let clientID: String
    /// What an OAuth App's token is asked to reach (`public_repo`, `repo`);
    /// nil for a GitHub App's, which has no scope.
    public let scope: String?
    /// Whether this app signs in by code (it has a client id, and isn't a
    /// web page), else by a token pasted.
    public let signsInByCode: Bool
    public private(set) var state: SignInState
    /// Why the last sign-in did not go through, or why it ended.
    public var problem: String?
    /// Asked once signed in: here (by code, or a token pasted), or found
    /// signed in by `reload()` (another sign-in on the store signed in).
    @ObservationIgnored public var signedIn: (@MainActor () -> Void)?
    /// Asked once signed out: here (`signOut()`), GitHub refusing the token
    /// (`refused()`), or found signed out by `reload()` (another sign-in on
    /// the store signed out, or was refused).
    @ObservationIgnored public var signedOut: (@MainActor () -> Void)?
    @ObservationIgnored private let store: TokenStore
    @ObservationIgnored private let post: GitHubDeviceFlow.Post
    @ObservationIgnored private let send: GitHubTransport.Send
    @ObservationIgnored private var token: GitHubToken?
    @ObservationIgnored private var kept: String
    /// The sign-in by code under way (read by tests, to wait for it).
    @ObservationIgnored private(set) var waiting: Task<Void, Never>?
    @ObservationIgnored private var renewing: Task<GitHubToken, Error>?
    /// How long a refused renewal waits before reading the store once more.
    @ObservationIgnored private let retryWait: UInt64
    /// Held across a renewal, by every process sharing the store; nil for one process alone.
    @ObservationIgnored private let renewalLock: RenewalLock?

    /// `clientID`: the host's OAuth App's or GitHub App's ("" for none: a
    /// token pasted). `scope`: what an OAuth App's token is asked to reach
    /// (nil: none sent, as for a GitHub App's).
    /// `store`: where the host keeps its tokens. `canSignInByCode`: false on
    /// a web page. `post` and `send`: a test's GitHub, in place of the
    /// device flow's and the API's (`send` asks whose a pasted token is).
    /// `retryWait`: how long a refused renewal waits to read the store once
    /// more. `renewalLock`: the lock every app sharing the store holds
    /// across a renewal (nil: this process alone renews on it).
    public init(clientID: String, scope: String? = nil, store: TokenStore, canSignInByCode: Bool = true,
                post: @escaping GitHubDeviceFlow.Post = GitHubDeviceFlow.post,
                send: @escaping GitHubTransport.Send = GitHubTransport.network, retryWait: Duration = .seconds(1),
                renewalLock: RenewalLock? = nil) {
        self.clientID = clientID
        self.scope = scope
        self.renewalLock = renewalLock
        let parts = retryWait.components
        self.retryWait = UInt64(max(parts.seconds, 0)) * 1_000_000_000 + UInt64(max(parts.attoseconds, 0) / 1_000_000_000)
        self.store = store
        self.post = post
        self.send = send
        signsInByCode = !clientID.isEmpty && canSignInByCode
        // The app's own token, else one pasted.
        if let token = store.token(for: clientID) {
            self.token = token
            kept = clientID
        } else {
            token = store.token(for: "")
            kept = ""
        }
        state = token == nil ? .signedOut : .signedIn
        // Heard by the other sign-ins on its store, and hearing them.
        if let key = store.sharingKey {
            Self.sharing[key, default: []].removeAll { $0.credentials == nil }
            Self.sharing[key, default: []].append(Listener(credentials: self))
        }
    }

    /// A sign-in of this process, held weakly: gone with whatever held it.
    private struct Listener {
        weak var credentials: GitHubCredentials?
    }

    /// This process' sign-ins, by their store's sharing key.
    private static var sharing: [String: [Listener]] = [:]

    /// The other sign-ins on this one's store told to read it again: what this
    /// one kept, or found, they find too (and each of them says so).
    private func tellOthers() {
        guard let key = store.sharingKey else { return }
        Self.sharing[key]?.removeAll { $0.credentials == nil }
        for listener in Self.sharing[key] ?? [] where listener.credentials !== self {
            listener.credentials?.reload()
        }
    }

    /// Asks GitHub for a code to show, then after it until the user has
    /// entered it at GitHub (or the code runs out, or is cancelled there).
    public func signInByCode() {
        guard signsInByCode else { return }
        waiting?.cancel()
        problem = nil
        state = .asking
        let clientID = clientID, scope = scope, post = post
        waiting = Task {
            do {
                let code = try await GitHubDeviceFlow.start(clientID: clientID, scope: scope, post: post)
                state = .entering(code)
                let token = try await GitHubDeviceFlow.token(clientID: clientID, for: code, post: post)
                // Cancelled just as GitHub answered: nothing kept.
                guard !Task.isCancelled else { return }
                keep(token, as: clientID)
                state = .signedIn
                signedIn?()
            } catch {
                // Cancelled here: nothing to say.
                guard !Task.isCancelled else { return }
                problem = error.localizedDescription
                state = .signedOut
            }
        }
    }

    /// Stops asking after the code shown.
    public func cancelSignIn() {
        waiting?.cancel()
        waiting = nil
        if state != .signedIn { state = .signedOut }
    }

    /// A token pasted, kept once GitHub says whose it is: nil when signed
    /// in, else why not.
    public func signIn(token pasted: String) async -> String? {
        let text = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "Paste a token first." }
        do {
            _ = try await GitHubTransport.login(token: text, send: send)
        } catch {
            return (error as? GitHubError)?.signedOut == true ? "GitHub doesn't take that token." : error.localizedDescription
        }
        waiting?.cancel()
        keep(GitHubToken(access: text), as: "")
        problem = nil
        state = .signedIn
        signedIn?()
        return nil
    }

    /// Signed out: the token deleted from the store (the access token and
    /// its refresh token, kept together), for every sign-in on it. Nothing
    /// is asked of GitHub: revoking a token there needs the app's client
    /// secret, which never ships in an app, so the token stays good on
    /// GitHub until the user revokes it (GitHub › Settings ›
    /// Applications) or, a GitHub App's, it runs out.
    public func signOut() {
        waiting?.cancel()
        let was = state
        problem = nil
        state = .signedOut
        keep(nil, as: kept)
        if was == .signedIn { signedOut?() }
    }

    /// GitHub refused the token (revoked, or run out): let go, and why.
    /// The store's copy is deleted only while it is still the one refused:
    /// another process on the store may have kept a new one meanwhile,
    /// which stays (and is taken at the next `reload()`).
    public func refused() {
        guard state == .signedIn, let refusedToken = token else { return }
        token = nil
        problem = "GitHub no longer takes the token (revoked, or run out): sign in again."
        state = .signedOut
        if store.token(for: kept) == refusedToken {
            store.keep(nil, for: kept)
            tellOthers()
        }
        signedOut?()
    }

    /// The store read again, for what other processes on it did since:
    /// signed in, renewed, or signed out. The app calls it when it comes to
    /// the front; the sign-ins of its own process on the store are told at
    /// once. Signed in or out by it, `signedIn` or `signedOut` is asked,
    /// and the process' other sign-ins on the store are told.
    public func reload() {
        // Not while a sign-in by code is under way.
        guard state == .signedIn || state == .signedOut else { return }
        let found: (GitHubToken, String)? = store.token(for: clientID).map { ($0, clientID) } ?? store.token(for: "").map { ($0, "") }
        guard found?.0 != token else { return }
        let was = state
        token = found?.0
        kept = found?.1 ?? clientID
        if token != nil {
            problem = nil
            state = .signedIn
        } else if state == .signedIn {
            state = .signedOut
        }
        tellOthers()
        if was != .signedIn, state == .signedIn {
            signedIn?()
        } else if was == .signedIn, state == .signedOut {
            signedOut?()
        }
    }

    /// A fixture's: signed in, with no token (nothing is asked of GitHub).
    public func showFixture() {
        state = .signedIn
    }

    /// The token to send, renewed first when it is about to run out (one
    /// renewal at a time); one GitHub won't renew, and nothing else on the
    /// store has renewed meanwhile, is let go. One with no end or no
    /// refresh token (an OAuth App's, or one pasted) is sent as it is.
    public func access() async throws -> String {
        guard var token else { throw GitHubError(status: 401, message: "Not signed in to GitHub: sign in first.") }
        guard token.expiresSoon(), token.refresh != nil, kept == clientID, !clientID.isEmpty else { return token.access }
        if let renewing { return try await renewing.value.access }
        // Another process on the store may have renewed it already.
        if let shared = store.token(for: clientID), shared != token {
            self.token = shared
            token = shared
            if !shared.expiresSoon() { return shared.access }
        }
        let clientID = clientID, post = post, old = token, store = store, lock = renewalLock
        let renewal = Task { () throws -> GitHubToken in
            guard let lock else { return try await GitHubDeviceFlow.refresh(clientID: clientID, token: old, post: post) }
            // Under the shared lock: another app's renewal, kept while this one waited, is taken; else this one
            // renews, and keeps the renewed token before letting go.
            let lease = try await lock.acquire()
            defer { lease.release() }
            if let shared = store.token(for: clientID), shared != old, !shared.expiresSoon() { return shared }
            let renewed = try await GitHubDeviceFlow.refresh(clientID: clientID, token: old, post: post)
            store.keep(renewed, for: clientID)
            return renewed
        }
        renewing = renewal
        defer { renewing = nil }
        do {
            let renewed = try await renewal.value
            keep(renewed, as: clientID)
            return renewed.access
        } catch let refused as GitHubError where refused.signedOut {
            // Another process may have won the race: its renewal used the
            // refresh token this one tried, and keeps a new one, maybe a
            // moment after GitHub refused this one.
            for wait in [0, retryWait] {
                if wait > 0 { try? await Task.sleep(nanoseconds: wait) }
                if let shared = store.token(for: clientID), shared != old, !shared.expiresSoon() {
                    self.token = shared
                    return shared.access
                }
            }
            self.refused()
            throw refused
        }
    }

    private func keep(_ token: GitHubToken?, as clientID: String) {
        self.token = token
        kept = clientID
        store.keep(token, for: clientID)
        tellOthers()
    }
}
