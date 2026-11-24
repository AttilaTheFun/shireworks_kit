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
