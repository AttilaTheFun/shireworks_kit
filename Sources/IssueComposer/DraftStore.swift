import Foundation

/// Where the composer keeps an unsent draft, so it survives the sheet
/// closing, a failed submit or the app quitting. A host with a cache of its
/// own can keep drafts there instead.
public protocol DraftStore: Sendable {
    func load() -> IssueDraft?
    func save(_ draft: IssueDraft)
    func clear()
}

/// Keeps the draft as one JSON file. Screenshots can be megabytes, so a
/// file, not UserDefaults.
public struct FileDraftStore: DraftStore {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `<Application Support>/ShakeKit/Drafts/<name>.json` in the app's own
    /// container.
    public init(name: String) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.init(url: base.appendingPathComponent("ShakeKit/Drafts/\(name).json"))
    }

    public func load() -> IssueDraft? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(IssueDraft.self, from: data)
    }

    public func save(_ draft: IssueDraft) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Keeps the draft in memory only: for tests and previews.
public final class MemoryDraftStore: DraftStore, @unchecked Sendable {
    private let lock = NSLock()
    private var draft: IssueDraft?

    public init(_ draft: IssueDraft? = nil) {
        self.draft = draft
    }

    public func load() -> IssueDraft? { lock.withLock { draft } }
    public func save(_ draft: IssueDraft) { lock.withLock { self.draft = draft } }
    public func clear() { lock.withLock { draft = nil } }
}
