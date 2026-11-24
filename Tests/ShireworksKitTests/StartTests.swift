@testable import ShireworksKit
import Testing
#if canImport(SwiftUI) && (canImport(UIKit) || canImport(AppKit))
import SwiftUI
#endif

/// `start()` runs once a process, however many windows' `.shireworks()`
/// appear (its starters replaced: the real ones would install the crash
/// recorder in the test runner).
@MainActor
@Suite(.serialized)
struct StartTests {
    @Test func startRunsOnce() {
        let crashes = ShireworksKit.startCrashes, updates = ShireworksKit.startUpdates, started = ShireworksKit.isStarted
        defer {
            ShireworksKit.startCrashes = crashes
            ShireworksKit.startUpdates = updates
            ShireworksKit.isStarted = started
        }
        var calls: [String] = []
        ShireworksKit.startCrashes = { calls.append("crashes \($0.repository ?? "none")") }
        ShireworksKit.startUpdates = { calls.append("updates \($0 ?? "none")") }
        ShireworksKit.isStarted = false

        ShireworksKit.start(crashes: CrashesConfiguration(repository: "owner/app"), appGroup: "group.com.example")
        ShireworksKit.start()
        ShireworksKit.start(crashes: CrashesConfiguration(repository: "owner/other"))

        #expect(calls == ["crashes owner/app", "updates group.com.example"])
        #expect(ShireworksKit.isStarted)
    }

    #if canImport(SwiftUI) && (canImport(UIKit) || canImport(AppKit))
    /// The one modifier an app adopts the kit by, with the repository from
    /// the Info.plist or given (made, not shown: showing it would start).
    @Test func theRootModifierIsThere() {
        _ = Text("App").shireworks()
        _ = Text("App").shireworks(repository: "owner/app")
    }
    #endif
}
