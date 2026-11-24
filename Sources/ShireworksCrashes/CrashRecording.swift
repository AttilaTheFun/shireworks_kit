import Foundation

/// A crash recorder's report, as its JSON says it, made a CrashReport: the
/// reading of what Apple's recorder (Platform) hands over, kept apart from
/// it so that it is the same, and tested, everywhere.
///
/// The report is KSCrash's: `report` (its id and time), `crash.error` (how
/// it was caught: `type`, `mach`, `signal`, `nsexception`, `cpp_exception`,
/// `reason`), `crash.threads` (each one's `backtrace.contents`, innermost
/// frame first, and which `crashed`), `binary_images` (with the Swift
/// runtime's `crash_info_message`, "Fatal error: …"), and `system` (the
/// app's version and build, the system, the machine).
enum CrashRecording {
    /// The report a recorder's report makes; nil for one that isn't a crash
    /// (a clean exit, or one marked not fatal). `executable`: the app's
    /// executable's name, where the report doesn't say it: its frames are
    /// the app's own.
    static func report(from record: [String: Any], executable: String? = nil) -> CrashReport? {
        guard let crash = dictionary(record["crash"]), let error = dictionary(crash["error"]),
              bool(error["is_fatal"]) != false, bool(error["is_clean_exit"]) != true else { return nil }
        let header = dictionary(record["report"]) ?? [:]
        let system = dictionary(record["system"]) ?? [:]
        let own = string(system["CFBundleExecutable"]) ?? executable ?? string(system["process_name"]) ?? string(header["process_name"])

        let rawImages = (record["binary_images"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        let images = rawImages.compactMap(image(from:))
        let uuids = Dictionary(images.compactMap { image in image.uuid.map { (image.address, $0) } }) { first, _ in first }
        func frames(of thread: [String: Any]) -> [CrashReport.Frame] {
            let contents = dictionary(thread["backtrace"])?["contents"] as? [Any] ?? []
            return contents.compactMap { $0 as? [String: Any] }.compactMap { frame(from: $0, own: own, uuids: uuids) }
        }

        // The crashing thread, and the others with a frame read.
        let threads = (crash["threads"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        let crashedIndex = threads.firstIndex { bool($0["crashed"]) == true }
        let crashing = crashedIndex.map { frames(of: threads[$0]) } ?? []
        let others: [CrashReport.Thread] = threads.indices.filter { $0 != crashedIndex }.compactMap { index in
            let thread = threads[index]
            let read = frames(of: thread)
            guard !read.isEmpty else { return nil }
            return CrashReport.Thread(id: integer(thread["index"]).map(Int.init),
                                      name: string(thread["name"]) ?? string(thread["dispatch_queue"]), frames: read)
        }

        let (type, reason) = exception(of: error, messages: rawImages.compactMap { string($0["crash_info_message"]) })
        var model = string(system["machine"]) ?? string(system["model"]) ?? "unknown"
        if string(system["build_type"]) == "simulator" { model += " (Simulator)" }
        let name = [string(system["system_name"]), string(system["system_version"])].compactMap { $0 }.joined(separator: " ")
        return CrashReport(
            id: string(header["id"]) ?? UUID().uuidString,
            date: date(header["timestamp"]) ?? Date(),
            appVersion: string(system["CFBundleShortVersionString"]) ?? "",
            appBuild: string(system["CFBundleVersion"]) ?? "",
            system: name.isEmpty ? "unknown" : name + (string(system["os_version"]).map { " (\($0))" } ?? ""),
            deviceModel: model,
            exceptionType: type,
            reason: reason,
            mechanism: string(error["type"]),
            frames: crashing,
            threads: others.isEmpty ? nil : others,
            images: images)
    }

    /// The exception's type and reason: an NSException's or a C++
    /// exception's name and reason; else the Mach exception (or the signal),
    /// with the reason the Swift runtime (or the C library) left beside it
    /// ("Fatal error: Index out of range"), or else the signal and, for a bad
    /// access, its code and address.
    private static func exception(of error: [String: Any], messages: [String]) -> (type: String, reason: String) {
        let mach = dictionary(error["mach"]) ?? [:]
        let signal = dictionary(error["signal"]) ?? [:]
        let given = string(error["reason"])
        switch string(error["type"]) {
        case "nsexception":
            let exception = dictionary(error["nsexception"]) ?? [:]
            return (string(exception["name"]) ?? "NSException", given ?? string(exception["reason"]) ?? "")
        case "cpp_exception":
            return (string(dictionary(error["cpp_exception"])?["name"]) ?? "C++ exception", given ?? "")
        default:
            let type = string(mach["exception_name"]) ?? string(signal["name"]) ?? string(error["type"]) ?? "Crash"
            if let reason = given ?? messages.first { return (type, reason) }
            var parts = [string(signal["name"])].compactMap { $0 }
            if type == "EXC_BAD_ACCESS", let code = string(mach["code_name"]) {
                parts.append(code + (address(error["address"]).map { " at " + CrashReport.hex($0) } ?? ""))
            }
            return (type, parts.joined(separator: ", "))
        }
    }

    private static func frame(from frame: [String: Any], own: String?, uuids: [UInt64: String]) -> CrashReport.Frame? {
        // A frame at 0 is no frame (the end of a thread's stack, unread).
        guard let address = address(frame["instruction_addr"]), address != 0 else { return nil }
        let imageAddress = self.address(frame["object_addr"])
        let imageName = string(frame["object_name"]).map(fileName)
        return CrashReport.Frame(
            imageName: imageName,
            imageUUID: string(frame["object_uuid"]) ?? imageAddress.flatMap { uuids[$0] },
            instructionAddress: address, imageAddress: imageAddress, symbol: string(frame["symbol_name"]),
            inApp: own != nil && imageName == own)
    }

    private static func image(from image: [String: Any]) -> CrashReport.Image? {
        guard let address = address(image["image_addr"]), let path = string(image["name"]) else { return nil }
        return CrashReport.Image(name: fileName(path), uuid: string(image["uuid"]), address: address,
                                 size: self.address(image["image_size"]))
    }

    // MARK: Reading JSON's values

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

    /// An address or a size: a number, or "0x1a2b".
    static func address(_ value: Any?) -> UInt64? {
        if let number = value as? UInt64 { return number }
        if let number = value as? Int, number >= 0 { return UInt64(number) }
        if let number = value as? NSNumber { return number.uint64Value }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") { return UInt64(trimmed.dropFirst(2), radix: 16) }
            return UInt64(trimmed)
        }
        return nil
    }

    /// ISO 8601, to the microsecond ("2026-11-24T18:27:05.779506Z"), as the
    /// report says its time; or seconds since 1970, as older ones did.
    static func date(_ value: Any?) -> Date? {
        if let seconds = value as? Double { return Date(timeIntervalSince1970: seconds) }
        if let seconds = value as? Int { return Date(timeIntervalSince1970: TimeInterval(seconds)) }
        guard let text = value as? String else { return nil }
        if let seconds = Double(text) { return Date(timeIntervalSince1970: seconds) }
        // The fraction apart: ISO8601DateFormatter reads three digits of it at most.
        var whole = text, fraction = 0.0
        if let dot = text.firstIndex(of: ".") {
            let digits = text[text.index(after: dot)...].prefix { $0.isASCII && $0.isNumber }
            fraction = Double("0." + digits) ?? 0
            whole = String(text[..<dot]) + String(text[text.index(after: dot)...].dropFirst(digits.count))
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: whole).map { $0.addingTimeInterval(fraction) }
    }
}
