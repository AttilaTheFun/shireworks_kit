// The stores: a token kept, replaced and deleted by its client id, and the
// keychain's names derived from the host's service, group and client id.

import Foundation
@testable import GitHubAuth
import Testing

@Suite struct TokenStoreTests {
    @Test func memoryKeepsByClientID() {
        let store = MemoryTokenStore()
        #expect(store.token(for: "Iv1.example") == nil)
        store.keep(GitHubToken(access: "ghu_one", refresh: "ghr_one"), for: "Iv1.example")
        store.keep(GitHubToken(access: "github_pat_x"), for: "")
        #expect(store.token(for: "Iv1.example")?.access == "ghu_one")
        #expect(store.token(for: "")?.access == "github_pat_x")
        #expect(store.token(for: "Iv1.other") == nil)
        store.keep(nil, for: "Iv1.example")
        #expect(store.token(for: "Iv1.example") == nil, "signing out deletes the access and refresh tokens together")
        #expect(store.token(for: "")?.access == "github_pat_x")
    }

    /// Each memory store is its own: two never share a key.
    @Test func memoryStoresShareNothing() {
        let one = MemoryTokenStore(), other = MemoryTokenStore()
        #expect(one.sharingKey != nil)
        #expect(one.sharingKey == one.sharingKey)
        #expect(one.sharingKey != other.sharingKey)
    }

    @Test func aTokenRoundTrips() throws {
        let token = GitHubToken(access: "ghu_fixture", refresh: "ghr_fixture", expires: Date(timeIntervalSince1970: 1_793_122_860),
                                refreshExpires: Date(timeIntervalSince1970: 1_808_818_860))
        #expect(try JSONDecoder().decode(GitHubToken.self, from: JSONEncoder().encode(token)) == token)
    }

    @Test func expiresSoonWithinFiveMinutes() {
        let now = Date(timeIntervalSince1970: 1_793_094_060)
        #expect(GitHubToken(access: "a", expires: now.addingTimeInterval(299)).expiresSoon(now: now))
        #expect(!GitHubToken(access: "a", expires: now.addingTimeInterval(301)).expiresSoon(now: now))
        #expect(!GitHubToken(access: "a").expiresSoon(now: now), "a token with no end is never renewed")
    }

    #if canImport(Security)
    /// The keychain's names come from the host: its service and group, and
    /// the account from the client id. (Nothing is written to the keychain
    /// here: a test bundle has no keychain entitlement.)
    @Test func keychainNamesAreTheHosts() {
        let store = KeychainTokenStore(service: "com.example.App.github", accessGroup: "TEAMID.com.example.App")
        #expect(store.account(for: "Iv1.example") == "token.Iv1.example")
        #expect(store.account(for: "") == "token.pasted")
        #expect(KeychainTokenStore(service: "s", accountPrefix: "github.").account(for: "Iv1.example") == "github.Iv1.example")
        #expect(KeychainTokenStore(service: "s").accessGroup == nil)
        #expect(store.sharingKey != KeychainTokenStore(service: "com.example.App.github").sharingKey)
    }
    #endif
}
