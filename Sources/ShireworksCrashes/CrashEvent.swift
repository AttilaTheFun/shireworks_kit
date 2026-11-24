import Foundation

/// A crash reporter's event, as its JSON says it, made a CrashReport: the
/// reading of what Apple's crash reporter (Platform) hands over, kept apart
/// from it so that it is the same, and tested, everywhere.
///
/// The event is Sentry's event protocol, serialized: `level`, `event_id`,
/// `timestamp`, `exception.values`, `threads.values`, `debug_meta.images`,
/// `contexts.app`, `.os` and `.device`, and `breadcrumbs`. Its frames come
/// outermost first; a report's are innermost first.
enum CrashEvent {
    /// The report an event makes; nil for an event that isn't a crash
    /// (anything but `fatal`), or has no exception.
    static func report(from event: [String: Any]) -> CrashReport? {
        guard string(event["level"]) == "fatal",
              let exceptions = dictionary(event["exception"])?["values"] as? [Any],
              let exception = exceptions.compactMap({ $0 as? [String: Any] }).last else { return nil }

        let images = (dictionary(event["debug_meta"])?["images"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }.compactMap(image(from:))
        let uuids = Dictionary(images.compactMap { image in image.uuid.map { (image.address, $0) } }) { first, _ in first }
        func frames(of stacktrace: Any?) -> [CrashReport.Frame] {
            let raw = dictionary(stacktrace)?["frames"] as? [Any] ?? []
            return raw.compactMap { $0 as? [String: Any] }.compactMap { frame(from: $0, uuids: uuids) }.reversed()
        }

        // The crashing thread: the exception's own stacktrace where it has
        // one, else the thread marked crashed, else the exception's thread.
        let threads = (dictionary(event["threads"])?["values"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        let threadID = integer(exception["thread_id"])
        let crashedIndex = threads.firstIndex { bool($0["crashed"]) == true }
            ?? threads.firstIndex { threadID != nil && integer($0["id"]) == threadID }
        var crashing = frames(of: exception["stacktrace"])
        if crashing.isEmpty, let crashedIndex { crashing = frames(of: threads[crashedIndex]["stacktrace"]) }
        // The other threads with a frame read.
        let others: [CrashReport.Thread] = threads.indices.filter { $0 != crashedIndex }.compactMap { index in
            let thread = threads[index]
            let read = frames(of: thread["stacktrace"])
            guard !read.isEmpty else { return nil }
            return CrashReport.Thread(id: integer(thread["id"]).map(Int.init), name: string(thread["name"]), frames: read)
        }

        let contexts = dictionary(event["contexts"]) ?? [:]
        let app = dictionary(contexts["app"]) ?? [:]
        let release = releaseParts(string(event["release"]))
        let os = dictionary(contexts["os"]) ?? [:]
        let device = dictionary(contexts["device"]) ?? [:]
        let system = [string(os["name"]), string(os["version"])].compactMap { $0 }.joined(separator: " ")
            + (string(os["build"]).map { " (\($0))" } ?? "")
        var model = string(device["model"]) ?? string(device["model_id"]) ?? "unknown"
        if bool(device["simulator"]) == true { model += " (Simulator)" }

        let breadcrumbs = (event["breadcrumbs"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }.compactMap(breadcrumb(from:))
        let mechanism = dictionary(exception["mechanism"])
        return CrashReport(
            id: string(event["event_id"]) ?? UUID().uuidString.lowercased(),
            date: date(event["timestamp"]) ?? Date(),
            appVersion: string(app["app_version"]) ?? release.version ?? "",
            appBuild: string(app["app_build"]) ?? string(event["dist"]) ?? release.build ?? "",
            system: system.isEmpty ? "unknown" : system,
            deviceModel: model,
            exceptionType: string(exception["type"]) ?? "Crash",
            reason: string(exception["value"]) ?? "",
            mechanism: string(mechanism?["type"]),
            frames: crashing,
            threads: others.isEmpty ? nil : others,
            images: images,
            breadcrumbs: breadcrumbs.isEmpty ? nil : breadcrumbs)
    }

    private static func frame(from frame: [String: Any], uuids: [UInt64: String]) -> CrashReport.Frame? {
        // A frame at 0 is no frame (the end of a thread's stack, unread).
        guard let address = address(frame["instruction_addr"]), address != 0 else { return nil }
        let imageAddress = self.address(frame["image_addr"])
        var symbol = string(frame["function"])
        if symbol == "<redacted>" { symbol = nil }
        return CrashReport.Frame(
            imageName: string(frame["package"]).map(fileName),
            imageUUID: imageAddress.flatMap { uuids[$0] },
            instructionAddress: address, imageAddress: imageAddress, symbol: symbol,
            inApp: bool(frame["in_app"]) ?? false)
    }

    private static func image(from image: [String: Any]) -> CrashReport.Image? {
        guard let address = address(image["image_addr"]),
              let path = string(image["code_file"]) ?? string(image["name"]) else { return nil }
        return CrashReport.Image(name: fileName(path), uuid: string(image["debug_id"]) ?? string(image["uuid"]),
                                 address: address, size: self.address(image["image_size"]))
    }

    /// "12:00:00 [app.lifecycle] message (state: foreground)".
    private static func breadcrumb(from crumb: [String: Any]) -> String? {
        var parts: [String] = []
        if let date = date(crumb["timestamp"]) { parts.append(timeFormatter.string(from: date)) }
        if let category = string(crumb["category"]) { parts.append("[\(category)]") }
        if let message = string(crumb["message"]) { parts.append(message) }
        if let data = dictionary(crumb["data"]), !data.isEmpty {
            let pairs = data.keys.sorted().map { "\($0): \(data[$0].map { "\($0)" } ?? "")" }
            parts.append("(" + pairs.joined(separator: ", ") + ")")
        }
        return parts.isEmpty ? nil : String(parts.joined(separator: " ").prefix(200))
    }

    // MARK: Reading JSON's values

    /// "com.example.app@1.2.0+42": its version and build.
    private static func releaseParts(_ release: String?) -> (version: String?, build: String?) {
        guard let release, let at = release.lastIndex(of: "@") else { return (nil, nil) }
        let rest = release[release.index(after: at)...]
        let parts = rest.split(separator: "+", maxSplits: 1).map(String.init)
        return (parts.first, parts.count > 1 ? parts[1] : nil)
    }

    private static func fileName(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    private static func dictionary(_ value: Any?) -> [String: Any]? { value as? [String: Any] }

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.boolValue }
        return nil
    }

    private static func integer(_ value: Any?) -> Int64? {
        if let number = value as? Int { return Int64(number) }
        if let number = value as? Int64 { return number }
        if let number = value as? NSNumber { return number.int64Value }
        if let text = value as? String { return Int64(text) }
        return nil
    }

    /// An address or a size: "0x1a2b" or a number.
    static func address(_ value: Any?) -> UInt64? {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") { return UInt64(trimmed.dropFirst(2), radix: 16) }
            return UInt64(trimmed)
        }
        if let number = value as? UInt64 { return number }
        if let number = value as? Int, number >= 0 { return UInt64(number) }
        if let number = value as? NSNumber { return number.uint64Value }
        return nil
    }

    /// Seconds since 1970 (as the event says its time), or ISO 8601 (as its
    /// breadcrumbs do).
    private static func date(_ value: Any?) -> Date? {
        if let seconds = value as? Double { return Date(timeIntervalSince1970: seconds) }
        if let number = value as? NSNumber { return Date(timeIntervalSince1970: number.doubleValue) }
        guard let text = value as? String else { return nil }
        if let seconds = Double(text) { return Date(timeIntervalSince1970: seconds) }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    private static var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }
}
