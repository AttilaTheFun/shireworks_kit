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

    .package(url: "https://github.com/AttilaTheFun/shake_kit.git", exact: "0.1.0")

    .product(name: "ShakeKit", package: "shake_kit")

Not released yet: 0.1.0 is the first version. `swift test` runs on Linux
and on a Mac.
