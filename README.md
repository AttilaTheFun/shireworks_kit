# Shireworks Kit

What an app developed through Shireworks builds in: a set of capabilities,
one library each, with more to come. It was two packages until 0.1.0:
update_kit and shake_kit, whose histories it carries.

| Product | What it does |
| --- | --- |
| `ShireworksKit` | All of the below but the installer's rules, in one import |
| `ShireworksShake` | Shake to report a bug, filed as a GitHub issue (docs/shake) |
| `ShireworksUpdates` | Record the build the app is, and hear of its updates (docs/updates) |
| `ShireworksCrashes` | The app's crashes, filed as GitHub issues, one a crash (docs/crashes) |
| `ShireworksUpdatesInstall` | A sandboxed Mac app's installer service's rules (docs/updates/Installing.md) |
| `GitHubAuth` | The sign-in an owner's apps share |
| `GitHubIssues` | GitHub's issues, as a client |
| `IssueComposer` | The SwiftUI issue composer |

    .package(url: "https://github.com/AttilaTheFun/shireworks_kit.git", exact: "0.1.0")

    .product(name: "ShireworksKit", package: "shireworks_kit")

    import ShireworksKit

    WindowGroup {
        ContentView()
            .shakeToReport(repository: "owner/app")
    }
    .commands { ShakeKitCommands() }   // Help › Report a Bug… (⌥⌘B)

An app is configured by its Info.plist, which the distributor's CI stamps
in: the shared sign-in's keys (`GitHubSharedClientID`,
`GitHubSharedKeychainGroup`, `GitHubSharedLockGroup`), Updates' app group
and bundle ids (`UpdateKitAppGroup`, `UpdateKitApplicationsBundleIDs`,
`UpdateKitReleasesRepository`), Shake's scope (`ShakeKitScope`) and the
repository crashes are filed in (`ShireworksRepository`). Without them a
capability does nothing.

## Crashes

Started once, at launch; the last run's crash is filed at the next, as an
issue in the app's repository (docs/crashes):

    ShireworksCrashes.start()

## From update_kit and shake_kit

One pin replaces both; the Info.plist keys and the API are the same.

- `update_kit` 0.19 → `shireworks_kit` 0.1: `import UpdateKit` becomes
  `import ShireworksUpdates` (or `ShireworksKit`), `import UpdateKitInstall`
  becomes `import ShireworksUpdatesInstall`, and the products are named so.
- `shake_kit` 0.4 → `shireworks_kit` 0.1: `import ShakeKit` becomes
  `import ShireworksShake` (or `ShireworksKit`); `GitHubAuth`,
  `GitHubIssues` and `IssueComposer` keep their names.
- With rules_swift_package_manager, the repository is `swiftpkg_shireworks_kit`.

update_kit's and shake_kit's tags stay in those repositories, so their pins
keep resolving until each app moves; then they're archived.

`swift test` passes on Linux and on a Mac. Updates works on Linux and
Isomer's hosts too; Shake's views are Apple's systems' only for now, and
Crashes catches crashes on iOS and macOS only.

## Releasing

A release is proposed by hand, on main, and released by the owner in
Reviews, which publishes the draft and makes its `v<version>` tag:

    gh workflow run Release --ref main -f version=0.1.0

It runs the tests on Linux and on a Mac, builds the libraries for the iOS
Simulator, makes the proof from the tests' results (build_tools'
tests-proof), compares it with the release before's (proof-diff), and
proposes the draft "Shireworks Kit <version>" with both attached. One
release a minor line.
