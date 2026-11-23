// ShakeKit's views, on Apple's systems only for now (Isomer's hosts lack
// the shake, the screenshot and the keychain it needs).
#if canImport(UIKit) || canImport(AppKit)
import GitHubAuth
import IssueComposer
import SwiftUI

extension View {
    /// A shake (or Help › Report a Bug… on a Mac, with `ShakeKitCommands`)
    /// opens a bug report, filed as an issue in `repository` ("owner/name"),
    /// for someone signed in to the host's shared sign-in on this device. A
    /// build that carries no shared sign-in gets the view back untouched.
    @ViewBuilder
    public func shakeToReport(repository: String, configuration: ShakeKitConfiguration = .main) -> some View {
        if ShakeReport.isOffered {
            modifier(ShakeToReport(repository: repository, configuration: configuration))
        } else {
            self
        }
    }

    /// While `paused` is true, ShakeKit ignores shakes, for a view that needs
    /// the shake itself. Put it anywhere below `.shakeToReport`; while any
    /// such view says true, shakes are ignored. The Mac's menu command and
    /// `ShakeReport.request()` still work.
    public func shakeToReportPaused(_ paused: Bool = true) -> some View {
        preference(key: ShakesPausedKey.self, value: paused)
    }
}

/// Whether any view below asks for shakes to be ignored.
struct ShakesPausedKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

struct ShakeToReport: ViewModifier {
    @State private var report: ShakeReport

    init(repository: String, configuration: ShakeKitConfiguration) {
        _report = State(initialValue: ShakeReport(repository: repository, configuration: configuration))
    }

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(ShakesPausedKey.self) { paused in
                report.shakesPaused = paused
            }
            .onReceive(NotificationCenter.default.publisher(for: ShakeReport.requested)) { notification in
                report.present(notification.object as? ShakeReport.Trigger ?? .request)
            }
            .sheet(isPresented: $report.isPresented) {
                NewIssueSheet(model: report.composer, title: "Report a Bug") {
                    ReportDetails(report: report)
                }
            }
            .alert("Report a Bug", isPresented: $report.showsSignInNotice) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(ShakeReport.signInNotice)
            }
    }
}

/// Help › Report a Bug… (⌥⌘B), for a Mac (and an iPad's keyboard), where
/// there's no shake. Left out of a build that carries no shared sign-in.
public struct ShakeKitCommands: Commands {
    public init() {}

    public var body: some Commands {
        CommandGroup(after: .help) {
            if ShakeReport.isOffered {
                Button("Report a Bug…") { ShakeReport.request() }
                    .keyboardShortcut("b", modifiers: [.command, .option])
            }
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
                Text("Filed in \(report.repository), as you, through the sign-in your apps share.")
            }
        }
    }
}
#endif
