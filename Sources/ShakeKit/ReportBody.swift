import Foundation

/// The parts ShakeKit adds below what the person wrote: the app and device,
/// and the app's recent logs, redacted and capped.
public enum ReportBody {
    /// What blanks anything that looks like a token, an email address or a
    /// URL's query string, before the logs leave the device.
    static let builtInRedactions: [String] = [
        // GitHub tokens, and bearer or token authorizations.
        #"\b(gh[opusr]_|github_pat_)[A-Za-z0-9_]{10,}"#,
        #"(?i)\b(bearer|token)\s+[A-Za-z0-9._~+/=-]{16,}"#,
        // Email addresses.
        #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,
        // A URL's query string, kept up to the "?".
        #"(?<=\?)[^\s"'<>]+"#,
    ]

    /// `text` with everything `patterns` and the built-in rules match
    /// replaced by `<redacted>`.
    public static func redacted(_ text: String, extra patterns: [String] = []) -> String {
        var result = text
        for pattern in builtInRedactions + patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = expression.stringByReplacingMatches(in: result, range: range, withTemplate: "<redacted>")
        }
        return result
    }

    /// The last `limit` characters of `lines` joined, cut at a line start.
    static func newest(_ lines: [String], limit: Int) -> (text: String, dropped: Int) {
        var kept: [String] = []
        var count = 0
        for line in lines.reversed() {
            let cost = line.count + 1
            if count + cost > limit { break }
            kept.append(line)
            count += cost
        }
        return (kept.reversed().joined(separator: "\n"), lines.count - kept.count)
    }

    /// The logs, redacted, capped at `limit` characters, folded in a
    /// `<details>` block; nil with none.
    public static func logs(_ lines: [String], limit: Int, redactions: [String] = []) -> String? {
        guard !lines.isEmpty else { return nil }
        let safe = lines.map { redacted($0, extra: redactions) }
        let (text, dropped) = newest(safe, limit: limit)
        let note = dropped > 0 ? " (the last \(safe.count - dropped) of \(safe.count) lines)" : ""
        // A fence the logs can't close early.
        let fence = text.contains("```") ? "~~~~" : "```"
        return """
            <details><summary>Logs\(note)</summary>

            \(fence)
            \(text)
            \(fence)

            </details>
            """
    }

    /// What the person wrote, then the app and device, then the logs.
    public static func compose(written: String, environment: ReportEnvironment, logs: String?) -> String {
        var parts = [written.trimmingCharacters(in: .whitespacesAndNewlines)].filter { !$0.isEmpty }
        parts.append(environment.markdown)
        if let logs { parts.append(logs) }
        return parts.joined(separator: "\n\n") + "\n"
    }
}
