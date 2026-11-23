// What ShakeKit needs from each platform, in one place: the sign-in's
// store, the shake, a screenshot of the app's own key window, its logs, and
// the device model.
// Elsewhere (Linux, Isomer's hosts) each has nothing to give, for now.
import Foundation
import GitHubAuth

#if canImport(OSLog)
import OSLog
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum Platform {
    /// The sign-in to file with, and whether it's the shared one: the apps'
    /// shared sign-in when the host has one, holding a token that covers the
    /// scope; otherwise ShakeKit's own, in the app's own keychain. ShakeKit
    /// never signs in to the shared one itself: asking for a narrower scope
    /// would replace the token every other app relies on.
    @MainActor
    static func credentials(configuration: ShakeKitConfiguration, shared: GitHubSharedSignIn?) -> (GitHubCredentials, Bool) {
        #if canImport(Security)
        if let shared, let lock = shared.lock,
           let token = shared.store.token(for: shared.clientID), token.covers(configuration.scope) {
            let credentials = GitHubCredentials(
                clientID: shared.clientID, store: shared.store, canSignInByCode: false, renewalLock: lock)
            return (credentials, true)
        }
        let store: TokenStore = KeychainTokenStore(service: configuration.keychainService)
        #else
        let store: TokenStore = MemoryTokenStore()
        #endif
        return (GitHubCredentials(clientID: configuration.clientID, scope: configuration.scope, store: store), false)
    }

    /// The current process's log lines from `since`, from `subsystems`
    /// (each a prefix), oldest first: "12:00:00.123 [category] message".
    static func logLines(since: Date, subsystems: [String]) -> [String] {
        #if canImport(OSLog)
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier),
              let entries = try? store.getEntries(at: store.position(date: since)) else { return [] }
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

    /// A PNG of the app's key window as it is now, before anything is
    /// presented over it; nil with none.
    @MainActor
    static func keyWindowPNG() -> Data? {
        #if canImport(UIKit)
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.pngData { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        #elseif canImport(AppKit)
        guard let view = NSApp.keyWindow?.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
        #else
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

#if canImport(UIKit)
extension UIWindow {
    /// A shake anywhere in the app asks for a report.
    override open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: ShakeReport.requested, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}
#endif
