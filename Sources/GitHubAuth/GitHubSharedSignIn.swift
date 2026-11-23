import Foundation

/// A sign-in several of one owner's apps share: one OAuth App's token, kept in a keychain access group they all carry,
/// renewed under a lock in an app group container they all carry too, so signing in in one signs in all of them. What
/// it is comes from the host's Info.plist, stamped by its distributor's CI (a public repository names none of it):
///
///     <key>GitHubSharedClientID</key>       <string>the OAuth App's client id</string>
///     <key>GitHubSharedKeychainGroup</key>  <string>TEAMID.com.example.github</string>
///     <key>GitHubSharedLockGroup</key>      <string>group.com.example.github</string>
///     <key>GitHubSharedKeychainService</key> <string>com.example.github</string>   (optional)
///
/// The app's entitlements must grant both groups. A build for other people carries neither the keys nor the groups,
/// and has its own sign-in, or none.
public struct GitHubSharedSignIn: Sendable, Equatable {
    public var clientID: String
    public var keychainGroup: String
    /// The app group whose container holds the renewal lock.
    public var lockGroup: String
    public var keychainService: String

    public static let clientIDKey = "GitHubSharedClientID"
    public static let keychainGroupKey = "GitHubSharedKeychainGroup"
    public static let lockGroupKey = "GitHubSharedLockGroup"
    public static let keychainServiceKey = "GitHubSharedKeychainService"
    /// The keychain service when the Info.plist names none.
    public static let defaultKeychainService = "github.shared-sign-in"
    /// The renewal lock's file, in the lock group's container.
    public static let lockFileName = "GitHubSharedSignIn.lock"

    public init(clientID: String, keychainGroup: String, lockGroup: String, keychainService: String = Self.defaultKeychainService) {
        self.clientID = clientID
        self.keychainGroup = keychainGroup
        self.lockGroup = lockGroup
        self.keychainService = keychainService
    }

    /// The shared sign-in an Info.plist names: nil unless it names the client id and both groups (a value a build
    /// didn't fill in, `$(…)`, counts as none).
    public static func from(info: [String: Any]?) -> GitHubSharedSignIn? {
        func value(_ key: String) -> String? {
            guard let text = (info?[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
                  !text.contains("$(") else { return nil }
            return text
        }
        guard let clientID = value(clientIDKey), let keychainGroup = value(keychainGroupKey), let lockGroup = value(lockGroupKey) else {
            return nil
        }
        return GitHubSharedSignIn(clientID: clientID, keychainGroup: keychainGroup, lockGroup: lockGroup,
                                  keychainService: value(keychainServiceKey) ?? defaultKeychainService)
    }

    /// The main bundle's, if it names one.
    public static var main: GitHubSharedSignIn? { from(info: Bundle.main.infoDictionary) }

    /// The renewal lock's path in `container` (the lock group's container, as the system gives it).
    public func lockPath(in container: URL) -> String { container.appendingPathComponent(Self.lockFileName).path }

    #if canImport(Security)
    /// Its store: the shared keychain group's.
    public var store: KeychainTokenStore { KeychainTokenStore(service: keychainService, accessGroup: keychainGroup) }

    /// The renewal lock, in the lock group's container; nil where the app can't reach that container (its
    /// entitlements don't grant the group).
    public var lock: FileRenewalLock? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: lockGroup) else { return nil }
        return FileRenewalLock(path: lockPath(in: container))
    }

    /// A sign-in on it, asking for `scope` when it signs in by code. Nil where the lock's container can't be reached:
    /// renewing without the others' lock could sign them out.
    @MainActor
    public func credentials(scope: String?) -> GitHubCredentials? {
        guard let lock else { return nil }
        return GitHubCredentials(clientID: clientID, scope: scope, store: store, renewalLock: lock)
    }
    #endif
}
