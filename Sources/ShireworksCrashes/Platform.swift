// What Crashes needs from each platform, in one place: a crash reporter
// that catches the app's crash and hands it over at the next launch, and
// the shared sign-in to file with.
//
// On Apple's systems the crash reporter is Sentry's SDK (sentry-cocoa),
// used on the device alone: started with a DSN that names no Sentry project
// (a placeholder at a host that doesn't exist), everything but its crash
// handler turned off, and every event it would send dropped in
// `beforeSend`, a crash's first handed over as its JSON. Nothing reaches
// Sentry; there is no Sentry account. No Sentry type leaves this file.
//
// Elsewhere (Linux, Isomer's hosts) there is no crash reporter, for now:
// Crashes does nothing there.
import Foundation
import GitHubAuth

#if canImport(SentryObjCInternal)
import SentryObjCInternal
import SentrySwift
#endif

enum Platform {
    /// Whether Crashes catches crashes here: where Sentry's SDK is linked
    /// (iOS and macOS).
    static var isSupported: Bool {
        #if canImport(SentryObjCInternal)
        return true
        #else
        return false
        #endif
    }

    /// A DSN of no Sentry project: the SDK runs with it, and sends nothing,
    /// as `beforeSend` drops every event anyway.
    static let placeholderDSN = "https://00000000000000000000000000000000@o0.ingest.invalid/0"

    /// Starts the crash reporter, keeping its files in `cache`. `caught` is
    /// given each crash as its event's JSON (`CrashEvent`): the last run's
    /// at the start, as the SDK reads it. Whether it started.
    @MainActor
    static func startCrashReporter(cache: URL, caught: @escaping @Sendable ([String: Any]) -> Void) -> Bool {
        #if canImport(SentryObjCInternal)
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        SentrySDK.start { options in
            options.dsn = placeholderDSN
            options.cacheDirectoryPath = cache.path
            // The app's own frames: its executable's (Sentry's SDK takes it
            // from the Info.plist, which a bare executable has none of).
            options.add(inAppInclude: ProcessInfo.processInfo.processName)
            // Crashes, and nothing else.
            options.enableCrashHandler = true
            options.enableAppHangTracking = false
            options.enableWatchdogTerminationTracking = false
            options.enableAutoSessionTracking = false
            options.tracesSampleRate = 0
            options.enableAutoPerformanceTracing = false
            options.enableNetworkTracking = false
            options.enableNetworkBreadcrumbs = false
            options.enableCaptureFailedRequests = false
            options.enableFileIOTracing = false
            options.enableCoreDataTracing = false
            options.enableSwizzling = false
            options.enableMetricKit = false
            options.enableMetrics = false
            options.enableLogs = false
            options.sendClientReports = false
            options.sendDefaultPii = false
            #if os(iOS)
            options.enableUIViewControllerTracing = false
            options.enableUserInteractionTracing = false
            options.enablePreWarmedAppStartTracing = false
            options.attachScreenshot = false
            options.attachViewHierarchy = false
            options.sessionReplay.sessionSampleRate = 0
            options.sessionReplay.onErrorSampleRate = 0
            #endif
            // Every event dropped; a crash's handed over first.
            options.beforeSend = { event in
                if event.level == .fatal { caught(event.serialize()) }
                return nil
            }
        }
        return SentrySDK.isEnabled
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

    /// Where the crash reporter keeps its files: the app's own caches folder.
    static func cacheFolder(name: String) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("ShireworksCrashes", isDirectory: true).appendingPathComponent(name, isDirectory: true)
    }
}
