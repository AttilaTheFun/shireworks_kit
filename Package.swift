// swift-tools-version: 6.0

// Shireworks Kit: what an app developed through Shireworks builds in, one
// capability a library (the owner, 2026-11-24: shake_kit and update_kit in one
// package, "a set of capabilities built into apps developed through shireworks
// and we may add other capabilities in the future"):
//
// - ShireworksShake: report a bug from inside the app (shake_kit's ShakeKit).
// - ShireworksUpdates: record the build the app is and hear of its updates
//   (update_kit's UpdateKit); ShireworksUpdatesInstall, the Mac installer
//   service's rules.
// - GitHubAuth, GitHubIssues and IssueComposer: the shared sign-in, the
//   issues client and the composer the capabilities file with.
// - ShireworksKit: all of them, in one import.
//
// Other repositories depend on it by version (its tags), through SwiftPM or
// rules_swift_package_manager. Its history is update_kit's and shake_kit's,
// both kept (their tags stay in those repositories).
import PackageDescription

let package = Package(
    name: "shireworks_kit",
    // The apps' own minimums are higher.
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ShireworksKit", targets: ["ShireworksKit"]),
        .library(name: "ShireworksShake", targets: ["ShireworksShake"]),
        .library(name: "ShireworksUpdates", targets: ["ShireworksUpdates"]),
        // An installer service's rules and its Mac (docs/updates/Installing.md): for the unsandboxed service inside
        // a sandboxed app, which links nothing else of the package.
        .library(name: "ShireworksUpdatesInstall", targets: ["ShireworksUpdatesInstall"]),
        .library(name: "GitHubAuth", targets: ["GitHubAuth"]),
        .library(name: "GitHubIssues", targets: ["GitHubIssues"]),
        .library(name: "IssueComposer", targets: ["IssueComposer"]),
    ],
    dependencies: [
        // A range, not one version: the apps pin swift_sql themselves, and their pin is the one taken.
        .package(url: "https://github.com/AttilaTheFun/swift_sql.git", from: "0.35.0"),
    ],
    targets: [
        .target(name: "ShireworksKit", dependencies: ["ShireworksShake", "ShireworksUpdates", "GitHubAuth", "GitHubIssues", "IssueComposer"]),
        .target(name: "GitHubAuth"),
        .target(name: "GitHubIssues", dependencies: ["GitHubAuth"]),
        .target(name: "IssueComposer"),
        .target(name: "ShireworksShake", dependencies: ["GitHubAuth", "GitHubIssues", "IssueComposer"]),
        .target(name: "ShireworksUpdates", dependencies: [.product(name: "SwiftSQL", package: "swift_sql")]),
        .target(name: "ShireworksUpdatesInstall"),
        .testTarget(name: "ShireworksKitTests", dependencies: ["ShireworksKit"]),
        .testTarget(name: "GitHubAuthTests", dependencies: ["GitHubAuth"]),
        .testTarget(name: "GitHubIssuesTests", dependencies: ["GitHubIssues"]),
        .testTarget(name: "IssueComposerTests", dependencies: ["IssueComposer"]),
        .testTarget(name: "ShireworksShakeTests", dependencies: ["ShireworksShake", "GitHubAuth", "GitHubIssues", "IssueComposer"]),
        .testTarget(name: "ShireworksUpdatesTests", dependencies: ["ShireworksUpdates", .product(name: "SwiftSQL", package: "swift_sql")]),
        .testTarget(name: "ShireworksUpdatesInstallTests", dependencies: ["ShireworksUpdatesInstall"]),
    ],
    swiftLanguageModes: [.v6]
)
