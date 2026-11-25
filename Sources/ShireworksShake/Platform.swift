// What ShakeKit needs from each platform, in one place: the sign-in's
// store, the shake, a screenshot of the app's own key window, its logs, and
// the device model.
// Isomer's hosts (Android: SwiftUI without UIKit or AppKit) have the
// report's views and a Report a Bug request, but no shake, screenshot, log
// store or keychain yet: each is marked below where Isomer's slots in.
// Linux has none of the views.
import Foundation
import GitHubAuth

#if canImport(OSLog) && canImport(Darwin)
// Apple's, with its store; Isomer's OSLog has the Logger alone.
import OSLog
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
#if canImport(ImageIO) && (canImport(UIKit) || canImport(AppKit))
import ImageIO
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif

enum Platform {
    /// Whether ShakeKit offers reports here, given the shared sign-in the
    /// build carries (`shared`): on Apple's systems, where it carries one; on
    /// Isomer's hosts, always, as there's no shared sign-in there yet (no
    /// keychain): a report is filed with the sign-in the host gives
    /// `.shakeToReport(credentials:)`, and a request without one says how to
    /// sign in. Elsewhere (Linux, with no views), never.
    static func offersReports(shared: GitHubSharedSignIn?) -> Bool {
        #if canImport(UIKit) || canImport(AppKit)
        return shared != nil
        #elseif canImport(SwiftUI)
        return true
        #else
        return false
        #endif
    }

    /// The shared sign-in to file with, and whether its token reaches
    /// `scope` now; nil where the build carries none or can't reach its lock.
    /// It never signs in by code: signing in happens in the app that owns the
    /// shared sign-in, and signing out too.
    @MainActor
    static func sharedSignIn(_ shared: GitHubSharedSignIn?, scope: String)
        -> (credentials: GitHubCredentials, reaches: @MainActor () -> Bool)? {
        #if canImport(Security) && (canImport(UIKit) || canImport(AppKit))
        guard let shared, let lock = shared.lock else { return nil }
        let credentials = GitHubCredentials(
            clientID: shared.clientID, store: shared.store, canSignInByCode: false, renewalLock: lock)
        let store = shared.store, clientID = shared.clientID
        return (credentials, { store.token(for: clientID)?.covers(scope) ?? false })
        #else
        return nil
        #endif
    }

    /// Whether the app's logs are read here: on Apple's systems, from
    /// `OSLogStore`. Isomer's OSLog has no store to read.
    static var readsLogs: Bool {
        #if canImport(OSLog) && canImport(Darwin)
        return true
        #else
        return false
        #endif
    }

    /// The current process's log lines from `since`, from `subsystems`
    /// (each a prefix), oldest first: "12:00:00.123 [category] message".
    /// It takes most of a second or more (the store is read through, from
    /// `since`), so never on the main actor. The subsystems are the store's
    /// to match (a predicate): every entry of the process read and filtered
    /// here instead, every framework's too, took 2 to 3 seconds for 3,000
    /// lines among 23,000, against 0.8 matched by the store.
    static func logLines(since: Date, subsystems: [String]) -> [String] {
        #if canImport(OSLog) && canImport(Darwin)
        guard !subsystems.isEmpty else { return [] }
        let matching = NSCompoundPredicate(orPredicateWithSubpredicates: subsystems.map {
            NSPredicate(format: "subsystem BEGINSWITH %@", $0)
        })
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier),
              let entries = try? store.getEntries(at: store.position(date: since), matching: matching) else { return [] }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return entries.compactMap { $0 as? OSLogEntryLog }
            .filter { entry in subsystems.contains { entry.subsystem.hasPrefix($0) } }
            .map { "\(formatter.string(from: $0.date)) [\($0.category)] \($0.composedMessage)" }
        #else
        return []
        #endif
    }

    /// The app's key window as it is now, before anything is presented over
    /// it, and what makes its PNG: the image is taken here, on the main
    /// actor; the PNG (the slower part) is made by what's returned, anywhere.
    /// Nil with no key window.
    @MainActor
    static func keyWindowCapture() -> (@Sendable () -> Data?)? {
        #if canImport(UIKit)
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) else { return nil }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        guard let captured = image.cgImage.map(CapturedImage.init) else { return nil }
        return { captured.png() }
        #elseif canImport(AppKit)
        guard let view = NSApp.keyWindow?.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let captured = bitmap.cgImage.map(CapturedImage.init) else { return nil }
        return { captured.png() }
        #else
        // Isomer's hosts: `IsomerScreenshot.capture()`'s PNG here, once Isomer has it.
        return nil
        #endif
    }

    /// The hardware model ("iPhone17,1", "Mac16,10").
    static var deviceModel: String {
        #if os(macOS)
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "Mac" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "Mac" }
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        #elseif canImport(UIKit)
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated + " (Simulator)"
        }
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        #else
        return "unknown"
        #endif
    }
}

#if canImport(ImageIO) && (canImport(UIKit) || canImport(AppKit))
/// A screenshot's pixels, taken on the main actor and made a PNG elsewhere
/// (ImageIO's, which any thread may use). Nothing changes the image once
/// it's taken.
struct CapturedImage: @unchecked Sendable {
    let image: CGImage

    func png() -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
#endif

#if canImport(SwiftUI)
extension View {
    /// Shakes posted as requests (`ShakeReport.requested`, `Trigger.shake`).
    /// On iOS the `UIWindow` override below posts them, for every window,
    /// so the view has nothing to add; on Isomer's hosts, Isomer's
    /// `.onShake` will, once it has one:
    /// `onShake { NotificationCenter.default.post(name: ShakeReport.requested, object: ShakeReport.Trigger.shake) }`.
    func postingShakes() -> some View {
        self
    }

    /// `report.shakesPaused` kept as the views below ask
    /// (`.shakeToReportPaused`), through SwiftUI's preferences on Apple's
    /// systems. Isomer has no preferences yet, nor a shake to pause.
    func followingShakePauses(_ report: ShakeReport) -> some View {
        #if canImport(UIKit) || canImport(AppKit)
        onPreferenceChange(ShakesPausedKey.self) { paused in
            report.shakesPaused = paused
        }
        #else
        self
        #endif
    }

    /// Shakes asked to be ignored while `paused` (`.shakeToReportPaused`).
    func askingShakesPaused(_ paused: Bool) -> some View {
        #if canImport(UIKit) || canImport(AppKit)
        preference(key: ShakesPausedKey.self, value: paused)
        #else
        self
        #endif
    }
}

#if canImport(UIKit) || canImport(AppKit)
/// Whether any view below asks for shakes to be ignored.
struct ShakesPausedKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}
#endif
#endif

#if canImport(UIKit)
extension UIWindow {
    /// A shake anywhere in the app asks for a report.
    override open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: ShakeReport.requested, object: ShakeReport.Trigger.shake)
        }
        super.motionEnded(motion, with: event)
    }
}
#endif
