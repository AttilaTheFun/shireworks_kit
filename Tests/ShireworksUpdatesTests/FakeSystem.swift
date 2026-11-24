import ShireworksUpdates
import Foundation

/// The system as a test sees it: what was asked of it, in order.
actor FakeSystem: UpdateSystem {
    private(set) var events: [String] = []
    var opensURLs = true
    var hasApplications = true
    /// The update sheet's answers, in turn; Update Now once they run out.
    var sheetAnswers: [UpdateSheetAnswer?] = []
    /// The app's activations, which a test sends (`activate()`).
    nonisolated let activationStream = AsyncStream<Void>.makeStream()

    func setOpensURLs(_ value: Bool) { opensURLs = value }
    func setHasApplications(_ value: Bool) { hasApplications = value }
    func setSheetAnswers(_ value: [UpdateSheetAnswer?]) { sheetAnswers = value }

    func open(_ url: URL) async -> Bool {
        events.append("open \(url.absoluteString)")
        return opensURLs
    }

    func openApplications() async throws {
        guard hasApplications else { throw UpdateInstallError.applicationsNotInstalled }
        events.append("open Applications")
    }

    func terminate() async { events.append("terminate") }

    func databaseChanged() async { events.append("changed") }

    func showUpdateSheet(_ offer: UpdateOffer) async -> UpdateSheetAnswer? {
        events.append("sheet \(offer.version)")
        return sheetAnswers.isEmpty ? .updateNow : sheetAnswers.removeFirst()
    }

    nonisolated func activations() -> AsyncStream<Void> { activationStream.stream }

    /// The app comes to the front.
    nonisolated func activate() { activationStream.continuation.yield() }
}
