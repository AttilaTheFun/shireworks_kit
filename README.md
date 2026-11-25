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

    @main struct ExampleApp: App {
        var body: some Scene {
            WindowGroup {
                ContentView()
                    .shireworks()   // crashes, updates, shake to report
            }
            .commands { ShakeKitCommands() }   // extra, on a Mac: Help › Report a Bug… (⌥⌘B)
        }
    }

`.shireworks()` on the root view is the whole adoption. At its first
appearance it starts crashes and updates, once a process
(`ShireworksKit.start()`); it puts shake to report on the view, filed in the
Info.plist's `ShireworksRepository` (or `.shireworks(repository:)`'s); and on
a Mac, Shireworks' offers of the app's newer build, heard through the app
group (its signal, every five minutes, and as the app comes to the front),
are answered with the update sheet: Update Now quits the app through its
normal path and Shireworks installs the build and opens it again; Later asks
again in an hour (docs/updates/Updates.md, "Updating automatically"). The
last run's crash is filed at the next launch, as an issue in the app's
repository (docs/crashes).

Extras: on a Mac, `.commands { ShakeKitCommands() }` for Help › Report a
Bug…; a menu-bar app adds `ShakeKitReportWindow` and `ShakeKitReportButton`
(docs/shake). An app that must answer updates itself (work in progress, an
install of its own) registers `AppUpdates.register(autoUpdate:)` (and
`register(install:)`) before its root view appears: its answer is used in
place of the sheet. A process without SwiftUI views (a headless server, an
AppKit-only app) calls `ShireworksKit.start()` at launch instead.

## Adopting: what every app meets

Every production build of an app the owner distributes through Shireworks:

1. **Links Shireworks Kit** (`ShireworksKit`) and puts `.shireworks()` on
   the app's root view (each window's), with `ShakeKitCommands` on a Mac;
   another process that runs the app's code without SwiftUI views (a
   headless server, for its crashes) calls `ShireworksKit.start()` at launch.
2. **Records its build** in the shared app group: `.shireworks()` does it
   (Updates), given the group key and entitlement below, so Applications
   always knows the installed build (never "Unknown").
3. **Carries, stamped in by its CI** (never in its repository):
   - `GitHubSharedClientID`, `GitHubSharedKeychainGroup`,
     `GitHubSharedLockGroup`: the shared sign-in reports and crashes file with;
   - `ShakeKitScope` (`repo` for a private repository);
   - `ShireworksRepository`: `owner/name`, where crashes are filed;
   - `UpdateKitAppGroup` and, on a Mac, `UpdateKitApplicationsBundleIDs`;
   - `BuildVariant`: `Production`, `Alpha`, `Beta` or `AdHoc`.
4. **Is entitled** to the app group (application-groups) and the shared
   sign-in's keychain group (keychain-access-groups), granted by its
   profiles.
5. **Has a link scheme, its own name** (`<name>://`) in CFBundleURLTypes and
   its builds.json's `urlSchemes`, which Applications opens it by; on the
   iPhone and iPad, Shireworks lists the scheme to ask iOS about it.
6. **On a Mac, lets Shireworks update it while it runs:** `.shireworks()`
   answers Shireworks' offers of its newer build (automatic or a person's
   Install or Update, alike). With no handler, the kit's update sheet asks,
   on the app's front window: Update Now quits the app through its normal
   path (`NSApplication.terminate`) and Shireworks installs the build and
   opens it again; Later asks again in an hour. An app that must decide
   itself (work in progress, an install of its own) registers
   `AppUpdates.register(autoUpdate:)` before its root view appears
   (docs/updates/Updates.md, "Updating automatically").
7. **On Android (Isomer's hosts),** links the same `ShireworksKit` and puts
   the same `.shireworks()` on its root view, which gives it Report a Bug:
   a `ShakeKitReportButton` (or `ShakeReport.request()`) of the app's
   opens the report, without a screenshot or the app's logs (the issue
   says they weren't read). There's no shared sign-in there yet, so a
   report asks the app's own sign-in
   (`.shakeToReport(repository:credentials:)`), else says how to sign in.
   The shake and the screenshot come with Isomer's `.onShake` and its
   screenshot API; crashes and updates are Apple's systems' only for now
   (`.shireworks()` starts them, which does nothing there).

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

`swift test` passes on Linux and on a Mac. Every library builds for
Isomer's hosts (Android) too: Updates' checks run there, Shake's views and
`.shireworks()` give Report a Bug (above), and Crashes catches crashes on
iOS and macOS only.

## Releasing

A release is proposed by hand, on main, and released by the owner in
Reviews, which publishes the draft and makes its `v<version>` tag:

    gh workflow run Release --ref main -f version=0.1.0

It runs the tests on Linux and on a Mac, builds the libraries for the iOS
Simulator, makes the proof from the tests' results (build_tools'
tests-proof), compares it with the release before's (proof-diff), and
proposes the draft "Shireworks Kit <version>" with both attached. One
release a minor line.
