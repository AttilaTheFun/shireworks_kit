import Foundation
import Testing

@testable import IssueComposer

private struct Refused: Error {}

private actor Recorder {
    var submissions: [IssueSubmission] = []
    func record(_ submission: IssueSubmission) { submissions.append(submission) }
}

@MainActor
struct IssueComposerModelTests {
    let png = IssueAttachment(name: "screenshot-1.png", contentType: "image/png", data: Data([1]))
    let logs = IssueAttachment(name: "logs.txt", contentType: "text/plain", data: Data([2]))
    let assetURL = URL(string: "https://github.com/user-attachments/assets/abc")!

    @Test func startsFromTheKeptDraft() {
        let store = MemoryDraftStore(IssueDraft(title: "Kept"))
        let model = IssueComposerModel(store: store, upload: { _ in throw Refused() }, submit: { _ in })
        #expect(model.draft.title == "Kept")
    }

    @Test func submitUploadsThenHandsOver() async {
        let recorder = Recorder()
        let store = MemoryDraftStore()
        let url = assetURL
        let model = IssueComposerModel(
            store: store, upload: { _ in url }, submit: { await recorder.record($0) })
        model.draft.title = "  Crash  "
        model.attach(png)
        await model.submit()

        let submissions = await recorder.submissions
        #expect(submissions.count == 1)
        #expect(submissions.first?.title == "Crash")
        #expect(submissions.first?.body.contains(url.absoluteString) == true)
        #expect(model.state == .submitted)
        #expect(model.draft == IssueDraft())
        #expect(store.load() == nil)
    }

    @Test func failedUploadStillSubmits() async {
        let recorder = Recorder()
        let url = assetURL
        let pngID = png.id
        let model = IssueComposerModel(
            store: MemoryDraftStore(),
            upload: { attachment in
                guard attachment.id == pngID else { throw Refused() }
                return url
            },
            submit: { await recorder.record($0) })
        model.draft.title = "Crash"
        model.attach(png)
        model.attach(logs)
        await model.submit()

        let body = await recorder.submissions.first?.body ?? ""
        #expect(body.contains(url.absoluteString))
        #expect(!body.contains(logs.placeholder))
        #expect(body.contains("1 attachment couldn't be uploaded"))
    }

    @Test func failedSubmitKeepsTheDraft() async {
        let store = MemoryDraftStore()
        let model = IssueComposerModel(store: store, upload: { _ in throw Refused() }, submit: { _ in throw Refused() })
        model.draft.title = "Crash"
        await model.submit()

        guard case .failed = model.state else {
            Issue.record("expected .failed, got \(model.state)")
            return
        }
        #expect(model.draft.title == "Crash")
        #expect(store.load()?.title == "Crash")
    }

    @Test func noTitleNoSubmit() async {
        let recorder = Recorder()
        let model = IssueComposerModel(store: MemoryDraftStore(), upload: { _ in throw Refused() }, submit: { await recorder.record($0) })
        #expect(!model.canSubmit)
        await model.submit()
        #expect(await recorder.submissions.isEmpty)
        #expect(model.state == .editing)
    }

    @Test func discardClearsTheStore() {
        let store = MemoryDraftStore(IssueDraft(title: "Kept"))
        let model = IssueComposerModel(store: store, upload: { _ in throw Refused() }, submit: { _ in })
        model.discard()
        #expect(model.draft == IssueDraft())
        #expect(store.load() == nil)
    }
}

struct FileDraftStoreTests {
    @Test func roundTrips() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("draft.json")
        let store = FileDraftStore(url: url)
        #expect(store.load() == nil)
        var draft = IssueDraft(title: "Crash", body: "It crashed.")
        draft.attach(IssueAttachment(name: "a.png", contentType: "image/png", data: Data([1, 2, 3])))
        store.save(draft)
        #expect(store.load() == draft)
        store.clear()
        #expect(store.load() == nil)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
