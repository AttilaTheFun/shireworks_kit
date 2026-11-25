import Foundation
@testable import ShireworksShake
import Testing

/// A request is answered by one `.shakeToReport` view: the most recently
/// made active that still is, else the most recently shown.
@MainActor
struct ReportPresentersTests {
    @Test func theMostRecentlyActiveOneAnswers() {
        let presenters = ReportPresenters()
        let main = UUID(), settings = UUID()
        presenters.set(main, active: true)
        presenters.set(settings, active: false)
        #expect(presenters.answers(main) && !presenters.answers(settings))
        // Settings' window made key: it answers, and main no longer does.
        presenters.set(main, active: false)
        presenters.set(settings, active: true)
        #expect(presenters.answers(settings) && !presenters.answers(main))
        #expect(presenters.hasActive)
        // Settings closed: none active, so main, the one still shown, answers.
        presenters.remove(settings)
        #expect(presenters.answers(main))
        #expect(!presenters.hasActive)
        presenters.remove(main)
        #expect(!presenters.answers(main))
    }

    @Test func aRequestIsHandedToTheOneThatAnswers() {
        let presenters = ReportPresenters()
        let main = UUID(), settings = UUID()
        var heard: [String] = []
        presenters.set(main, active: false) { heard.append("main \($0)") }
        presenters.set(settings, active: true) { heard.append("settings \($0)") }
        presenters.deliver(.shake)
        presenters.remove(settings)
        presenters.deliver(.request)
        presenters.remove(main)
        presenters.deliver(.request)
        #expect(heard == ["settings shake", "main request"])
    }

    /// `ShakeReport.request()`'s notification reaches the view that answers, through the shared presenters.
    @Test func aPostedRequestReachesTheSharedPresenters() async {
        let id = UUID()
        var heard: [ShakeReport.Trigger] = []
        ReportPresenters.shared.set(id, active: true) { heard.append($0) }
        defer { ReportPresenters.shared.remove(id) }
        ShakeReport.request()
        for _ in 0..<200 where heard.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(heard == [.request])
    }

    @Test func twoActiveAtOnceTheLaterAnswers() {
        // An iPad's two scenes side by side, both active.
        let presenters = ReportPresenters()
        let left = UUID(), right = UUID()
        presenters.set(left, active: true)
        presenters.set(right, active: true)
        #expect(presenters.answers(right) && !presenters.answers(left))
        presenters.set(left, active: true)
        #expect(presenters.answers(left))
    }
}
