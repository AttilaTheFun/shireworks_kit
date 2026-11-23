import Foundation
#if canImport(Security)
import Security
#endif

/// Where a sign-in's token is kept, by the GitHub App's client id that
/// issued it (a token renews only with its own client id): "" for a token
/// pasted. Apple's platforms keep it in the keychain (`KeychainTokenStore`,
/// in the host app's own access group); another platform gives its own
/// (the Android Keystore's, a file of the user's, the web page's storage),
/// or keeps it in memory (`MemoryTokenStore`).
public protocol TokenStore: Sendable {
    func token(for clientID: String) -> GitHubToken?
    func keep(_ token: GitHubToken?, for clientID: String)
    /// What names the tokens this store keeps, the same for every store of
    /// a process that keeps the same ones (one keychain service and group):
    /// GitHubCredentials on stores of one key hear each other's changes at
    /// once. Nil (the default): none shared.
    var sharingKey: String? { get }
}

extension TokenStore {
    public var sharingKey: String? { nil }
}

/// A store in memory, for tests, fixtures and platforms without a
/// keychain: its tokens go with the process.
public final class MemoryTokenStore: TokenStore {
    private let tokens: Locked<[String: GitHubToken]>

    public init(_ tokens: [String: GitHubToken] = [:]) {
        self.tokens = Locked(tokens)
    }

    public func token(for clientID: String) -> GitHubToken? { tokens.withLock { $0[clientID] } }

    /// This store's own: the sign-ins on this one object share it.
    public var sharingKey: String? { "memory:" + String(describing: ObjectIdentifier(self)) }

    public func keep(_ token: GitHubToken?, for clientID: String) {
        tokens.withLock { $0[clientID] = token }
    }
}

#if canImport(Security)
/// The keychain's: a generic password of `service`, its account derived
/// from the client id (`accountPrefix` and the client id, or "pasted" for
/// a token pasted: "token.Iv1.example", "token.pasted"), kept after first
/// unlock, on this device only. On the Mac, the data protection keychain
/// (the iPhone's kind), which access groups need.
///
/// It is kept in the host app's own access group: `accessGroup` as the app
/// gives it (one its keychain-access-groups entitlement lists, with its
/// team id: `<team id>.com.example.App`), or nil for the app's default.
/// The group must never be one another app's GitHub sign-in uses, or one
/// sign-in would replace the other.
public struct KeychainTokenStore: TokenStore {
    public let service: String
    /// The access group, in full; nil for the app's default.
    public let accessGroup: String?
    /// What the account names start with, before the client id.
    public let accountPrefix: String

    /// The host's store: its keychain `service` (its bundle id, say, or one
    /// of its own), in `accessGroup` (nil: the app's default).
    public init(service: String, accessGroup: String? = nil, accountPrefix: String = "token.") {
        self.service = service
        self.accessGroup = accessGroup
        self.accountPrefix = accountPrefix
    }

    /// The account a client id's token is kept under.
    public func account(for clientID: String) -> String {
        accountPrefix + (clientID.isEmpty ? "pasted" : clientID)
    }

    /// On the Mac, the data protection keychain: access groups need it.
    private static func dataProtection(_ query: inout [String: Any]) {
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
    }

    /// One for every store of this service, group and prefix.
    public var sharingKey: String? { "keychain:" + service + ":" + (accessGroup ?? "") + ":" + accountPrefix }

    private func query(_ clientID: String) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account(for: clientID)]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        Self.dataProtection(&query)
        return query
    }

    public func token(for clientID: String) -> GitHubToken? {
        var query = query(clientID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(GitHubToken.self, from: data)
    }

    public func keep(_ token: GitHubToken?, for clientID: String) {
        let query = query(clientID)
        guard let token, let data = try? JSONEncoder().encode(token) else {
            SecItemDelete(query as CFDictionary)
            return
        }
        if SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
#endif
