// Every capability of Shireworks Kit, in one import: `import ShireworksKit`
// gives an app the shake to report (ShireworksShake), its updates
// (ShireworksUpdates), its crashes filed (ShireworksCrashes), and the shared
// sign-in, issues client and composer they file with. The installer
// service's rules (ShireworksUpdatesInstall) aren't among them: only that
// service links them.
@_exported import GitHubAuth
@_exported import GitHubIssues
@_exported import IssueComposer
@_exported import ShireworksCrashes
@_exported import ShireworksShake
@_exported import ShireworksUpdates

/// What an app starts once, for every capability that runs by itself: its
/// crashes caught and filed (ShireworksCrashes), and its build recorded in
/// the app group and, on a Mac, Shireworks' offers of its updates answered
/// (ShireworksUpdates' `AppUpdates.start`: the update sheet, unless the app
/// registered its own answer). An app with SwiftUI views doesn't call it:
/// `.shireworks()` on its root view starts it (`ShireworksView.swift`). A
/// process without them (a headless server, an AppKit-only app) calls
/// `start()` at launch, on the main actor, after any
/// `AppUpdates.register(…)`. Each capability does nothing without its
/// Info.plist keys (README, "Adopting"). Where there's no Darwin (Linux,
/// Isomer's hosts), Updates' own `AppUpdates` isn't there to start, and
/// crashes aren't caught: it does nothing.
public enum ShireworksKit {
    /// Whether `start` has run in this process: it runs once, however many
    /// windows' `.shireworks()` appear.
    @MainActor public internal(set) static var isStarted = false

    /// What `start` starts (tests replace them).
    @MainActor static var startCrashes: @MainActor (CrashesConfiguration) -> Void = { ShireworksCrashes.start(configuration: $0) }
    @MainActor static var startUpdates: @MainActor (String?) -> Void = { appGroup in
        #if canImport(Darwin)
        AppUpdates.start(appGroup: appGroup)
        #endif
    }

    /// Starts crashes and updates, once a process: asked again, it does
    /// nothing.
    @MainActor
    public static func start(crashes: CrashesConfiguration = .main, appGroup: String? = nil) {
        guard !isStarted else { return }
        isStarted = true
        startCrashes(crashes)
        startUpdates(appGroup)
    }
}
