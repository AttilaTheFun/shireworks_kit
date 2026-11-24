// One import gives an app every capability: each module's names reach it
// through `import ShireworksKit` alone.
import ShireworksKit
import Testing

struct ShireworksKitTests {
    @Test func oneImportReachesEveryCapability() {
        // ShireworksUpdates, GitHubAuth and ShireworksShake, by a name each.
        _ = UpdateKitInfo.self
        _ = GitHubSharedSignIn.self
        _ = ShakeKitConfiguration.self
    }
}
