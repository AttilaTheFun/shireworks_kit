import Foundation
import Testing

@testable import IssueComposer

struct IssueDraftTests {
    let png = IssueAttachment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "screenshot-1.png", contentType: "image/png", data: Data([1]))
    let logs = IssueAttachment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "logs.txt", contentType: "text/plain", data: Data([2]), altText: "Logs")

    @Test func needsATitle() {
        #expect(!IssueDraft().canSubmit)
        #expect(!IssueDraft(title: "  \n").canSubmit)
        #expect(IssueDraft(title: "Crash on launch").canSubmit)
    }

    @Test func attachAppendsMarkdown() {
        var draft = IssueDraft(title: "T", body: "It crashed.")
        draft.attach(png)
        #expect(draft.attachments == [png])
        #expect(draft.body == "It crashed.\n\n![screenshot-1.png](attachment:00000000-0000-0000-0000-000000000001)\n")
    }

    @Test func detachRemovesMarkdown() {
        var draft = IssueDraft(title: "T", body: "It crashed.")
        draft.attach(png)
        draft.attach(logs)
        draft.detach(png.id)
        #expect(draft.attachments == [logs])
        #expect(!draft.body.contains(png.placeholder))
        #expect(draft.body.contains(logs.markdown))
    }

    @Test func uploadedPlaceholdersBecomeURLs() throws {
        var draft = IssueDraft(title: "T", body: "It crashed.")
        draft.attach(png)
        let url = try #require(URL(string: "https://github.com/user-attachments/assets/abc"))
        #expect(draft.body(uploaded: [png.id: url])
            == "It crashed.\n\n![screenshot-1.png](https://github.com/user-attachments/assets/abc)\n")
    }

    @Test func failedUploadsAreLeftOutWithANote() throws {
        var draft = IssueDraft(title: "T", body: "It crashed.")
        draft.attach(png)
        draft.attach(logs)
        let url = try #require(URL(string: "https://github.com/user-attachments/assets/abc"))
        let body = draft.body(uploaded: [png.id: url])
        #expect(body.contains(url.absoluteString))
        #expect(!body.contains(logs.placeholder))
        #expect(body.hasSuffix("_1 attachment couldn't be uploaded._\n"))
    }
}
