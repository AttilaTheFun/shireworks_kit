import Foundation

/// The `.shakeToReport` views showing, and which one answers a request:
/// the one made active most recently (its window key on a Mac, its scene
/// active on iOS) that still is. So an app may put the modifier on every
/// window, and a request opens one sheet, not one in each. With none
/// active, the one shown most recently answers, as before. It hears the
/// requests (`ShakeReport.requested`) itself, once for the process, and
/// hands each to that view: through Foundation's notifications alone, as
/// Isomer's hosts have no Combine publisher of them.
@MainActor
final class ReportPresenters {
    static let shared = ReportPresenters()

    /// Every view showing, the most recently shown last.
    private var shown: [UUID] = []
    /// Those active, the most recently made active last.
    private var active: [UUID] = []
    /// What each view showing does with a request (presents its report).
    private var handlers: [UUID: @MainActor (ShakeReport.Trigger) -> Void] = [:]
    /// The requests' observer, once one view answers.
    private var observer: (any NSObjectProtocol)?

    /// `id` showing, active or not (as it appears, and as that changes).
    func set(_ id: UUID, active isActive: Bool) {
        if !shown.contains(id) { shown.append(id) }
        active.removeAll { $0 == id }
        if isActive { active.append(id) }
    }

    /// `id` showing, `answer` what it does with a request: the requests
    /// heard from now on.
    func set(_ id: UUID, active isActive: Bool, answer: @escaping @MainActor (ShakeReport.Trigger) -> Void) {
        set(id, active: isActive)
        handlers[id] = answer
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: ShakeReport.requested, object: nil, queue: nil) { notification in
            let trigger = notification.object as? ShakeReport.Trigger ?? .request
            Task { @MainActor in ReportPresenters.shared.deliver(trigger) }
        }
    }

    /// `id` gone (its window closed).
    func remove(_ id: UUID) {
        shown.removeAll { $0 == id }
        active.removeAll { $0 == id }
        handlers[id] = nil
    }

    /// A request handed to the view that answers it; none with none showing.
    func deliver(_ trigger: ShakeReport.Trigger) {
        guard let id = active.last ?? shown.last else { return }
        handlers[id]?(trigger)
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
