@testable import ShireworksUpdates
import Foundation
import XCTest

/// The update sheet (docs/Updates.md, "Updating automatically"): what an
/// offer asks of an app with no handler of offers, Later asked again an
/// hour on, and the offers a person asks for.
@MainActor
final class UpdateSheetTests: XCTestCase {
    private let temporary = TemporaryDatabase()
    private let visor = "com.example.Visor"
    private let hour: TimeInterval = 3_600

    override func tearDown() {
        temporary.remove()
        super.tearDown()
    }

    /// The store's clock, which stamps an offer's moves (Later's time).
    private func store() -> AppGroupStore {
        AppGroupStore(fileURL: temporary.file, now: { Date(timeIntervalSince1970: 1_000) })
    }

    private func responder(_ store: AppGroupStore, system: FakeSystem, clock: TestClock,
                           handler: AutoUpdateHandler? = nil) -> OfferResponder {
        let installer = UpdateInstaller(store: store, system: system, platform: .macOS, handler: nil, requester: visor)
        return OfferResponder(store: store, app: InstalledApp(bundleID: visor, version: "0.39.2", build: "1"), installer: installer,
                              system: system, handler: handler, installHook: nil, installsFromZip: false, now: { clock.now })
    }

    private func offer(_ state: UpdateOffer.State, updatedAt: TimeInterval = 1_000) -> UpdateOffer {
        UpdateOffer(bundleID: visor, version: "0.40.1", build: "1", state: state, offeredBy: "com.example.Applications",
                    offeredAt: Date(timeIntervalSince1970: 1_000), updatedAt: Date(timeIntervalSince1970: updatedAt))
    }

    // MARK: The decision

    func testANewOfferAsksTheHandlerElseTheSheet() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(OfferResponder.action(for: offer(.offered), hasHandler: true, now: now, askAgainAfter: hour), .askHandler)
        XCTAssertEqual(OfferResponder.action(for: offer(.offered), hasHandler: false, now: now, askAgainAfter: hour), .showSheet)
    }

    func testLaterIsAskedAgainOnlyAnHourOn() {
        let later = offer(.deferred, updatedAt: 1_000)
        func action(at time: TimeInterval, hasHandler: Bool = false) -> OfferResponder.Action {
            OfferResponder.action(for: later, hasHandler: hasHandler, now: Date(timeIntervalSince1970: time), askAgainAfter: hour)
        }
        XCTAssertEqual(action(at: 1_000), .none)
        XCTAssertEqual(action(at: 1_000 + hour - 1), .none, "not on every check")
        XCTAssertEqual(action(at: 1_000 + hour), .showSheet)
        XCTAssertEqual(action(at: 1_000 - hour - 1), .showSheet, "a clock moved back an hour asks too")
        XCTAssertEqual(action(at: 1_000 + 2 * hour, hasHandler: true), .none, "a handler's deferral waits for readyToUpdate()")
    }

    func testAnOfferUnderWayOrDoneAsksNothing() {
        let now = Date(timeIntervalSince1970: 1_000 + 10 * hour)
        for state in UpdateOffer.State.allCases where ![.offered, .deferred].contains(state) {
            for hasHandler in [false, true] {
                XCTAssertEqual(OfferResponder.action(for: offer(state), hasHandler: hasHandler, now: now, askAgainAfter: hour), .none,
                               "\(state)")
            }
        }
    }

    // MARK: The app answering

    func testLaterDefersAndTheSheetAsksAgainAnHourOn() async throws {
        let store = store(), system = FakeSystem(), clock = TestClock(1_000)
        await system.setSheetAnswers([.later, .updateNow])
        _ = try await store.makeOffer(bundleID: visor, version: "0.40.1", build: "1", offeredBy: "com.example.Applications")
        let responder = responder(store, system: system, clock: clock)
        try await responder.launched()
        var offer = try await store.offer(bundleID: visor)
        XCTAssertEqual(offer?.state, .deferred)
        clock.now = Date(timeIntervalSince1970: 1_000 + 30 * 60)
        try await responder.look()
        var events = await system.events
        XCTAssertEqual(events.filter { $0.hasPrefix("sheet") }, ["sheet 0.40.1"], "not asked again within the hour")
        clock.now = Date(timeIntervalSince1970: 1_000 + hour)
        try await responder.look()
        offer = try await store.offer(bundleID: visor)
        XCTAssertEqual(offer?.state, .goAhead)
        events = await system.events
        XCTAssertEqual(events.filter { $0.hasPrefix("sheet") }.count, 2)
        XCTAssertEqual(events.suffix(2), ["open Applications", "terminate"])
    }

    /// The app isn't in front: the sheet isn't shown, and the offer waits
    /// for the next look (an activation, the next check).
    func testASheetNotShownLeavesTheOfferForTheNextLook() async throws {
        let store = store(), system = FakeSystem(), clock = TestClock(1_000)
        await system.setSheetAnswers([nil])
        _ = try await store.makeOffer(bundleID: visor, version: "0.40.1", build: "1", offeredBy: "com.example.Applications")
        let responder = responder(store, system: system, clock: clock)
        try await responder.launched()
        var offer = try await store.offer(bundleID: visor)
        XCTAssertEqual(offer?.state, .offered)
        var events = await system.events
        XCTAssertEqual(events, ["sheet 0.40.1"])
        try await responder.look()
        offer = try await store.offer(bundleID: visor)
        XCTAssertEqual(offer?.state, .goAhead)
        events = await system.events
        XCTAssertEqual(events.last, "terminate")
    }

    func testANewerBuildAfterLaterIsAskedAtOnce() async throws {
        let store = store(), system = FakeSystem(), clock = TestClock(1_000)
        await system.setSheetAnswers([.later, .later])
        _ = try await store.makeOffer(bundleID: visor, version: "0.40.1", build: "1", offeredBy: "com.example.Applications")
        let responder = responder(store, system: system, clock: clock)
        try await responder.launched()
        _ = try await store.makeOffer(bundleID: visor, version: "0.40.2", build: "1", offeredBy: "com.example.Applications")
        try await responder.look()
        let events = await system.events
        XCTAssertEqual(events.filter { $0.hasPrefix("sheet") }, ["sheet 0.40.1", "sheet 0.40.2"])
    }

    /// Later, then Update in Shireworks: a person's offer of the same build,
    /// asked at once.
    func testAPersonAskingAgainIsAskedAtOnce() async throws {
        let store = store(), system = FakeSystem(), clock = TestClock(1_000)
        await system.setSheetAnswers([.later, .updateNow])
        _ = try await store.makeOffer(bundleID: visor, version: "0.40.1", build: "1", offeredBy: "com.example.Applications")
        let responder = responder(store, system: system, clock: clock)
        try await responder.launched()
        let asked = try await store.makeOffer(bundleID: visor, version: "0.40.1", build: "1", offeredBy: "com.example.Applications",
                                              byPerson: true)
        XCTAssertEqual(asked?.state, .offered)
        XCTAssertEqual(asked?.byPerson, true)
        try await responder.look()
        let offer = try await store.offer(bundleID: visor)
        XCTAssertEqual(offer?.state, .goAhead)
        XCTAssertEqual(offer?.byPerson, true)
    }

    /// An app's handler decides in place of the sheet, whatever it answers.
    func testAHandlerDecidesInsteadOfTheSheet() async throws {
        let store = store(), system = FakeSystem(), clock = TestClock(1_000)
        _ = try await store.makeOffer(bundleID: visor, version: "0.40.1", build: "1", offeredBy: "com.example.Applications",
                                      byPerson: true)
        var asked: [Bool] = []
        let responder = responder(store, system: system, clock: clock, handler: { offer in
            asked.append(offer.byPerson)
            return .deferUntilReady
        })
        try await responder.launched()
        clock.now = Date(timeIntervalSince1970: 1_000 + 3 * hour)
        try await responder.look()
        XCTAssertEqual(asked, [true], "asked once, and told it was a person's")
        let events = await system.events
        XCTAssertFalse(events.contains { $0.hasPrefix("sheet") })
        let offer = try await store.offer(bundleID: visor)
        XCTAssertEqual(offer?.state, .deferred)
    }

    // MARK: A person's offers

    func testAPersonsOfferIsRecordedAndReplacesOnlyOneNotUnderWay() async throws {
        let store = store()
        let automatic = try await store.makeOffer(bundleID: visor, version: "0.40.1", build: "1", offeredBy: "com.example.Applications")
        XCTAssertEqual(automatic?.byPerson, false)
        var read = try await store.offer(bundleID: visor)
        XCTAssertEqual(read?.byPerson, false)
        try await store.moveOffer(bundleID: visor, version: "0.40.1", build: "1", from: [.offered], to: .declined, note: "busy")
        let automaticAgain = try await store.makeOffer(bundleID: visor, version: "0.40.1", build: "1", offeredBy: "com.example.Applications")
        XCTAssertNil(automaticAgain, "a declined build isn't offered again automatically")
        let person = try await store.makeOffer(bundleID: visor, version: "0.40.1", build: "1", offeredBy: "com.example.Applications",
                                               byPerson: true)
        XCTAssertEqual(person?.state, .offered, "a person asking replaces the declined offer")
        read = try await store.offer(bundleID: visor)
        XCTAssertEqual(read?.byPerson, true)
        XCTAssertNil(read?.note)
        let older = try await store.makeOffer(bundleID: visor, version: "0.40.0", build: "1", offeredBy: "com.example.Applications",
                                              byPerson: true)
        XCTAssertNil(older, "never an older build")
        try await store.moveOffer(bundleID: visor, version: "0.40.1", build: "1", from: [.offered], to: .installMyself)
        let underWay = try await store.makeOffer(bundleID: visor, version: "0.40.1", build: "1", offeredBy: "com.example.Applications",
                                                 byPerson: true)
        XCTAssertNil(underWay, "one under way stands")
        // The setting is the distributor's: a person's offer is made for an
        // app whose "Update automatically" is off.
        let autoUpdating = try await store.autoUpdating()
        XCTAssertTrue(autoUpdating.isEmpty)
        let other = try await store.makeOffer(bundleID: "com.example.Other", version: "1.0", build: nil, offeredBy: "com.example.Applications",
                                              byPerson: true)
        XCTAssertEqual(other?.byPerson, true)
    }
}

/// A clock a test moves.
final class TestClock: @unchecked Sendable {
    var now: Date

    init(_ time: TimeInterval) {
        now = Date(timeIntervalSince1970: time)
    }
}
