import Foundation
@testable import ShakeKit
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
