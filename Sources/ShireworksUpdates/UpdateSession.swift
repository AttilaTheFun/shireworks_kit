import Foundation

/// What `AppUpdates.start` sets going, apart from Apple's system: the
/// database, the signal, the check (the build written), and (on a Mac) the
/// answering of offers, and how an update installs: the update handler as
/// it is when asked, else the platform's way. Portable, so its wiring is
/// tested on Linux with a fake system; `AppUpdates` makes one with Apple's.
@MainActor
public final class UpdateSession {
    public let store: AppGroupStore
    public let app: InstalledApp
    public let signal: UpdateSignal
    public let checker: UpdateChecker
    public let system: any UpdateSystem
    public let platform: UpdatePlatform
    /// The update handler, looked up each time one is needed: a handler
    /// registered after start is used all the same.
    private let handler: @MainActor () -> UpdateHandler?
    private let autoUpdate: @MainActor () -> AutoUpdateHandler?
    private let installHook: @MainActor () -> AutoUpdateInstaller?
    private let now: @Sendable () -> Date
    /// How often the offers are looked at besides the signal and the app's
    /// activations, in case a signal was missed.
    private let offersInterval: Duration
    /// The offers' answerer, once `answerOffers` has made it (a Mac's).
    public private(set) var responder: OfferResponder?

    public init(store: AppGroupStore, app: InstalledApp, signal: UpdateSignal, system: any UpdateSystem,
                platform: UpdatePlatform = .current,
                handler: @escaping @MainActor () -> UpdateHandler? = { nil },
                autoUpdate: @escaping @MainActor () -> AutoUpdateHandler? = { nil },
                installHook: @escaping @MainActor () -> AutoUpdateInstaller? = { nil },
                now: @escaping @Sendable () -> Date = { Date() }, offersInterval: Duration = .seconds(300)) {
        self.store = store
        self.app = app
        self.signal = signal
        self.system = system
        self.platform = platform
        self.handler = handler
        self.autoUpdate = autoUpdate
        self.installHook = installHook
        self.now = now
        self.offersInterval = offersInterval
        checker = UpdateChecker(store: store, app: app)
    }

    /// The app's build written, and what Applications knows of a newer one.
    public func check() async throws -> UpdateCheck {
        try await checker.check()
    }

    /// The app's own releases checked (`ReleaseChecker`, learn only): a
    /// newer build found is written to the database where the row knows of
    /// none as new (`AppGroupStore.offerLatest`), and then, as after an
    /// Applications sync, the group is told (the app's own offers looked at
    /// again, Applications' tab) and the check runs again. Whether it was
    /// written.
    @discardableResult
    public func checkReleases(_ checker: ReleaseChecker) async throws -> Bool {
        guard let latest = try await checker.check(app: app, platform: platform.releasePlatform),
              try await store.offerLatest(latest) else { return false }
        signal.post()
        _ = try await check()
        return true
    }

    /// Installs an update: the update handler's way, if one is registered,
    /// else the platform's (`UpdateInstaller`).
    @discardableResult
    public func install(_ update: AvailableUpdate) async throws -> InstallOutcome {
        try await installer(handler: handler()).install(update)
    }

    /// Installs an update the platform's way, whatever handler is
    /// registered: on a Mac, Applications asked and the app quit.
    @discardableResult
    public func installThroughApplications(_ update: AvailableUpdate) async throws -> InstallOutcome {
        try await installer(handler: nil).install(update)
    }

    /// A Mac's: the offers answered, now (at launch: an install this app
    /// started is settled first), each time the group's signal comes, each
    /// time the app becomes active, and every `offersInterval` (five
    /// minutes) in case a signal was missed. The handler of offers as it is
    /// then decides, else the update sheet. Go ahead installs with the
    /// update handler as it is then, else through Applications. Returns the
    /// task that watches; cancelling it stops all three.
    @discardableResult
    public func answerOffers(failed: @escaping @Sendable (String) -> Void = { _ in }) async -> Task<Void, Never> {
        let goAhead = installer(handler: { [weak self] update in
            // The handler as it is when go ahead comes, else the Mac's way.
            guard let self else { throw UpdateInstallError.notStarted }
            if let registered = await MainActor.run(body: { self.handler() }) {
                try await registered(update)
            } else {
                _ = try await self.installThroughApplications(update)
            }
        })
        let responder = OfferResponder(store: store, app: app, installer: goAhead, system: system,
                                       autoUpdate: { [weak self] in self?.autoUpdate() },
                                       installHook: { [weak self] offer in await self?.installHook()?(offer) },
                                       installsFromZip: UpdateKitInfo.mainInstallsFromZip, now: now)
        self.responder = responder
        do { try await responder.launched() } catch { failed("The offer was not looked at: \(error)") }
        let signal = self.signal, activations = system.activations(), interval = offersInterval
        let look: @MainActor @Sendable () async -> Void = {
            do { try await responder.look() } catch { failed("The offer was not looked at: \(error)") }
        }
        let watches = [
            Task { @MainActor in for await _ in signal.changes() { await look() } },
            Task { @MainActor in for await _ in activations { await look() } },
            Task { @MainActor in while (try? await Task.sleep(for: interval)) != nil { await look() } },
        ]
        return Task {
            await withTaskCancellationHandler {
                for watch in watches { await watch.value }
            } onCancel: {
                for watch in watches { watch.cancel() }
            }
        }
    }

    private func installer(handler: UpdateHandler?) -> UpdateInstaller {
        UpdateInstaller(store: store, system: system, platform: platform, handler: handler, requester: app.bundleID, now: now)
    }
}
