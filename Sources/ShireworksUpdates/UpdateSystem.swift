import Foundation

/// What installing asks of the system: Apple's (`AppleUpdateSystem`), or a
/// stand-in in tests.
public protocol UpdateSystem: Sendable {
    /// Opens a URL (an over-the-air install link): whether the system took it.
    func open(_ url: URL) async -> Bool
    /// Opens Applications, or brings it forward: throws when it is not installed.
    func openApplications() async throws
    /// Quits the app as the user quitting it would.
    func terminate() async
    /// Tells the other apps of the group that the database changed.
    func databaseChanged() async
    /// Shows the update sheet for an offer, for an app that registered no
    /// handler of offers: Update Now or Later, or nil when it can't be shown
    /// now (the app isn't in front, another modal window is up), so the
    /// offer is looked at again at the next check or activation. Without
    /// one of its own, a system answers Update Now, as before the sheet.
    func showUpdateSheet(_ offer: UpdateOffer) async -> UpdateSheetAnswer?
    /// Each time the app becomes active (comes to the front), when the
    /// offers are looked at again. Without one of its own, never.
    func activations() -> AsyncStream<Void>
}

extension UpdateSystem {
    public func showUpdateSheet(_ offer: UpdateOffer) async -> UpdateSheetAnswer? { .updateNow }

    public func activations() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}
