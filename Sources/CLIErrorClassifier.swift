import Foundation

/// Turns a failed `claude -p` run into a message the user can act on.
///
/// This exists because the first version guessed: any non-zero exit produced
/// "проверьте, что вы вошли в Claude Code". On 2026-08-10 the CLI failed once
/// mid-practice while the owner was perfectly well logged in, and the guess
/// sent him hunting for a problem that was not there. A wrong diagnosis is
/// worse than no diagnosis, so the real stderr decides now — and when nothing
/// matches, the raw text is shown rather than replaced by a story about it.
///
/// Pure and free of AppKit on purpose: it is compiled into the test target.
enum CLIErrorClassifier {

    /// Longest stderr excerpt shown to the user when no known cause matches.
    static let snippetLimit = 200
    /// Longest stderr excerpt written to the debug log.
    static let logLimit = 120

    /// - Parameters:
    ///   - exitCode: process termination status (0 when the CLI exited cleanly
    ///     but reported a non-success result).
    ///   - stderr: everything the process wrote to stderr.
    ///   - subtype: `subtype` of the CLI's final `result` event, if one arrived.
    ///   - timeZone: injectable so the reset time is testable; callers use local.
    static func message(
        exitCode: Int32,
        stderr: String,
        subtype: String?,
        timeZone: TimeZone = .current
    ) -> String {
        // The result subtype is part of the evidence: "error_during_execution"
        // carries no words of its own, but a limit hit sometimes surfaces only
        // in the JSON result while stderr stays empty.
        let haystack = (stderr + " " + (subtype ?? "")).lowercased()

        if contains(haystack, Self.limitMarkers) || hasStatus(haystack, 429) {
            let base = L("Claude subscription limit reached — try later")
            guard let reset = resetTime(in: stderr, timeZone: timeZone) else { return base }
            return base + LF(" (resets at %@)", reset)
        }
        if contains(haystack, Self.authMarkers) || hasStatus(haystack, 401) {
            return L("You are not logged into Claude Code — run claude login in a terminal")
        }
        if contains(haystack, Self.networkMarkers) {
            return L("Cannot reach Claude — check your connection")
        }

        // Nothing recognized: show what actually happened. Guessing here is the
        // bug this file was written to fix.
        let snippet = singleLine(stderr, limit: snippetLimit)
        if !snippet.isEmpty { return "Claude Code: \(snippet)" }
        if let subtype, subtype != "success", !subtype.isEmpty {
            return LF("Claude Code finished without an answer (%@)", subtype)
        }
        return LF("Claude Code failed (code %d)", exitCode)
    }

    /// stderr excerpt for `Log.d`. Safe under the project's privacy rule: the
    /// CLI writes diagnostics here, never the problem text or the answer.
    static func logExcerpt(_ stderr: String) -> String {
        singleLine(stderr, limit: logLimit)
    }

    // Checked before the auth markers: "Claude AI usage limit reached" is the
    // one failure users are most likely to misread as being logged out.
    private static let limitMarkers = [
        "usage limit", "rate limit", "rate_limit", "limit reached",
        "quota", "out of credits", "insufficient credits",
    ]

    private static let authMarkers = [
        "invalid api key", "not logged in", "please run /login", "/login",
        "unauthorized", "authentication_error", "authentication failed",
        "no credentials", "log in to claude",
    ]

    private static let networkMarkers = [
        "network", "connection", "econnrefused", "econnreset", "enotfound",
        "etimedout", "getaddrinfo", "socket hang up", "timeout", "timed out",
        "offline", "dns", "proxy",
    ]

    private static func contains(_ haystack: String, _ markers: [String]) -> Bool {
        markers.contains { haystack.contains($0) }
    }

    /// HTTP status as a standalone number. A bare substring search would match
    /// the "401" inside any unix timestamp or request id that happens to hold it.
    private static func hasStatus(_ haystack: String, _ status: Int) -> Bool {
        firstMatch(haystack, pattern: "(?<![0-9])\(status)(?![0-9])", group: 0) != nil
    }

    /// Collapses whitespace and strips ANSI colour codes so a multi-line, styled
    /// stack trace still fits one line of the hint panel.
    static func singleLine(_ text: String, limit: Int) -> String {
        var s = replacing(text, pattern: "\u{1B}\\[[0-9;?]*[a-zA-Z]", with: "")
        s = replacing(s, pattern: "\\s+", with: " ")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count > limit else { return s }
        return String(s.prefix(limit)) + "…"
    }

    /// The CLI reports a limit reset as a unix timestamp ("Claude AI usage limit
    /// reached|1754870400"); older builds spell it out in words instead.
    private static func resetTime(in stderr: String, timeZone: TimeZone) -> String? {
        if let epoch = firstMatch(stderr, pattern: "\\b(1[0-9]{9})\\b", group: 1),
           let seconds = TimeInterval(epoch) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: Date(timeIntervalSince1970: seconds))
        }
        if let spelled = firstMatch(
            stderr,
            pattern: "(?i)reset[s]?\\s+(?:at|in)\\s+([^\\n.,;]{1,24})",
            group: 1
        ) {
            return spelled.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func firstMatch(_ text: String, pattern: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let found = Range(match.range(at: group), in: text)
        else { return nil }
        return String(text[found])
    }

    private static func replacing(_ text: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(
            in: text, range: range, withTemplate: template)
    }
}
