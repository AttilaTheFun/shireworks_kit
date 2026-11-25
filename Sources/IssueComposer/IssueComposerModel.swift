import Foundation
import Observation

/// The composer's state: the draft being written, and submitting it through
/// the host. The composer doesn't talk to GitHub itself. The host gives it
/// `upload`, which turns an attachment into a URL, and `submit`, which files
/// the issue (or queues it, for a host with an outbox).
@MainActor
@Observable
public final class IssueComposerModel {
    public typealias Upload = @Sendable (IssueAttachment) async throws -> URL
    public typealias Submit = @Sendable (IssueSubmission) async throws -> Void

    public enum State: Equatable, Sendable {
        case editing
        case submitting
        case submitted
        case failed(String)
    }

    public var draft: IssueDraft
    public private(set) var state: State = .editing

    @ObservationIgnored private let store: DraftStore
    @ObservationIgnored private let upload: Upload
    @ObservationIgnored private let submitIssue: Submit
    /// Awaited at submit, before the attachments are uploaded: for a host
    /// still adding to the draft (a screenshot being made, say), so what it
    /// adds goes with the issue. Nil: nothing to wait for.
    @ObservationIgnored public var preparing: (@MainActor () async -> Void)?

    /// Starts from the draft the store kept, if any.
    public init(store: DraftStore, upload: @escaping Upload, submit: @escaping Submit) {
        self.store = store
        self.upload = upload
        self.submitIssue = submit
        self.draft = store.load() ?? IssueDraft()
    }

    public var canSubmit: Bool {
        draft.canSubmit && state != .submitting
    }

    public func attach(_ attachment: IssueAttachment) {
        draft.attach(attachment)
        saveDraft()
    }

    public func detach(_ id: IssueAttachment.ID) {
        draft.detach(id)
        saveDraft()
    }

    /// Keeps the draft, e.g. when the sheet closes unsent.
    public func saveDraft() {
        // Nothing to keep (after a submit, say): no empty draft on disk.
        if draft == IssueDraft() {
            store.clear()
        } else {
            store.save(draft)
        }
    }

    /// Throws the draft away.
    public func discard() {
        draft = IssueDraft()
        store.clear()
        state = .editing
    }

    /// Waits for the host's `preparing`, uploads the attachments, rewrites
    /// their placeholders to the URLs, and hands the issue to the host. An
    /// attachment that fails to upload is left out, with a note in the body;
    /// the issue is still submitted. If the submit fails, the draft is kept
    /// to try again.
    public func submit() async {
        guard canSubmit else { return }
        state = .submitting
        if let preparing { await preparing() }
        var uploaded: [IssueAttachment.ID: URL] = [:]
        for attachment in draft.attachments {
            if let url = try? await upload(attachment) {
                uploaded[attachment.id] = url
            }
        }
        let submission = IssueSubmission(
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            body: draft.body(uploaded: uploaded))
        do {
            try await submitIssue(submission)
            draft = IssueDraft()
            store.clear()
            state = .submitted
        } catch {
            saveDraft()
            state = .failed(String(describing: error))
        }
    }
}
