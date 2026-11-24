// ShakeKit's views, on Apple's systems only for now (Isomer's hosts lack
// the shake, the screenshot and the keychain it needs).
#if canImport(UIKit) || canImport(AppKit)
import GitHubAuth
import IssueComposer
import SwiftUI
#if os(macOS)
import AppKit
#endif

extension View {
    /// A shake (or Help › Report a Bug… on a Mac, with `ShakeKitCommands`)
    /// opens a bug report, filed as an issue in `repository` ("owner/name"),
    /// for someone signed in to the host's shared sign-in on this device. A
    /// build that carries no shared sign-in gets the view back untouched.
    /// Put it on every window: a request opens the report in the one made
    /// key (or active) most recently, once.
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
    /// This view, to ReportPresenters.
    @State private var id = UUID()
    #if os(macOS)
    @Environment(\.controlActiveState) private var activeState
    /// Its window key.
    private var isActive: Bool { activeState == .key }
    #else
    @Environment(\.scenePhase) private var scenePhase
    /// Its scene in front.
    private var isActive: Bool { scenePhase == .active }
    #endif

    init(repository: String, configuration: ShakeKitConfiguration) {
        _report = State(initialValue: ShakeReport(repository: repository, configuration: configuration))
    }

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(ShakesPausedKey.self) { paused in
                report.shakesPaused = paused
            }
            .onAppear { ReportPresenters.shared.set(id, active: isActive) }
            .onChange(of: isActive) { _, active in ReportPresenters.shared.set(id, active: active) }
            .onDisappear { ReportPresenters.shared.remove(id) }
            // One view answers (ReportPresenters): the key window's, not every window's.
            .onReceive(NotificationCenter.default.publisher(for: ShakeReport.requested)) { notification in
                guard ReportPresenters.shared.answers(id) else { return }
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
/// there's no shake: the key window's `.shakeToReport` opens the report;
/// with none (a menu-bar app's windows all closed), the app's
/// `ShakeKitReportWindow`, if it added one. Left out of a build that
/// carries no shared sign-in.
public struct ShakeKitCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some Commands {
        CommandGroup(after: .help) {
            if ShakeReport.isOffered {
                Button("Report a Bug…") { ShakeReport.request(opening: openWindow) }
                    .keyboardShortcut("b", modifiers: [.command, .option])
            }
        }
    }
}

/// Report a Bug…, as a button, for where the menu command isn't: a
/// menu-bar app's MenuBarExtra, or an app's own Help screen. It does what
/// Help › Report a Bug… does. Nothing in a build that carries no shared
/// sign-in.
public struct ShakeKitReportButton: View {
    let title: String
    @Environment(\.openWindow) private var openWindow

    public init(_ title: String = "Report a Bug…") {
        self.title = title
    }

    public var body: some View {
        if ShakeReport.isOffered {
            Button(title) { ShakeReport.request(opening: openWindow) }
        }
    }
}

extension ShakeReport {
    /// A deliberate request (the menu command, the button): the key
    /// window's `.shakeToReport` answers it; with none, on a Mac, the app's
    /// `ShakeKitReportWindow` opens, if it added one; else the request is
    /// posted as `request()` posts it.
    static func request(opening openWindow: OpenWindowAction) {
        #if os(macOS)
        if !ReportPresenters.shared.hasActive, ShakeKitReportWindow.isAdded {
            openWindow(id: ShakeKitReportWindow.id)
            // A menu-bar app isn't in front: the window would open behind.
            NSApplication.shared.activate()
            return
        }
        #endif
        request()
    }
}

#if os(macOS)
/// ShakeKit's own window for a report, for a Mac app whose windows may all
/// be closed (a menu-bar app): Help › Report a Bug… (or
/// `ShakeKitReportButton`) opens it when no key window carries
/// `.shakeToReport`. Add it to the app's `body`, beside its other scenes.
/// It takes no screenshot (there's no window of the app's to take).
public struct ShakeKitReportWindow: Scene {
    /// The window's id, for `openWindow(id:)`.
    public static let id = "shakekit.report"
    /// Whether the app added one (its `body` made one).
    @MainActor static var isAdded = false

    let repository: String
    let configuration: ShakeKitConfiguration

    @MainActor
    public init(repository: String, configuration: ShakeKitConfiguration = .main) {
        self.repository = repository
        self.configuration = configuration
        Self.isAdded = ShakeReport.isOffered
    }

    public var body: some Scene {
        Window("Report a Bug", id: Self.id) {
            ReportWindowContent(repository: repository, configuration: configuration)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

/// The report window's content: the composer at once, or the sign-in
/// notice; closed when it's done.
struct ReportWindowContent: View {
    @State private var report: ShakeReport
    @Environment(\.dismissWindow) private var dismissWindow

    init(repository: String, configuration: ShakeKitConfiguration) {
        _report = State(initialValue: ShakeReport(repository: repository, configuration: configuration, screenshot: { nil }))
    }

    var body: some View {
        Group {
            if report.showsSignInNotice {
                VStack(spacing: 16) {
                    Text(ShakeReport.signInNotice)
                    Button("OK") { close() }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(24)
            } else if report.isPresented {
                NewIssueSheet(model: report.composer, title: "Report a Bug", close: close) {
                    ReportDetails(report: report)
                }
                .frame(minWidth: 480, minHeight: 420)
            } else {
                ProgressView().padding(24)
            }
        }
        .onAppear { report.present(.request) }
    }

    /// Done with: the window closed, and the report ready to open again.
    private func close() {
        report.isPresented = false
        report.showsSignInNotice = false
        dismissWindow(id: ShakeKitReportWindow.id)
    }
}
#endif

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
