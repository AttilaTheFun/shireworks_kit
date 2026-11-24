// What Crashes needs from each platform, in one place: a crash recorder
// that writes the app's crash down as it happens and hands it over at the
// next launch, and the shared sign-in to file with.
//
// On Apple's systems the recorder is KSCrash (its Recording library, built
// from source; what Sentry's own SDK records with), on the device alone: it
// writes each crash as a JSON report in the app's caches, and sends nothing
// anywhere. Only the crash monitors are installed: Mach exceptions, signals,
// C++ exceptions and uncaught NSExceptions; no hang, watchdog, deadlock,
// zombie or memory-termination monitors. No KSCrash type leaves this file.
//
// Elsewhere (Linux, Isomer's hosts) there is no recorder, for now: Crashes
// does nothing there.
import Foundation
import GitHubAuth

#if canImport(KSCrashRecording)
import KSCrashRecording
#endif

enum Platform {
    /// Whether Crashes catches crashes here: where KSCrash is linked (iOS
    /// and macOS).
    static var isSupported: Bool {
        #if canImport(KSCrashRecording)
        return true
        #else
        return false
        #endif
    }

    /// Starts the recorder, its files in `folder`, then hands over each
    /// crash it has kept (the runs' before), oldest first, as its report's
    /// JSON (`CrashRecording`): one that `handled` says was dealt with (kept,
    /// or no crash) is deleted from the recorder's store; the rest stay
    /// there for the next launch. Whether the recorder runs.
    @MainActor
    static func startCrashRecorder(folder: URL, handled: ([String: Any]) -> Bool) -> Bool {
        #if canImport(KSCrashRecording)
        let configuration = KSCrashConfiguration()
        configuration.installPath = folder.path
        // Crashes, and nothing else.
        configuration.monitors = [.machException, .signal, .cppException, .nsException]
        configuration.enableHangReporting = false
        configuration.enableCPUExceptionReporting = false
        // Nothing of the app's memory or console in a report, and no
        // rebinding of `__cxa_throw` across the app's images.
        configuration.enableMemoryIntrospection = false
        configuration.addConsoleLogToReport = false
        configuration.printPreviousLogOnStartup = false
        configuration.enableQueueNameSearch = false
        configuration.enableSwapCxaThrow = false
        // Only the images the backtraces name.
        configuration.enableCompactBinaryImages = true
        configuration.reportStoreConfiguration.reportCleanupPolicy = .never
        do {
            try KSCrash.shared.install(with: configuration)
        } catch {
            return false
        }
        guard let store = KSCrash.shared.reportStore else { return true }
        for id in store.reportIDs.map(\.int64Value).sorted() {
            guard let report = store.report(for: id) else {
                store.deleteReport(with: id)
                continue
            }
            if handled(report.value) { store.deleteReport(with: id) }
        }
        return true
        #else
        return false
        #endif
    }

    /// The shared sign-in to file with; nil where the build carries none or
    /// can't reach its lock. It never signs in by code: signing in happens in
    /// the app that owns the shared sign-in.
    @MainActor
    static func sharedSignIn(_ shared: GitHubSharedSignIn?) -> GitHubCredentials? {
        #if canImport(Security) && canImport(Darwin)
        guard let shared, let lock = shared.lock else { return nil }
        return GitHubCredentials(clientID: shared.clientID, store: shared.store, canSignInByCode: false, renewalLock: lock)
        #else
        return nil
        #endif
    }

    /// Where the recorder keeps its files: the app's own caches folder.
    static func recorderFolder(name: String) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("ShireworksCrashes", isDirectory: true).appendingPathComponent(name, isDirectory: true)
    }

    /// The app's executable's name: its frames are the app's own.
    static var executableName: String {
        Bundle.main.executableURL?.lastPathComponent ?? ProcessInfo.processInfo.processName
    }
}
