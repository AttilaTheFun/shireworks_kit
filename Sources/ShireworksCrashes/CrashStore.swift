import Foundation

/// The crashes not yet filed: a folder of JSON files, one a report, kept
/// until each is filed (`remove`) or pruned (too many, or too old). A
/// device with no sign-in keeps at most the newest `CrashesConfiguration.maxStored`.
///
/// Each app has its own folder: `ShireworksCrashes/<bundle id>` in its
/// Application Support on Apple's systems (a Mac's unsandboxed apps share
/// one), and in `$XDG_DATA_HOME` (`~/.local/share`) elsewhere.
public struct CrashStore: Sendable {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// The app's own folder (above): `name`, the bundle id or else the
    /// process' name, keeps one app's crashes from another's.
    public static func standard(name: String = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName) -> CrashStore {
        CrashStore(folder: dataFolder.appendingPathComponent("ShireworksCrashes", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true))
    }

    private static var dataFolder: URL {
        #if canImport(Darwin)
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        #else
        if let data = ProcessInfo.processInfo.environment["XDG_DATA_HOME"], !data.isEmpty {
            return URL(fileURLWithPath: data, isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent(".local/share", isDirectory: true)
        #endif
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Keeps a report (in place of one with its id).
    public func add(_ report: CrashReport) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Self.encoder.encode(report).write(to: file(for: report.id), options: .atomic)
    }

    /// The reports kept, oldest first. A file that can't be read is left
    /// out (and `prune` deletes it).
    public func reports() -> [CrashReport] {
        files().compactMap { try? Self.decoder.decode(CrashReport.self, from: Data(contentsOf: $0)) }
            .sorted { $0.date < $1.date }
    }

    /// Lets a report go: filed.
    public func remove(_ id: String) {
        try? FileManager.default.removeItem(at: file(for: id))
    }

    /// Deletes the reports older than `maxAge`, then the oldest past
    /// `maxCount`, and any file that isn't a report.
    public func prune(maxCount: Int, maxAge: TimeInterval, now: Date = Date()) {
        var kept: [(URL, CrashReport)] = []
        for url in files() {
            guard let report = try? Self.decoder.decode(CrashReport.self, from: Data(contentsOf: url)),
                  now.timeIntervalSince(report.date) <= maxAge else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            kept.append((url, report))
        }
        kept.sort { $0.1.date > $1.1.date }
        for (url, _) in kept.dropFirst(max(maxCount, 0)) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func files() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.map { folder.appendingPathComponent($0) }
    }

    /// The report's file: its id, with anything but letters, digits, "-" and
    /// "_" left out.
    private func file(for id: String) -> URL {
        let safe = String(id.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }.map(Character.init))
        return folder.appendingPathComponent((safe.isEmpty ? "crash" : safe) + ".json")
    }
}
