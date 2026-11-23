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

0.1.0 ships `GitHubAuth`, `GitHubIssues` and `IssueComposer`; `ShakeKit` itself
comes in 0.2.0. `swift test` runs on Linux and on a Mac.

## Releasing

A release is proposed by hand, from main, and released by the owner in
Reviews, which publishes the draft and makes its `v<version>` tag:

    gh workflow run Release --ref main -f version=0.1.0

It runs the tests on Linux and on macOS, builds the libraries for the iOS
Simulator, makes the tests' proof (build_tools' `tests-proof`, compared with
the release before by `proof-diff`), and proposes the draft "Shake Kit
<version>" with them attached.
