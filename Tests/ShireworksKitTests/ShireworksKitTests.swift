// One import gives an app every capability: each module's names reach it
// through `import ShireworksKit` alone.
import ShireworksKit
import Testing

struct ShireworksKitTests {
    @Test func oneImportReachesEveryCapability() {
        // ShireworksUpdates, GitHubAuth, ShireworksShake and ShireworksCrashes, by a name each.
        _ = UpdateKitInfo.self
        _ = GitHubSharedSignIn.self
        _ = ShakeKitConfiguration.self
        _ = CrashReport.self
    }

    /// The call for a process without SwiftUI views is there, with crashes' and updates' settings (not run here: it
    /// would install the crash recorder in the test runner; StartTests runs it with its starters replaced).
    @MainActor @Test func oneCallStartsThem() {
        let start: @MainActor (CrashesConfiguration, String?) -> Void = ShireworksKit.start(crashes:appGroup:)
        _ = start
    }
}
