#if canImport(SwiftUI)
import GitHubAuth
import IssueComposer
import SwiftUI

extension View {
    /// A shake (or Help › Report a Bug… on a Mac, with `ShakeKitCommands`)
    /// opens a bug report, filed as an issue in `repository` ("owner/name").
    /// It does nothing unless `configuration` is on: by default, unless the
    /// app's Info.plist opts in (`ShakeKitConfiguration.from(info:)`).
    @ViewBuilder
    public func shakeToReport(repository: String, configuration: ShakeKitConfiguration = .main) -> some View {
        if configuration.isEnabled {
            modifier(ShakeToReport(repository: repository, configuration: configuration))
        } else {
            self
        }
    }
}

struct ShakeToReport: ViewModifier {
    @State private var report: ShakeReport

    init(repository: String, configuration: ShakeKitConfiguration) {
        _report = State(initialValue: ShakeReport(repository: repository, configuration: configuration))
    }

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: ShakeReport.requested)) { notification in
                report.present(notification.object as? ShakeReport.Trigger ?? .request)
            }
            .sheet(isPresented: $report.isPresented) {
                ShakeReportSheet(report: report)
            }
    }
}

/// Help › Report a Bug… (⌥⌘B), for a Mac (and an iPad's keyboard), where
/// there's no shake.
/// Left out when ShakeKit is off (a release build that doesn't opt in).
public struct ShakeKitCommands: Commands {
    let configuration: ShakeKitConfiguration

    public init(configuration: ShakeKitConfiguration = .main) {
        self.configuration = configuration
    }

    public var body: some Commands {
        CommandGroup(after: .help) {
            if configuration.isEnabled {
                Button("Report a Bug…") { ShakeReport.request() }
                .keyboardShortcut("b", modifiers: [.command, .option])
            }
        }
    }
}

/// The composer once signed in, the sign-in before.
struct ShakeReportSheet: View {
    @Bindable var report: ShakeReport

    var body: some View {
        if report.credentials.state == .signedIn {
            NewIssueSheet(model: report.composer, title: "Report a Bug") {
                ReportDetails(report: report)
            }
        } else {
            SignInSheet(credentials: report.credentials)
        }
    }
}

/// What goes into the issue besides what the person writes, to look at
/// before sending.
struct ReportDetails: View {
    @Bindable var report: ShakeReport

    var body: some View {
        Section {
            DisclosureGroup("App and device") {
                Text(report.environment.markdown)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
            if let logs = report.logs {
                Toggle("Include the app's logs", isOn: $report.includeLogs)
                if report.includeLogs {
                    DisclosureGroup("Logs") {
                        ScrollView {
                            Text(logs)
                                .font(.caption2.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 240)
                    }
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if report.configuration.scope == "public_repo" {
                    Text("This issue and its attachments will be public.")
                }
                Text("Filed in \(report.repository).")
                if !report.usesSharedSignIn {
                    Button("Sign Out of GitHub") { report.credentials.signOut() }
                        .buttonStyle(.borderless)
                }
            }
        }
    }
}

/// Signing in by code: the code to enter at github.com/login/device.
struct SignInSheet: View {
    @Bindable var credentials: GitHubCredentials
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    switch credentials.state {
                    case .signedOut:
                        Text("Sign in to GitHub to report a bug. The issue is filed as you.")
                        Button("Sign In to GitHub") { credentials.signInByCode() }
                    case .asking:
                        ProgressView()
                    case .entering(let code):
                        Text("Enter this code at GitHub:")
                        Text(code.userCode)
                            .font(.largeTitle.monospaced())
                            .textSelection(.enabled)
                        Link("Open \(code.verificationURI.host() ?? "GitHub")", destination: code.verificationURI)
                    case .signedIn:
                        EmptyView()
                    }
                    if let problem = credentials.problem {
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Report a Bug")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        credentials.cancelSignIn()
                        dismiss()
                    }
                }
            }
        }
    }
}
#endif
