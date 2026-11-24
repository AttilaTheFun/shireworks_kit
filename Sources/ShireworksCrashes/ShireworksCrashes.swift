// ShireworksCrashes: the app's crashes, caught on the device and filed as
// GitHub issues, one issue a crash (docs/crashes):
//
// - ShireworksCrashes: started once at launch, it records the app's crashes
//   (Platform: KSCrash on Apple's systems, on the device alone), keeps each
//   one in a CrashStore, and files them with the shared sign-in;
// - CrashReport: one crash, and its signature (CrashSignature); read from
//   the recorder's report by CrashRecording;
// - CrashStore: the crashes not yet filed, a folder of JSON files;
// - CrashFiler and CrashIssue: an issue opened, commented on or opened again,
//   and what it says;
// - CrashesConfiguration: where crashes are filed, how many are kept, and
//   whether a public repository's issues carry the reason and breadcrumbs.
//
// The crash recorder is an implementation detail: none of its types is in
// the API, and it sends nothing anywhere.
import Foundation
import GitHubAuth
import GitHubIssues

/// Crash reporting, filed as GitHub issues in the app's repository. Started
/// once, at launch:
///
///     ShireworksCrashes.start()
///
/// A crash is recorded as it happens, and handed over at the next launch,
/// as `start` starts the recorder: kept in the store (`CrashStore.standard()`, at most `maxStored`, for at
/// most `maxAge`), then filed in a background task (`CrashFiler`) with the
/// sign-in the host's apps share (`GitHubSharedSignIn`). Crashes has no
/// sign-in of its own: on a device with nobody signed in to that, nothing is
/// filed and the crashes stay kept, until someone is or they're pruned; a
/// sign-in GitHub refuses (a 401) leaves them kept too.
///
/// On Apple's systems (iOS and macOS) only; elsewhere `start` does nothing
/// and says so (false).
public enum ShireworksCrashes {
    /// Whether crashes are caught here: on iOS and macOS.
    public static var isSupported: Bool { Platform.isSupported }

    /// Whether `start` has started it.
    @MainActor public private(set) static var isStarted = false

    /// The sign-in and the filing, held for the app's run.
    @MainActor private static var credentials: GitHubCredentials?
    @MainActor private static var filing: CrashFiling?

    /// Starts catching crashes, and files those kept. By default: the main
    /// bundle's configuration (its `ShireworksRepository`), the app's own
    /// store, and its shared sign-in. `store`, `shared` and `send` replace
    /// those, for tests. Asked again, it does nothing. Whether it runs.
    @MainActor
    @discardableResult
    public static func start(
        configuration: CrashesConfiguration = .main,
        store: CrashStore = .standard(),
        shared: GitHubSharedSignIn? = .main,
        send: @escaping GitHubTransport.Send = GitHubTransport.network
    ) -> Bool {
        guard !isStarted, Platform.isSupported else { return isStarted }

        if configuration.files, let repository = configuration.repository, let signIn = Platform.sharedSignIn(shared) {
            credentials = signIn
            let client = GitHubIssuesClient(token: { try await signIn.access() }, send: send)
            filing = CrashFiling(
                filer: CrashFiler(client: client, repository: repository, labels: configuration.labels,
                                  redactions: configuration.redactions, publicDetails: configuration.publicDetails),
                store: store,
                signedIn: { @MainActor in
                    signIn.reload()
                    return signIn.state == .signedIn
                },
                refused: { @MainActor in signIn.refused() })
        }

        let executable = Platform.executableName
        let name = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        // The runs' before: each crash kept (and let go by the recorder), or
        // left with the recorder where it can't be kept now.
        isStarted = Platform.startCrashRecorder(folder: Platform.recorderFolder(name: name)) { record in
            guard let report = CrashRecording.report(from: record, executable: executable) else { return true }
            return (try? store.add(report)) != nil
        }
        store.prune(maxCount: configuration.maxStored, maxAge: configuration.maxAge)
        filing?.file()
        return isStarted
    }
}

/// The filing of the store's crashes, one pass at a time: a pass asked for
/// while one runs runs after it. A pass files nothing while nobody is
/// signed in.
final class CrashFiling: Sendable {
    private let filer: CrashFiler
    private let store: CrashStore
    private let signedIn: @Sendable () async -> Bool
    private let refused: @Sendable () async -> Void
    /// Whether a pass runs, and whether another is asked for after it.
    private let state = Locked((running: false, again: false))

    init(filer: CrashFiler, store: CrashStore, signedIn: @escaping @Sendable () async -> Bool,
         refused: @escaping @Sendable () async -> Void) {
        self.filer = filer
        self.store = store
        self.signedIn = signedIn
        self.refused = refused
    }

    /// Asks for a pass, in the background.
    func file() {
        let start = state.withLock { state -> Bool in
            if state.running {
                state.again = true
                return false
            }
            state.running = true
            return true
        }
        guard start else { return }
        Task.detached(priority: .utility) { await self.passes() }
    }

    private func passes() async {
        repeat {
            state.withLock { $0.again = false }
            await pass()
        } while state.withLock({ state -> Bool in
            if !state.again { state.running = false }
            return state.again
        })
    }

    private func pass() async {
        guard !store.reports().isEmpty, await signedIn() else { return }
        do {
            try await filer.fileStored(in: store)
        } catch let error as GitHubError where error.status == 401 {
            await refused()
        } catch {
            // Kept, for the next launch.
        }
    }
}
