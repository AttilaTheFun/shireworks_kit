import Foundation

/// What is blanked out of text an app puts in an issue (its logs, a crash's
/// details) before it leaves the device: anything that looks like a token,
/// an email address or a URL's query string, and the host's own patterns.
public enum IssueRedaction {
    /// The rules every redaction applies, as regular expressions.
    public static let builtIn: [String] = [
        // GitHub tokens, and bearer or token authorizations.
        #"\b(gh[opusr]_|github_pat_)[A-Za-z0-9_]{10,}"#,
        #"(?i)\b(bearer|token)\s+[A-Za-z0-9._~+/=-]{16,}"#,
        // Email addresses.
        #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,
        // A URL's query string, kept up to the "?".
        #"(?<=\?)[^\s"'<>]+"#,
    ]

    /// `text` with everything `patterns` and the built-in rules match
    /// replaced by `<redacted>`. A pattern that isn't a regular expression
    /// is skipped.
    public static func redacted(_ text: String, extra patterns: [String] = []) -> String {
        var result = text
        for pattern in builtIn + patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = expression.stringByReplacingMatches(in: result, range: range, withTemplate: "<redacted>")
        }
        return result
    }
}
