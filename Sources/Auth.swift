import Foundation

/// Resolves how the next request will authenticate.
///
/// Two ways in, checked in this order:
///  1. An API key in `~/.config/codecoach/api-key` — the explicit in-app
///     choice, so it wins when both are configured. Requests go straight to
///     the Messages API with `x-api-key`.
///  2. The user's Claude subscription, via headless Claude Code (`claude -p`,
///     see ClaudeCodeCLI). A subscription cannot call the Messages API
///     directly — Console OAuth (`ant auth login`) is a separate, API-billing
///     account, which is exactly the confusing flow this path avoids.
enum Auth {

    enum Credential {
        case apiKey(String)
        case claudeCode

        /// For logs only — never the secret itself.
        var kind: String {
            switch self {
            case .apiKey: return "key"
            case .claudeCode: return "claude-code"
            }
        }
    }

    /// Whether a hotkey press has any chance of producing a hint. Cheap
    /// on-disk checks only; whether Claude Code is actually logged in is
    /// discovered by the request itself.
    static var anySourceAvailable: Bool {
        Settings.shared.apiKey != nil || ClaudeCodeCLI.installed
    }

    static func resolve() -> Credential? {
        if let key = Settings.shared.apiKey { return .apiKey(key) }
        if ClaudeCodeCLI.installed { return .claudeCode }
        return nil
    }
}
