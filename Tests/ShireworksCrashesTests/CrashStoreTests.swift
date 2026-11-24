// The crashes not yet filed, in a folder of their own: kept, read back
// oldest first, let go, and pruned by number and by age.

import Foundation
import Testing
@testable import ShireworksCrashes

struct CrashStoreTests {
    private let day: TimeInterval = 24 * 60 * 60
    private let now = Date(timeIntervalSince1970: 1_793_526_060)

    @Test func keptReadAndLetGo() throws {
        let store = CrashStore(folder: Fixtures.folder())
        #expect(store.reports().isEmpty)
        try store.add(Fixtures.report(id: "b", date: now))
        try store.add(Fixtures.report(id: "a", date: now - day))
        try store.add(Fixtures.report(id: "c", date: now - 2 * day))
        #expect(store.reports().map(\.id) == ["c", "a", "b"])
        #expect(store.reports().first == Fixtures.report(id: "c", date: now - 2 * day))

        // The same id again replaces it.
        try store.add(Fixtures.report(id: "a", version: "1.3.0", date: now - day))
        #expect(store.reports().count == 3)
        #expect(store.reports().first { $0.id == "a" }?.appVersion == "1.3.0")

        store.remove("c")
        #expect(store.reports().map(\.id) == ["a", "b"])
        store.remove("missing")
        #expect(store.reports().count == 2)
    }

    @Test func prunedToTheNewest() throws {
        let store = CrashStore(folder: Fixtures.folder())
        for index in 0..<25 {
            try store.add(Fixtures.report(id: "crash-\(index)", date: now - Double(index) * 60))
        }
        store.prune(maxCount: 20, maxAge: 30 * day, now: now)
        let kept = store.reports()
        #expect(kept.count == 20)
        #expect(kept.last?.id == "crash-0")
        #expect(kept.first?.id == "crash-19")
    }

    @Test func prunedByAgeAndUnreadableFiles() throws {
        let store = CrashStore(folder: Fixtures.folder())
        try store.add(Fixtures.report(id: "new", date: now - day))
        try store.add(Fixtures.report(id: "old", date: now - 31 * day))
        try Data("not a report".utf8).write(to: store.folder.appendingPathComponent("junk.json"))
        #expect(store.reports().map(\.id) == ["old", "new"])
        store.prune(maxCount: 20, maxAge: 30 * day, now: now)
        #expect(store.reports().map(\.id) == ["new"])
        let files = try FileManager.default.contentsOfDirectory(atPath: store.folder.path)
        #expect(files == ["new.json"])
    }

    /// Each app has its own folder, by its name.
    @Test func theAppsOwnFolder() {
        let store = CrashStore.standard(name: "com.example.app")
        #expect(store.folder.lastPathComponent == "com.example.app")
        #expect(store.folder.deletingLastPathComponent().lastPathComponent == "ShireworksCrashes")
    }
}
