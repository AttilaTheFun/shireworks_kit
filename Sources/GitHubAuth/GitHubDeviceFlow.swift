import Foundation
// URLSession, on the toolchain's Foundation (Linux, Windows).
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Signing in as the user with a GitHub App's client id alone (no secret,
/// so an app can do it): a code shown to the user, entered at
/// github.com/login/device, and the token once they have; renewed with
/// its refresh token. github.com's two addresses for it answer no other
/// site's page (no CORS), so a browser can't sign in this way.
///
/// The client id is the host's: its GitHub App's, given to each call.
/// `post` sends a form to one of the addresses and gives back GitHub's
/// JSON (the network's, unless a test answers in its place); `wait` sleeps
/// between asks.
public enum GitHubDeviceFlow {
    public typealias Post = @Sendable (_ address: String, _ form: [String: String]) async throws -> Data
    public typealias Wait = @Sendable (_ seconds: Int) async throws -> Void

    static let codeAddress = "https://github.com/login/device/code"
    static let tokenAddress = "https://github.com/login/oauth/access_token"

    struct CodeAnswer: Decodable {
        let deviceCode: String?
        let userCode: String?
        let verificationUri: URL?
        let expiresIn: Int?
        let interval: Int?
        let error: String?
        let errorDescription: String?
    }

    struct TokenAnswer: Decodable {
        let accessToken: String?
        let refreshToken: String?
        let expiresIn: Int?
        let refreshTokenExpiresIn: Int?
        let interval: Int?
        let error: String?
        let errorDescription: String?
    }

    /// What to do after one of GitHub's answers to "has the user entered
    /// the code?": ask again after so many seconds, or stop, signed in or
    /// refused.
    public enum Step: Sendable, Equatable {
        case wait(Int)
        case signedIn(GitHubToken)
        case failed(String)
    }

    /// The code to show the user.
    public static func start(clientID: String, now: Date = Date(), post: Post = Self.post) async throws -> DeviceCode {
        let answer: CodeAnswer = try decoded(try await post(codeAddress, ["client_id": clientID]))
        guard let device = answer.deviceCode, let user = answer.userCode, let uri = answer.verificationUri else {
            throw GitHubError(status: 0, message: answer.errorDescription ?? answer.error ?? "GitHub gave no code")
        }
        return DeviceCode(deviceCode: device, userCode: user, verificationURI: uri,
                          expires: now.addingTimeInterval(TimeInterval(answer.expiresIn ?? 900)), interval: answer.interval ?? 5)
    }

    /// Where the sign-in stands after GitHub's answer (`data`) to a poll
    /// made `interval` seconds after the last: waiting for the user (asked
    /// again as often, or less often when GitHub says to slow down), signed
    /// in, or refused, out of time or cancelled.
    public static func step(after data: Data, interval: Int, now: Date = Date()) -> Step {
        guard let answer = try? decoded(data, as: TokenAnswer.self) else { return .failed("GitHub's answer could not be read") }
        if let token = token(answer, now: now) { return .signedIn(token) }
        switch answer.error {
        case "authorization_pending": return .wait(interval)
        case "slow_down": return .wait(answer.interval ?? interval + 5)
        case "access_denied": return .failed("The sign-in was cancelled on GitHub.")
        case "expired_token": return .failed("The code ran out of time: sign in again.")
        default: return .failed(answer.errorDescription ?? answer.error ?? "GitHub gave no token")
        }
    }

    /// Waits for the user to enter the code; the token once they have.
    /// Cancelled with its task; refused, or out of time, it throws.
    public static func token(clientID: String, for code: DeviceCode, clock: @Sendable () -> Date = { Date() },
                             post: Post = Self.post, wait: Wait = Self.sleep) async throws -> GitHubToken {
        var interval = code.interval
        while clock() < code.expires {
            try await wait(interval)
            let answer = try await post(tokenAddress, [
                "client_id": clientID, "device_code": code.deviceCode, "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])
            switch step(after: answer, interval: interval, now: clock()) {
            case .wait(let seconds): interval = seconds
            case .signedIn(let token): return token
            case .failed(let words): throw GitHubError(status: 0, message: words)
            }
        }
        throw GitHubError(status: 0, message: "The code ran out of time: sign in again.")
    }

    /// A token renewed with its refresh token (a device flow's needs no
    /// secret).
    public static func refresh(clientID: String, token: GitHubToken, post: Post = Self.post) async throws -> GitHubToken {
        guard let refresh = token.refresh else { throw GitHubError(status: 401, message: "Signed out of GitHub: sign in again.") }
        let answer: TokenAnswer = try decoded(try await post(tokenAddress, [
            "client_id": clientID, "grant_type": "refresh_token", "refresh_token": refresh,
        ]))
        guard let renewed = self.token(answer, now: Date()) else {
            throw GitHubError(status: 401, message: "Signed out of GitHub (\(answer.errorDescription ?? answer.error ?? "the token could not be renewed")): sign in again.")
        }
        return renewed
    }

    private static func token(_ answer: TokenAnswer, now: Date) -> GitHubToken? {
        guard let access = answer.accessToken else { return nil }
        return GitHubToken(access: access, refresh: answer.refreshToken,
                           expires: answer.expiresIn.map { now.addingTimeInterval(TimeInterval($0)) },
                           refreshExpires: answer.refreshTokenExpiresIn.map { now.addingTimeInterval(TimeInterval($0)) })
    }

    private static func decoded<T: Decodable>(_ data: Data, as type: T.Type = T.self) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    /// The network's: a form posted to github.com, its JSON answer.
    public static let post: Post = { address, form in
        var request = URLRequest(url: URL(string: address)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = form.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)
        let (data, _) = try await URLSession(configuration: .ephemeral).data(for: request)
        return data
    }

    public static let sleep: Wait = { seconds in try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000) }
}
