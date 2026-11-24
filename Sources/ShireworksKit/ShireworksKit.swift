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

/// What an app calls once at launch, on the main actor, for every capability
/// that runs by itself: its crashes caught and filed (ShireworksCrashes), and
/// its build recorded in the app group and its updates heard of
/// (ShireworksUpdates' `AppUpdates.start`). After any `AppUpdates.register(…)`;
/// shake to report is the views' own (`.shakeToReport`). Each capability does
/// nothing without its Info.plist keys (README, "Adopting"). Where there's no
/// Darwin (Linux, Isomer's hosts), Updates' own `AppUpdates` isn't there to
/// start, and crashes aren't caught: it does nothing.
public enum ShireworksKit {
    @MainActor
    public static func start(crashes: CrashesConfiguration = .main, appGroup: String? = nil) {
        ShireworksCrashes.start(configuration: crashes)
        #if canImport(Darwin)
        AppUpdates.start(appGroup: appGroup)
        #endif
    }
}
