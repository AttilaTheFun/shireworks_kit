import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// What makes one renewal at a time across every process signed in on one store (several apps sharing a sign-in
/// through a keychain group): held while the store is read again, the token renewed and the renewed one kept, so no
/// two processes spend the same refresh token, and each finds the other's renewal once it holds the lock.
public protocol RenewalLock: Sendable {
    /// The lock held, waited for as long as it takes another holder to let go (up to a time of the lock's own); the
    /// lease lets it go.
    func acquire() async throws -> RenewalLease
}

/// A held `RenewalLock`, let go by `release()` (and by the process ending).
public protocol RenewalLease: Sendable {
    func release()
}

/// A `RenewalLock` that is an exclusive `flock` on a file every process sharing the store can reach (in an app group's
/// container they all carry). The system lets it go when its holder's process ends, so an app killed mid-renewal never
/// keeps the others waiting.
public struct FileRenewalLock: RenewalLock {
    public let path: String
    /// How long a process waits for another's renewal before giving up (`GitHubError` 0).
    public let timeLimit: Duration

    public init(path: String, timeLimit: Duration = .seconds(30)) {
        self.path = path
        self.timeLimit = timeLimit
    }

    public func acquire() async throws -> RenewalLease {
        let file = open(path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard file >= 0 else { throw GitHubError(status: 0, message: "The sign-in's renewal lock can't be opened (\(errno)).") }
        let clock = ContinuousClock(), deadline = clock.now + timeLimit
        while flock(file, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EINTR, clock.now < deadline else {
                close(file)
                throw GitHubError(status: 0, message: "Another app's renewal of the sign-in didn't finish.")
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return Lease(file: file)
    }

    struct Lease: RenewalLease {
        let file: Int32

        func release() {
            flock(file, LOCK_UN)
            close(file)
        }
    }
}
