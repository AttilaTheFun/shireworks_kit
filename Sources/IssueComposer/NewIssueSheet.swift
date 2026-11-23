#if canImport(SwiftUI)
import SwiftUI

/// The issue composer: title, description and attachments, then Create.
/// `accessory` sits beside the title and description, for the host's own
/// fields (pickers for kind or priority, say, or a report's device info).
public struct NewIssueSheet<Accessory: View>: View {
    @Bindable var model: IssueComposerModel
    let title: String
    let accessory: Accessory
    @Environment(\.dismiss) private var dismiss

    public init(
        model: IssueComposerModel,
        title: String = "New Issue",
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.model = model
        self.title = title
        self.accessory = accessory()
    }

    public var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $model.draft.title)
                accessory
                Section("Description") {
                    TextEditor(text: $model.draft.body)
                        .frame(minHeight: 140)
                }
                if !model.draft.attachments.isEmpty {
                    Section("Attachments") {
                        ScrollView(.horizontal) {
                            HStack(spacing: 12) {
                                ForEach(model.draft.attachments) { attachment in
                                    AttachmentThumbnail(attachment: attachment) {
                                        model.detach(attachment.id)
                                    }
                                }
                            }
                        }
                    }
                }
                if case .failed(let message) = model.state {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(title)
            .disabled(model.state == .submitting)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.saveDraft()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.state == .submitting {
                        ProgressView()
                    } else {
                        Button("Create") {
                            Task {
                                await model.submit()
                                if model.state == .submitted {
                                    dismiss()
                                }
                            }
                        }
                        .disabled(!model.canSubmit)
                    }
                }
            }
        }
        .onDisappear { model.saveDraft() }
    }
}

extension NewIssueSheet where Accessory == EmptyView {
    public init(model: IssueComposerModel, title: String = "New Issue") {
        self.init(model: model, title: title) { EmptyView() }
    }
}

/// An attachment's thumbnail (or a file icon, for one that isn't an
/// image), with a button to remove it.
struct AttachmentThumbnail: View {
    let attachment: IssueAttachment
    let remove: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let image = Image(attachmentData: attachment.data) {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "doc.text").font(.largeTitle)
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topTrailing) {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove \(attachment.name)")
            }
            Text(attachment.name)
                .font(.caption2)
                .lineLimit(1)
                .frame(width: 72)
        }
    }
}
#endif
