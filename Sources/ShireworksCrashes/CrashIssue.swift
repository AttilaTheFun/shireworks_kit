import Foundation
import GitHubIssues

/// What a crash's issue says, and what finds it again: its title, its body
/// (a summary, the crashing thread, the app and device, then the other
/// threads, the binary images and the breadcrumbs folded away, then its
/// markers), and the comment each crash after the first adds.
///
/// Two HTML comments end the body, unseen on GitHub: the crash's signature
/// (`<!-- shireworks-crash: <signature> -->`), which finds the issue, and
/// the newest app version it was seen in
/// (`<!-- shireworks-crash-version: x.y.z -->`), which decides whether a
/// closed issue opens again.
public enum CrashIssue {
    /// The most a body or a comment holds, in UTF-8 bytes: under GitHub's
    /// 65,536 characters, whatever the characters.
    public static let limit = 60_000

    /// What the body carries to be found by: the signature's marker.
    public static func marker(_ signature: String) -> String { "<!-- shireworks-crash: \(signature) -->" }

    static let versionPrefix = "<!-- shireworks-crash-version: "

    /// The version marker.
    public static func versionMarker(_ version: String) -> String { versionPrefix + version + " -->" }

    /// The version a body's marker records; nil with none.
    public static func recordedVersion(in body: String) -> String? {
        guard let start = body.range(of: versionPrefix),
              let end = body.range(of: " -->", range: start.upperBound..<body.endIndex) else { return nil }
        let version = body[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespaces)
        return version.isEmpty ? nil : version
    }

    /// The body with its version marker saying `version` (added where it had none).
    public static func body(_ body: String, recording version: String) -> String {
        guard let start = body.range(of: versionPrefix),
              let end = body.range(of: " -->", range: start.upperBound..<body.endIndex) else {
            return body + (body.hasSuffix("\n") ? "" : "\n") + versionMarker(version) + "\n"
        }
        return body.replacingCharacters(in: start.lowerBound..<end.upperBound, with: versionMarker(version))
    }

    /// Whether `version` comes after `other`, part by dotted part as numbers
    /// (0.10.2 after 0.9.34; 1.2 is 1.2.0), each part by its leading digits.
    public static func isVersion(_ version: String, newerThan other: String) -> Bool {
        func parts(_ text: String) -> [Int] {
            text.split(separator: ".").map { Int($0.prefix { $0.isASCII && $0.isNumber }.prefix(18)) ?? 0 }
        }
        let a = parts(version), b = parts(other)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: Title

    /// "Crash: EXC_BAD_ACCESS: KERN_INVALID_ADDRESS at 0x0 (MyApp + 0x1a2b)":
    /// the exception, the first line of its reason (shortened), and the top
    /// frame of the app's own, else the top frame.
    public static func title(for report: CrashReport, redactions: [String] = []) -> String {
        var reason = redacted(report.reason, extra: redactions)
            .split(separator: "\n").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        if reason.count > 80 { reason = String(reason.prefix(79)) + "…" }
        var title = "Crash: " + report.exceptionType + (reason.isEmpty ? "" : ": " + reason)
        if let top = report.topFrames.first { title += " (\(redacted(top.location, extra: redactions)))" }
        return title.count > 250 ? String(title.prefix(249)) + "…" : title
    }

    // MARK: Body

    /// A part folded in `<details>`: its summary and its lines, and how many
    /// were left out to fit.
    struct Folded {
        var title: String
        var lines: [String]
        var dropped = 0

        var markdown: String {
            let note = dropped > 0 ? "\n… \(dropped) more left out" : ""
            return "<details><summary>\(title)</summary>\n\n" + CrashIssue.fenced(lines.joined(separator: "\n") + note) + "\n\n</details>"
        }
    }

    /// The issue's body: under `limit`, the folded parts cut first (the
    /// largest first), then the crashing thread's outermost frames.
    public static func body(for report: CrashReport, redactions: [String] = [], limit: Int = limit) -> String {
        let head = summary(of: report)
        var crashing = frameLines(report.frames)
        var crashingDropped = 0
        var folded: [Folded] = []
        if let threads = report.threads, !threads.isEmpty {
            let lines = threads.flatMap { thread -> [String] in
                let name = [thread.id.map { " \($0)" }, thread.name.map { " (\($0))" }].compactMap { $0 }.joined()
                return ["Thread\(name):"] + frameLines(thread.frames) + [""]
            }
            folded.append(Folded(title: "Other threads (\(threads.count))", lines: lines))
        }
        if !report.images.isEmpty {
            folded.append(Folded(title: "Binary images (\(report.images.count))", lines: report.images.map(imageLine)))
        }
        if let breadcrumbs = report.breadcrumbs, !breadcrumbs.isEmpty {
            folded.append(Folded(title: "Breadcrumbs (\(breadcrumbs.count))", lines: breadcrumbs))
        }
        let markers = marker(report.signature) + "\n" + versionMarker(report.appVersion) + "\n"
        let note = "Frames the device had no symbol for name their image and its offset; the binary images give "
            + "each image's UUID, to symbolicate them against the build's dSYMs."

        func compose() -> String {
            let thread = "The crashing thread, innermost frame first:\n\n"
                + fenced(crashing.joined(separator: "\n") + (crashingDropped > 0 ? "\n… \(crashingDropped) more left out" : ""))
            let parts = [head, thread, environment(of: report)] + folded.map(\.markdown) + [note]
            return redacted(parts.joined(separator: "\n\n"), extra: redactions) + "\n\n" + markers
        }

        var text = compose()
        while text.utf8.count > limit {
            // Enough to fit, and a little for the note of what was left out.
            let excess = text.utf8.count - limit + 64
            if let index = folded.indices.max(by: { size(folded[$0].lines) < size(folded[$1].lines) }),
               !folded[index].lines.isEmpty {
                var removed = 0
                while removed < excess, let line = folded[index].lines.popLast() {
                    removed += line.utf8.count + 1
                    folded[index].dropped += 1
                }
                if folded[index].lines.isEmpty { folded.remove(at: index) }
            } else if !folded.isEmpty {
                folded.removeAll()
            } else if crashing.count > 1 {
                var removed = 0
                while removed < excess, crashing.count > 1, let line = crashing.popLast() {
                    removed += line.utf8.count + 1
                    crashingDropped += 1
                }
            } else {
                // Only the summary is left too long: cut its end.
                return String(decoding: Array(text.utf8.prefix(limit - markers.utf8.count - 8)), as: UTF8.self) + "\n\n" + markers
            }
            text = compose()
        }
        return text
    }

    /// The comment a crash after the first adds: when and where, and its
    /// crashing thread.
    public static func comment(for report: CrashReport, redactions: [String] = [], limit: Int = limit) -> String {
        var lines = frameLines(report.frames)
        let head = "Again in \(version(of: report)), \(report.deviceModel), \(report.system), \(iso8601(report.date))"
        var dropped = 0
        func compose() -> String {
            let frames = lines.joined(separator: "\n") + (dropped > 0 ? "\n… \(dropped) more left out" : "")
            return redacted(head + "\n\n" + fenced(frames), extra: redactions) + "\n"
        }
        var text = compose()
        while text.utf8.count > limit, lines.count > 1 {
            lines.removeLast(max(lines.count / 4, 1))
            dropped = report.frames.count - lines.count
            text = compose()
        }
        return text
    }

    // MARK: Parts

    /// A home folder's user name, out of the paths a crash's reason or
    /// breadcrumbs may name.
    static let homeFolders = [#"(?<=/Users/)[^/\s]+"#, #"(?<=/home/)[^/\s]+"#]

    /// `text` redacted for an issue: GitHubIssues' rules, home folders'
    /// names, and the host's own patterns.
    static func redacted(_ text: String, extra redactions: [String]) -> String {
        IssueRedaction.redacted(text, extra: homeFolders + redactions)
    }

    private static func summary(of report: CrashReport) -> String {
        var text = "**\(report.exceptionType)**"
        let reason = report.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if !reason.isEmpty { text += ": " + reason }
        if let mechanism = report.mechanism { text += "\n\nCaught as: \(mechanism)" }
        return text
    }

    private static func environment(of report: CrashReport) -> String {
        let rows: [(String, String)] = [
            ("Version", version(of: report)),
            ("System", report.system),
            ("Device", report.deviceModel),
            ("Crashed", iso8601(report.date)),
            ("Signature", "`\(report.signature)`"),
        ]
        return (["| | |", "| --- | --- |"] + rows.map { "| \($0.0) | \($0.1.replacingOccurrences(of: "|", with: "\\|")) |" })
            .joined(separator: "\n")
    }

    /// "1.2.0 (42)", "1.2.0", or "an unknown version" (a build with no Info.plist).
    private static func version(of report: CrashReport) -> String {
        if report.appVersion.isEmpty { return "an unknown version" }
        return report.appBuild.isEmpty || report.appBuild == report.appVersion ? report.appVersion : "\(report.appVersion) (\(report.appBuild))"
    }

    /// "0   MyApp                        0x0000000100123abc  main (MyApp + 0x3abc)".
    static func frameLines(_ frames: [CrashReport.Frame]) -> [String] {
        frames.enumerated().map { index, frame in
            let image = frame.imageName ?? "?"
            var line = padded(String(index), 4) + padded(image, 32) + address(frame.instructionAddress) + "  "
            let offset = frame.offset.map { image + " + " + CrashReport.hex($0) }
            if let symbol = frame.symbol, symbol != "<redacted>" {
                line += symbol + (offset.map { " (\($0))" } ?? "")
            } else {
                line += offset ?? image
            }
            return line
        }
    }

    /// "0x0000000100000000  MyApp  <UUID>  (1234567 bytes)".
    private static func imageLine(_ image: CrashReport.Image) -> String {
        address(image.address) + "  " + padded(image.name, 32) + (image.uuid ?? "no UUID") + (image.size.map { "  (\($0) bytes)" } ?? "")
    }

    private static func address(_ value: UInt64) -> String {
        let digits = String(value, radix: 16)
        return "0x" + String(repeating: "0", count: max(16 - digits.count, 0)) + digits
    }

    private static func padded(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
    }

    /// In a fence the text can't close early.
    static func fenced(_ text: String) -> String {
        let fence = text.contains("```") ? "~~~~" : "```"
        return fence + "\n" + text + "\n" + fence
    }

    private static func size(_ lines: [String]) -> Int { lines.reduce(0) { $0 + $1.utf8.count + 1 } }

    static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
