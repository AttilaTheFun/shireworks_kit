#if canImport(Darwin)
import Foundation
import os
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Installing on Apple's systems: UIKit's or AppKit's opening of URLs and
/// apps, AppKit's quitting, the update sheet and the app's activations, and
/// the group's Darwin notification.
struct AppleUpdateSystem: UpdateSystem {
    let signal: UpdateSignal
    /// Applications on the Mac, production's before the beta's: whichever
    /// is installed is asked (both read the same database).
    let applicationsBundleIDs: [String]

    @MainActor
    func open(_ url: URL) async -> Bool {
        #if canImport(UIKit)
        return await UIApplication.shared.open(url)
        #elseif canImport(AppKit)
        return NSWorkspace.shared.open(url)
        #else
        return false
        #endif
    }

    @MainActor
    func openApplications() async throws {
        #if canImport(AppKit) && !canImport(UIKit)
        // Each step said (a go-ahead that ends here leaves nothing else behind: Nimbus 0.19.1, 2026-11-27).
        let log = Logger(subsystem: "UpdateKit", category: "install")
        guard let url = applicationsBundleIDs.lazy.compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }).first else {
            log.error("No app to install the update: none of \(applicationsBundleIDs.joined(separator: ", "), privacy: .public) found")
            throw UpdateInstallError.applicationsNotInstalled
        }
        log.notice("Asking \(url.path, privacy: .public) to install the update")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } catch {
            log.error("\(url.path, privacy: .public) couldn't be opened: \(String(describing: error), privacy: .public)")
            throw error
        }
        #else
        throw UpdateInstallError.applicationsNotInstalled
        #endif
    }

    @MainActor
    func terminate() async {
        #if canImport(AppKit) && !canImport(UIKit)
        // As Quit in the menu: the app's delegate may still finish its work.
        NSApplication.shared.terminate(nil)
        #endif
    }

    func databaseChanged() { signal.post() }

    /// The update sheet: an alert, as a sheet on the app's key (or main)
    /// window when it has one free, else a modal alert of its own (a
    /// windowless app, a menu-bar app). Shown to a regular app only while it
    /// is in front, so it never comes up behind another app's window or
    /// takes the front; an accessory app (a menu-bar app, seldom in front) is
    /// brought forward for it. Not while another modal window is up.
    /// Elsewhere (iOS, where offers aren't answered) nothing is shown.
    @MainActor
    func showUpdateSheet(_ offer: UpdateOffer) async -> UpdateSheetAnswer? {
        #if canImport(AppKit) && !canImport(UIKit)
        let application = NSApplication.shared
        guard application.modalWindow == nil else { return nil }
        if application.activationPolicy() == .regular {
            guard application.isActive else { return nil }
        } else {
            application.activate()
        }
        let name = Self.appName
        let alert = NSAlert()
        alert.messageText = "\(name) \(offer.version) is ready"
        alert.informativeText = "Updating quits \(name); Shireworks installs it and opens it again."
        alert.addButton(withTitle: "Update Now")
        alert.addButton(withTitle: "Later")
        let response: NSApplication.ModalResponse
        if let window = application.keyWindow ?? application.mainWindow, window.isVisible, window.attachedSheet == nil {
            response = await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            }
        } else {
            response = alert.runModal()
        }
        return response == .alertFirstButtonReturn ? .updateNow : .later
        #else
        return nil
        #endif
    }

    /// AppKit's did-become-active, on a Mac; elsewhere, none.
    func activations() -> AsyncStream<Void> {
        #if canImport(AppKit) && !canImport(UIKit)
        AsyncStream { continuation in
            let observer = Observer(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                                                           queue: nil) { _ in continuation.yield() })
            continuation.onTermination = { _ in NotificationCenter.default.removeObserver(observer.token) }
        }
        #else
        AsyncStream { $0.finish() }
        #endif
    }

    #if canImport(AppKit) && !canImport(UIKit)
    /// The app's name as the Finder shows it.
    private static var appName: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? ProcessInfo.processInfo.processName
    }
    #endif
}

#if canImport(AppKit) && !canImport(UIKit)
/// A notification observer's token, held by the stream until it ends.
private final class Observer: @unchecked Sendable {
    let token: any NSObjectProtocol

    init(_ token: any NSObjectProtocol) {
        self.token = token
    }
}
#endif
#endif
