// swift-tools-version: 6.0

// Shake Kit: report a bug from inside an app, as a GitHub issue with
// screenshots and logs (docs/Design.md). Four libraries, each building on
// the ones before it: GitHubAuth (sign-in), GitHubIssues (the REST client),
// IssueComposer (the SwiftUI composer) and ShakeKit (the shake, the
// screenshot and the logs). Other repositories depend on it by version (its
// tags), through SwiftPM or rules_swift_package_manager.
import PackageDescription

let package = Package(
    name: "shake_kit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GitHubAuth", targets: ["GitHubAuth"]),
        .library(name: "GitHubIssues", targets: ["GitHubIssues"]),
        .library(name: "IssueComposer", targets: ["IssueComposer"]),
        .library(name: "ShakeKit", targets: ["ShakeKit"]),
    ],
    targets: [
        .target(name: "GitHubAuth"),
        .target(name: "GitHubIssues", dependencies: ["GitHubAuth"]),
        .target(name: "IssueComposer"),
        .target(name: "ShakeKit", dependencies: ["GitHubAuth", "GitHubIssues", "IssueComposer"]),
        .testTarget(name: "IssueComposerTests", dependencies: ["IssueComposer"]),
    ],
    swiftLanguageModes: [.v6]
)
