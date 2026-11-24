import Foundation

/// The `.shakeToReport` views showing, and which one answers a request:
/// the one made active most recently (its window key on a Mac, its scene
/// active on iOS) that still is. So an app may put the modifier on every
/// window, and a request opens one sheet, not one in each. With none
/// active, the one shown most recently answers, as before.
@MainActor
final class ReportPresenters {
    static let shared = ReportPresenters()

    /// Every view showing, the most recently shown last.
    private var shown: [UUID] = []
    /// Those active, the most recently made active last.
    private var active: [UUID] = []

    /// `id` showing, active or not (as it appears, and as that changes).
    func set(_ id: UUID, active isActive: Bool) {
        if !shown.contains(id) { shown.append(id) }
        active.removeAll { $0 == id }
        if isActive { active.append(id) }
    }

    /// `id` gone (its window closed).
    func remove(_ id: UUID) {
        shown.removeAll { $0 == id }
        active.removeAll { $0 == id }
    }

    /// Whether `id` is the one to answer a request.
    func answers(_ id: UUID) -> Bool {
        (active.last ?? shown.last) == id
    }

    /// Whether a view showing is active: one that would answer where the
    /// person is looking. With none, a Mac app's own report window (if it
    /// added one) is opened instead.
    var hasActive: Bool { !active.isEmpty }
}
