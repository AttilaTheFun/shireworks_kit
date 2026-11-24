import Foundation

/// An app's side of updating automatically on a Mac (docs/Updates.md):
/// answers Applications' offer of its newest build with its handler, or,
/// when it has none, the update sheet's answer (Update Now or Later, asked
/// again an hour after Later); carries the answer out; and at each launch
/// settles what came of an offer it was installing. `AppUpdates` runs one;
/// tests run one with a fake system.
@MainActor
public final class OfferResponder {
    public let store: AppGroupStore
    /// The app running.
    public let app: InstalledApp
    /// Asks Applications to install and quits the app (go ahead).
    public let installer: UpdateInstaller
    public let system: any UpdateSystem
    /// The handler of offers as it is when one comes: none, the update sheet.
    let handler: @MainActor () -> AutoUpdateHandler?
    let installHook: AutoUpdateInstaller?
    /// When it is, for asking again after Later.
    let now: @Sendable () -> Date
    /// How long after Later the update sheet asks again.
    let askAgainAfter: TimeInterval
    /// Whether the app, installing itself, takes its build as its zip.
    let installsFromZip: Bool
    /// The offer being answered or installed, so a signal heard meanwhile
    /// doesn't ask the handler twice.
    private var busy: Set<String> = []
    /// The offers (version and build) whose install hook this process has
    /// called: once each, however long the app waits before installing.
    private var hooked: Set<String> = []

    public convenience init(store: AppGroupStore, app: InstalledApp, installer: UpdateInstaller, system: any UpdateSystem,
                            handler: AutoUpdateHandler?, installHook: AutoUpdateInstaller?, installsFromZip: Bool,
                            now: @escaping @Sendable () -> Date = { Date() }, askAgainAfter: TimeInterval = 3_600) {
        self.init(store: store, app: app, installer: installer, system: system, autoUpdate: { handler }, installHook: installHook,
                  installsFromZip: installsFromZip, now: now, askAgainAfter: askAgainAfter)
    }

    /// One that looks its handler of offers up as each offer comes
    /// (`autoUpdate`): one registered after start is asked all the same.
    public init(store: AppGroupStore, app: InstalledApp, installer: UpdateInstaller, system: any UpdateSystem,
                autoUpdate: @escaping @MainActor () -> AutoUpdateHandler?, installHook: AutoUpdateInstaller?, installsFromZip: Bool,
                now: @escaping @Sendable () -> Date = { Date() }, askAgainAfter: TimeInterval = 3_600) {
        self.store = store
        self.app = app
        self.installer = installer
        self.system = system
        self.handler = autoUpdate
        self.installHook = installHook
        self.installsFromZip = installsFromZip
        self.now = now
        self.askAgainAfter = askAgainAfter
    }

    /// What an offer asks of the app now.
    enum Action: Equatable {
        /// Nothing: answered already, under way, or Later less than
        /// `askAgainAfter` ago.
        case none
        /// The app's handler decides.
        case askHandler
        /// The update sheet asks.
        case showSheet
    }

    /// What an offer asks of the app now: a new one, its handler's answer,
    /// else the update sheet's; a deferred one, with no handler (the sheet's
    /// Later), the sheet again once `askAgainAfter` has passed since (either
    /// way, for a clock that moved). A handler's deferral waits for
    /// `readyToUpdate()`. A newer build, or a person's asking again, is a new
    /// offer, so it asks at once.
    static func action(for offer: UpdateOffer, hasHandler: Bool, now: Date, askAgainAfter: TimeInterval) -> Action {
        switch offer.state {
        case .offered:
            return hasHandler ? .askHandler : .showSheet
        case .deferred where !hasHandler:
            return abs(now.timeIntervalSince(offer.updatedAt)) >= askAgainAfter ? .showSheet : .none
        default:
            return .none
        }
    }

    /// At launch: says this app answers offers, settles one it was
    /// installing (by the version running now, as the process that started
    /// an install may not be the one that finds out how it went), then
    /// looks at the offer as it stands.
    public func launched() async throws {
        try await store.recordAnswersOffers(bundleID: app.bundleID, installsFromZip: installsFromZip)
        if let offer = try await store.offer(bundleID: app.bundleID) {
            try await settle(offer)
        }
        try await look()
    }

    /// Looks at the app's offer and acts on it: answers a new one (or one
    /// deferred by the update sheet's Later, an hour on), calls the install
    /// hook with one handed over. At launch, on each signal, every few
    /// minutes and at each activation (`UpdateSession.answerOffers`).
    public func look() async throws {
        guard let offer = try await store.offer(bundleID: app.bundleID), !busy.contains(Self.key(offer)) else { return }
        busy.insert(Self.key(offer))
        defer { busy.remove(Self.key(offer)) }
        switch offer.state {
        case .offered, .deferred:
            // One of a build that isn't newer than this one is no offer.
            guard app.appVersion < offer.appVersion else {
                try await store.moveOffer(bundleID: offer.bundleID, version: offer.version, build: offer.build, from: [offer.state],
                                          to: .installed)
                await system.databaseChanged()
                return
            }
            let handler = handler()
            let decision: UpdateDecision
            switch Self.action(for: offer, hasHandler: handler != nil, now: now(), askAgainAfter: askAgainAfter) {
            case .none:
                return
            case .askHandler:
                guard let handler else { return }
                decision = await handler(offer)
            case .showSheet:
                // Not shown now (the app isn't in front): the next look asks.
                guard let answer = await system.showUpdateSheet(offer) else { return }
                decision = answer == .updateNow ? .goAhead : .deferUntilReady
            }
            guard try await store.moveOffer(bundleID: offer.bundleID, version: offer.version, build: offer.build, from: [offer.state],
                                            to: decision.state, note: decision.note) else { return }
            await system.databaseChanged()
            if decision == .goAhead { try await goAhead(offer) }
        case .handedOver:
            guard let installHook, hooked.insert("\(offer.version) \(offer.build ?? "")").inserted else { return }
            await installHook(offer)
        default:
            return
        }
    }

    /// After deferring: the app is ready, so it goes ahead now. Nothing
    /// when there's no deferred offer.
    public func readyToUpdate() async throws {
        guard let offer = try await store.offer(bundleID: app.bundleID),
              try await store.moveOffer(bundleID: offer.bundleID, version: offer.version, build: offer.build, from: [.deferred],
                                        to: .goAhead) else { return }
        await system.databaseChanged()
        try await goAhead(offer)
    }

    /// The app is installing the bundle it was handed (just before it
    /// relaunches): its next launch says how that went.
    public func installing() async throws {
        guard let offer = try await store.offer(bundleID: app.bundleID),
              try await store.moveOffer(bundleID: offer.bundleID, version: offer.version, build: offer.build,
                                        from: [.handedOver], to: .installing, bundle: offer.bundle,
                                        bundleSHA256: offer.bundleSHA256, bundleName: offer.bundleName) else { return }
        await system.databaseChanged()
    }

    /// The app's own install failed (it refused the bundle, or its new build
    /// didn't stay up and the old one is back), saying why.
    public func installFailed(_ note: String) async throws {
        guard let offer = try await store.offer(bundleID: app.bundleID),
              try await store.moveOffer(bundleID: offer.bundleID, version: offer.version, build: offer.build,
                                        from: [.installMyself, .handedOver, .installing, .installed, .failed], to: .failed, note: note,
                                        bundle: offer.bundle, bundleSHA256: offer.bundleSHA256, bundleName: offer.bundleName) else { return }
        await system.databaseChanged()
    }

    // MARK: Inside

    /// What a launch says of an offer under way: the build running is the
    /// one offered (or newer), so it's installed; after the app's own
    /// install the older one is running, so it failed. That's so even once
    /// it was installed: an app that installs itself (its offer had a
    /// bundle) may put the old build back after the new one started (Visor's
    /// relauncher, within two minutes).
    func settle(_ offer: UpdateOffer) async throws {
        if offer.state == .installed, offer.bundle != nil, app.appVersion < offer.appVersion {
            try await store.moveOffer(bundleID: offer.bundleID, version: offer.version, build: offer.build, from: [.installed],
                                      to: .failed, note: "\(app.appVersion) is running again after \(offer.appVersion) was installed",
                                      bundle: offer.bundle, bundleSHA256: offer.bundleSHA256, bundleName: offer.bundleName)
            await system.databaseChanged()
            return
        }
        let states: Set<UpdateOffer.State> = [.goAhead, .handedOver, .installing]
        guard states.contains(offer.state) else { return }
        if app.appVersion >= offer.appVersion {
            try await store.moveOffer(bundleID: offer.bundleID, version: offer.version, build: offer.build, from: states, to: .installed,
                                      bundle: offer.bundle, bundleSHA256: offer.bundleSHA256, bundleName: offer.bundleName)
        } else if offer.state == .installing {
            try await store.moveOffer(bundleID: offer.bundleID, version: offer.version, build: offer.build, from: [.installing],
                                      to: .failed, note: "\(app.appVersion) is still running after installing \(offer.appVersion)",
                                      bundle: offer.bundle, bundleSHA256: offer.bundleSHA256, bundleName: offer.bundleName)
        } else {
            return
        }
        await system.databaseChanged()
    }

    /// Go ahead: Applications asked to install the build, and the app quits
    /// at once (`UpdateInstaller`, as the banner's Install).
    private func goAhead(_ offer: UpdateOffer) async throws {
        _ = try await installer.install(AvailableUpdate(bundleID: offer.bundleID, version: offer.version, build: offer.build,
                                                        installURL: nil, installedVersion: app.version, installedBuild: app.build))
    }

    private static func key(_ offer: UpdateOffer) -> String { "\(offer.version) \(offer.build ?? "") \(offer.state.rawValue)" }
}
