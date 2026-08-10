import Foundation

/// Streaming client for the Claude Messages API.
///
/// There is no official Anthropic SDK for Swift, so this speaks raw HTTP and
/// parses the SSE stream directly.
///
/// Claude Fable 5 specifics that shape this request:
///  - thinking is ALWAYS on. Sending `{"type":"disabled"}` is a 400; the only
///    valid forms are omitting the field or `{"type":"adaptive"}`. Depth is
///    controlled through `output_config.effort`, not a token budget —
///    `budget_tokens` is also a 400.
///  - `temperature` / `top_p` / `top_k` are rejected outright.
///  - the raw chain of thought is never returned. `display: "summarized"` gets a
///    readable summary, which is what feeds the panel's "thinking" line; the
///    default would stream empty thinking blocks and read as a dead pause.
///  - safety classifiers may decline a request with HTTP 200 and
///    `stop_reason: "refusal"`, so `stop_reason` has to be checked before the
///    content is treated as an answer.
final class ClaudeClient {

    enum Event {
        /// Summarized reasoning, shown as a progress line while the answer forms.
        case thinking(String)
        /// A chunk of the visible answer.
        case text(String)
    }

    enum ClientError: LocalizedError {
        case noCredentials
        case http(status: Int, message: String)
        case refused(String?)
        case transport(String)
        /// Already-diagnosed failure of the Claude Code CLI, shown verbatim —
        /// wrapping it in "нет связи с API" would contradict the diagnosis.
        case cli(String)

        var errorDescription: String? {
            switch self {
            case .noCredentials:
                return "Нет доступа к Claude — установите Claude Code (подписка) "
                    + "или введите ключ API в настройках CodeCoach"
            case .http(let status, let message):
                switch status {
                case 401: return "Ключ не принят (401) — проверьте его в настройках"
                case 403: return "Доступ запрещён (403) — нет прав на эту модель"
                case 429: return "Слишком много запросов (429) — подождите немного"
                case 400 where message.localizedCaseInsensitiveContains("retention"):
                    // Fable 5 requires 30-day retention and rejects every request
                    // from a zero-data-retention org, with a payload that looks fine.
                    return "Модель недоступна при нулевом хранении данных в организации (нужно 30 дней)"
                case 500...599: return "Сбой на стороне API (\(status)) — попробуйте ещё раз"
                default: return "Ошибка API (\(status)): \(message)"
                }
            case .refused(let explanation):
                return explanation.map { "Модель отклонила запрос: \($0)" }
                    ?? "Модель отклонила запрос по правилам безопасности"
            case .transport(let message):
                return "Нет связи с API: \(message)"
            case .cli(let message):
                return message
            }
        }
    }

    private let model = "claude-fable-5"
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        // Generous: a hard problem at high effort can think for a long while
        // before the first visible token. The per-resource timeout is what
        // actually bounds a stalled stream.
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 600
        session = URLSession(configuration: config)
    }

    /// Streams one level of help for one screenshot.
    ///
    /// Every level is an independent request carrying the same system prompt and
    /// the same image, and the image block is marked cacheable. That makes the
    /// shared prefix a cache hit on levels 2 and 3 — nearly free and much faster
    /// than re-reading the screenshot — while sidestepping the need to replay
    /// thinking blocks back into a multi-turn conversation.
    func stream(
        screenshotPNG: Data,
        level: HintLevel,
        language: String?,
        onEvent: @escaping (Event) -> Void
    ) async throws {
        guard let credential = Auth.resolve() else { throw ClientError.noCredentials }

        // Subscription path: the whole request runs through headless Claude
        // Code instead of the Messages API.
        guard case .apiKey(let apiKey) = credential else {
            Log.d("api: level \(level.rawValue) auth=\(credential.kind) -> claude code cli")
            return try await ClaudeCodeCLI.stream(
                screenshotPNG: screenshotPNG, level: level,
                language: language, onEvent: onEvent)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        // Opts into server-side fallbacks: on a policy decline the API re-runs
        // the same request on a recommended model instead of handing back a
        // refusal. Benign work occasionally trips the classifiers, and a single
        // failed hint mid-practice is exactly when that hurts.
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": level.maxTokens,
            "stream": true,
            "thinking": ["type": "adaptive", "display": "summarized"],
            "output_config": ["effort": level.effort],
            "fallbacks": "default",
            "system": [
                ["type": "text", "text": Prompts.system]
            ],
            "messages": [[
                "role": "user",
                "content": [
                    [
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": "image/png",
                            "data": screenshotPNG.base64EncodedString(),
                        ],
                        // Last block of the prefix shared by all three levels.
                        "cache_control": ["type": "ephemeral"],
                    ],
                    [
                        "type": "text",
                        "text": Prompts.instruction(
                            for: level, language: language,
                            seniority: Settings.shared.seniority,
                            codeOnly: Settings.shared.codeOnly),
                    ],
                ],
            ]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        Log.d("api: level \(level.rawValue) effort=\(level.effort) auth=\(credential.kind) image=\(screenshotPNG.count / 1024)KB")

        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            throw ClientError.transport(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var raw = Data()
            for try await byte in bytes { raw.append(byte) }
            throw ClientError.http(status: status, message: Self.errorMessage(from: raw))
        }

        var stopReason: String?
        var refusalExplanation: String?

        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard !payload.isEmpty,
                  let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String
            else { continue }

            switch type {
            case "content_block_delta":
                guard let delta = json["delta"] as? [String: Any] else { break }
                switch delta["type"] as? String {
                case "text_delta":
                    if let text = delta["text"] as? String, !text.isEmpty {
                        onEvent(.text(text))
                    }
                case "thinking_delta":
                    if let text = delta["thinking"] as? String, !text.isEmpty {
                        onEvent(.thinking(text))
                    }
                default:
                    break
                }

            case "message_delta":
                if let delta = json["delta"] as? [String: Any] {
                    stopReason = delta["stop_reason"] as? String ?? stopReason
                    if let details = delta["stop_details"] as? [String: Any] {
                        refusalExplanation = details["explanation"] as? String
                    }
                }

            case "error":
                let message = (json["error"] as? [String: Any])?["message"] as? String
                    ?? "неизвестная ошибка потока"
                throw ClientError.transport(message)

            default:
                break
            }
        }

        // Checked after the stream drains, not before reading content: a refusal
        // arrives as a successful response whose content is empty or partial.
        if stopReason == "refusal" {
            Log.d("api: refusal")
            throw ClientError.refused(refusalExplanation)
        }
        if stopReason == "max_tokens" {
            Log.d("api: hit max_tokens at level \(level.rawValue)")
        }
    }

    private static func errorMessage(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String
        else { return String(data: data, encoding: .utf8) ?? "" }
        return message
    }
}
