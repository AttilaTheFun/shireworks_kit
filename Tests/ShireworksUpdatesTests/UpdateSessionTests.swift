import Foundation
import Testing
import ShireworksUpdates

/// What AppUpdates sets going, with a fake system
/// (UpdateSession): the check, how an update installs (the update handler as
/// it is when asked, else the platform's way), and the offers' go ahead.
/// Portable: these run on Linux, where Apple's notifications aren't.
@MainActor
@Suite(.serialized)
final class UpdateSessionTests {
    private let temporary = TemporaryDatabase()
    private let visor = "com.example.Visor"
    private var registered: UpdateHandler?
    private var handled: [String] = []

    deinit { temporary.remove() }

    private func session(platform: UpdatePlatform = .macOS, system: FakeSystem = FakeSystem(),
                         running version: String = "0.39.2", offersInterval: Duration = .seconds(300)) -> UpdateSession {
        let store = AppGroupStore(fileURL: temporary.file, now: { Date(timeIntervalSince1970: 1_000) })
        return UpdateSession(store: store, app: InstalledApp(bundleID: visor, version: version, build: "1"),
                             signal: UpdateSignal(appGroup: "group.example." + UUID().uuidString), system: system,
                             platform: platform, handler: { [weak self] in self?.registered },
                             now: { Date(timeIntervalSince1970: 50) }, offersInterval: offersInterval)
    }

    /// Waits up to two seconds for the system to have been asked `event`.
    private func waitFor(_ event: String, on system: FakeSystem) async throws -> Bool {
        for _ in 0..<200 {
            if await system.events.contains(event) { return true }
            try await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private func newer(_ session: UpdateSession) async throws {
        try await session.store.setLatest([LatestBuild(bundleID: visor, version: "0.40.1", build: "1",
                                                       installURL: URL(string: "https://example.com/visor.zip"))])
    }

    private func handler() -> UpdateHandler {
        { [weak self] update in await MainActor.run { self?.handled.append(update.version) } }
    }

    @Test func aCheckWritesTheBuildAndFindsANewerOne() async throws {
        let session = session()
        try await newer(session)
        let found = try await session.check()
        guard case .available(let update) = found else { Issue.record("no update found: \(found)"); return }
        #expect(update.version == "0.40.1")
        #expect(try await session.store.record(bundleID: visor)?.installedVersion == "0.39.2")
    }

    @Test func withoutAHandlerAMacAsksApplicationsAndQuits() async throws {
        let system = FakeSystem()
        let session = session(system: system)
        try await newer(session)
        guard case .available(let update) = try await session.check() else { Issue.record("no update"); return }
        #expect(try await session.install(update) == .askedApplications)
        #expect(await system.events == ["changed", "open Applications", "terminate"])
        #expect(try await session.store.installRequests().map(\.version) == ["0.40.1"])
    }

    @Test func anIPhoneOpensTheInstallLink() async throws {
        let system = FakeSystem()
        let session = session(platform: .iOS, system: system)
        try await newer(session)
        guard case .available(let update) = try await session.check() else { Issue.record("no update"); return }
        #expect(try await session.install(update) == .openedInstallLink)
        #expect(await system.events == ["open https://example.com/visor.zip"])
    }

    @Test func aHandlerRegisteredAfterStartIsUsed() async throws {
        let system = FakeSystem()
        let session = session(system: system)
        try await newer(session)
        guard case .available(let update) = try await session.check() else { Issue.record("no update"); return }
        registered = handler()
        #expect(try await session.install(update) == .handled)
        #expect(handled == ["0.40.1"])
        #expect(await system.events.isEmpty, "the handler's way: Applications isn't asked")
    }

    @Test func throughApplicationsIgnoresTheHandler() async throws {
        let system = FakeSystem()
        let session = session(system: system)
        try await newer(session)
        guard case .available(let update) = try await session.check() else { Issue.record("no update"); return }
        registered = handler()
        #expect(try await session.installThroughApplications(update) == .askedApplications)
        #expect(handled.isEmpty)
        #expect(await system.events == ["changed", "open Applications", "terminate"])
    }

    @Test func goAheadUsesTheHandlerAsItIsThen() async throws {
        let system = FakeSystem()
        let session = session(system: system)
        try await newer(session)
        registered = handler()
        _ = try await session.store.makeOffer(bundleID: visor, version: "0.40.1", build: "1", offeredBy: "com.example.Applications")
        let watch = await session.answerOffers()
        defer { watch.cancel() }
        #expect(handled == ["0.40.1"], "no auto-update handler: go ahead, with the update handler registered")
        #expect(await system.events.contains("open Applications") == false)
    }

    @Test func goAheadWithoutAHandlerAsksApplications() async throws {
        let system = FakeSystem()
        let session = session(system: system)
        try await newer(session)
        _ = try await session.store.makeOffer(bundleID: visor, version: "0.40.1", build: "1", offeredBy: "com.example.Applications")
        let watch = await session.answerOffers()
        defer { watch.cancel() }
        #expect(await system.events.contains("open Applications"))
        #expect(await system.events.last == "terminate")
    }

    /// An offer made with no signal heard (one missed) is picked up by the
    /// periodic look.
    @Test func aMissedSignalIsMadeUpForByThePeriodicLook() async throws {
        let system = FakeSystem()
        let session = session(system: system, offersInterval: .milliseconds(20))
        let watch = await session.answerOffers()
        defer { watch.cancel() }
        #expect(await system.events.isEmpty)
        _ = try await session.store.makeOffer(bundleID: visor, version: "0.40.1", build: "1", offeredBy: "com.example.Applications")
        #expect(try await waitFor("sheet 0.40.1", on: system))
        #expect(try await waitFor("terminate", on: system), "Update Now: Applications asked, and the app quits")
    }

    /// And by the app's coming to the front, well before the next periodic look.
    @Test func anActivationLooksAgain() async throws {
        let system = FakeSystem()
        await system.setSheetAnswers([.later])
        let session = session(system: system, offersInterval: .seconds(3_600))
        let watch = await session.answerOffers()
        defer { watch.cancel() }
        _ = try await session.store.makeOffer(bundleID: visor, version: "0.40.1", build: "1", offeredBy: "com.example.Applications")
        #expect(await system.events.isEmpty)
        system.activate()
        #expect(try await waitFor("sheet 0.40.1", on: system))
        #expect(try await waitFor("changed", on: system))
        #expect(try await session.store.offer(bundleID: visor)?.state == .deferred, "Later")
    }

    /// A direct check of the app's releases writes the newer build it finds,
    /// which the session's check then sees; found again, nothing is written.
    @Test func aDirectCheckWritesANewerBuildOnce() async throws {
        let session = session(platform: .macOS)
        let line = """
            {"file": "Visor.zip", "bundleID": "\(visor)", "platform": "macos", "version": "0.40.2", "buildNumber": "1", "variant": "Production"}
            """
        let github = FakeGitHub(releases: [.init(asset: 4)], builds: [4: [line]])
        let checker = ReleaseChecker(repository: "owner/app", token: { "token" }, send: { await github.answer($0) })
        #expect(try await session.checkReleases(checker))
        guard case .available(let update) = try await session.check() else { Issue.record("no update"); return }
        #expect(update.version == "0.40.2")
        #expect(update.installURL == nil)
        #expect(try await session.checkReleases(checker) == false)
    }

    /// Applications' newer build stands: a direct check finding an older one
    /// writes nothing.
    @Test func aDirectCheckNeverLowersApplicationsBuild() async throws {
        let session = session(platform: .iOS)
        try await session.store.setLatest([LatestBuild(bundleID: visor, version: "0.41.0", build: "1",
                                                       installURL: URL(string: "itms-services://example"))])
        let line = """
            {"file": "Visor.ipa", "bundleID": "\(visor)", "platform": "ios", "version": "0.40.2", "buildNumber": "1", "variant": "Production"}
            """
        let github = FakeGitHub(releases: [.init(asset: 4)], builds: [4: [line]])
        let checker = ReleaseChecker(repository: "owner/app", token: { "token" }, send: { await github.answer($0) })
        #expect(try await session.checkReleases(checker) == false)
        #expect(try await session.store.record(bundleID: visor)?.latestVersion == "0.41.0")
    }
}
