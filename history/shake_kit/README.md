# Shake Kit

Report a bug from inside an app: shake the phone (or pick Help › Report a
Bug… on a Mac), add a title and a few words, and it opens a GitHub issue in
the app's repository with a screenshot of the moment, the app's recent
logs and its version. The design is [docs/Design.md](docs/Design.md).

Four libraries, each building on the ones before it:

| Product | What it is |
| --- | --- |
| `GitHubAuth` | Device-flow sign-in, tokens and their keychain store |
| `GitHubIssues` | GitHub's issues REST API and attachment upload |
| `IssueComposer` | The SwiftUI issue composer |
| `ShakeKit` | The shake, the screenshot, the logs, and the composer filled in |

    .package(url: "https://github.com/AttilaTheFun/shake_kit.git", exact: "0.4.0")

    .product(name: "ShakeKit", package: "shake_kit")

In the app:

    import ShakeKit

    WindowGroup {
        ContentView()
            .shakeToReport(repository: "owner/app")
    }
    .commands { ShakeKitCommands() }   // Help › Report a Bug… (⌥⌘B)

ShakeKit has no sign-in of its own. It reports with the sign-in the host's
apps share (`GitHubSharedSignIn`): the build needs its Info.plist keys
(`GitHubSharedClientID`, `GitHubSharedKeychainGroup`, `GitHubSharedLockGroup`)
and entitlements granting that keychain group and app group. The owner's apps
stamp them in from CI in **every build**, production included. A build
without them gets the view back untouched and no menu item. Set
`ShakeKitScope` to `repo` if the repository is private (the default is
`public_repo`).

Only someone signed in to the shared sign-in on the device (through the
owner's issues app) can report. For anyone else a shake does nothing; a
deliberate request (a Report a Bug button calling `ShakeReport.request()`,
or, on a Mac, Help › Report a Bug… from `ShakeKitCommands`) says to sign in
there. ShakeKit runs on Apple's systems only for now.

Put `.shakeToReport` on every window: a request opens the report once, in
the window made key (on iOS, the scene made active) most recently.

A Mac app whose windows may all be closed (a menu-bar app) adds ShakeKit's
own report window as a scene, and a button for its menu-bar menu:

    var body: some Scene {
        MenuBarExtra("App", systemImage: "cloud") {
            ShakeKitReportButton()   // Report a Bug…
        }
        Window("App", id: "main") { MainView().shakeToReport(repository: "owner/app") }
        ShakeKitReportWindow(repository: "owner/app")
            .commands { ShakeKitCommands() }
    }

Help › Report a Bug… and `ShakeKitReportButton` open the report in the key
window's `.shakeToReport`, or, with none, in `ShakeKitReportWindow` (without
a screenshot: no window of the app's is open). `ShakeReport.request()` only
reaches a `.shakeToReport`.

A view that needs the shake itself (a "shake to leave", say) pauses
ShakeKit's with `.shakeToReportPaused(true)` while it's showing. The pause is a
SwiftUI preference, and preferences don't cross a presentation: for a view
shown in a sheet or `fullScreenCover`, put `.shakeToReportPaused(isPresented)`
on the view that presents it, not inside it.

On iOS, ShakeKit hears the shake through an override of `UIWindow`'s
`motionEnded`, which applies to every window of the app; it calls `super`, so
the app's own handling still runs.

0.1.0 shipped `GitHubAuth`, `GitHubIssues` and `IssueComposer`; 0.2.0
`ShakeKit`; 0.3.0 makes the shared sign-in its only one; 0.4.0 answers a
request in one window (the key one) and adds the report window and button. `swift test` runs on Linux and on a Mac.

## Releasing

A release is proposed by hand, from main, and released by the owner in
Reviews, which publishes the draft and makes its `v<version>` tag:

    gh workflow run Release --ref main -f version=0.1.0

It runs the tests on Linux and on macOS, builds the libraries for the iOS
Simulator, makes the tests' proof (build_tools' `tests-proof`, compared with
the release before by `proof-diff`), and proposes the draft "Shake Kit
<version>" with them attached.
