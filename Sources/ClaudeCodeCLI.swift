import Foundation

/// Runs one hint level through headless Claude Code (`claude -p`), which is
/// authorized by the user's Claude subscription — no API key involved. This is
/// the same mechanism the Claude Agent SDK uses, so subscription usage is the
/// sanctioned path, unlike raw Messages-API calls with a subscription token.
///
/// The screenshot goes in the first user message as a base64 image block via
/// `--input-format stream-json`. The first implementation wrote it to a temp
/// file and had the model fetch it with the Read tool — that cost a whole
/// extra model round-trip and roughly doubled the latency of a nudge.
/// Each level is an independent invocation with its own model (HintLevel
/// .cliModel), mirroring the HTTP client's independent-request design.
enum ClaudeCodeCLI {

    /// GUI apps launch with a minimal PATH, so the usual install locations are
    /// checked explicitly.
    private static let binaryPaths = [
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        NSHomeDirectory() + "/.claude/local/claude",
        NSHomeDirectory() + "/.local/bin/claude",
    ]

    static var binary: String? {
        binaryPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var installed: Bool { binary != nil }

    static func stream(
        screenshotPNG: Data,
        level: HintLevel,
        language: String?,
        onEvent: @escaping (ClaudeClient.Event) -> Void
    ) async throws {
        guard let bin = binary else { throw ClaudeClient.ClientError.noCredentials }

        let prompt = "Условие задачи — на приложенном скриншоте. Отвечай сразу по делу; "
            + "не используй инструменты и не комментируй чтение изображения.\n\n"
            + Prompts.instruction(
                for: level, language: language, seniority: Settings.shared.seniority,
                codeOnly: Settings.shared.codeOnly)

        let message: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": [
                    [
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": "image/png",
                            "data": screenshotPNG.base64EncodedString(),
                        ],
                    ],
                    ["type": "text", "text": prompt],
                ],
            ],
        ]
        var input = try JSONSerialization.data(withJSONObject: message)
        input.append(0x0A)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: bin)
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.arguments = [
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--include-partial-messages",
            "--verbose",
            "--model", level.cliModel,
            // No tools are needed (the image is inline); 2 turns so that even a
            // stray denied tool call still leaves room for an answer turn.
            "--max-turns", "2",
            "--system-prompt", Prompts.system,
        ]
        // The subscription must be the auth source even if a key is exported
        // somewhere in the user's shell profile.
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "ANTHROPIC_API_KEY")
        process.environment = env

        let stdin = Pipe()
        let stdout = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderrPipe

        Log.d("cli: level \(level.rawValue) start model=\(level.cliModel) image=\(screenshotPNG.count / 1024)KB")
        try process.run()

        // Fed off this task so a full stdin pipe can never deadlock against
        // the stdout read loop below.
        Task.detached {
            try? stdin.fileHandleForWriting.write(contentsOf: input)
            try? stdin.fileHandleForWriting.close()
        }

        // stderr is drained on its own task for the same reason, and this is the
        // whole point of the change: a pipe nobody reads fills at ~64KB and then
        // blocks the child mid-write, so it cannot be collected after the fact.
        // The task ends by itself at EOF (process exit or terminate), which is
        // why the cancellation path does not have to wait for it.
        let cap = 16 * 1024
        let stderrTask = Task<String, Never>.detached {
            let handle = stderrPipe.fileHandleForReading
            var collected = Data()
            while let chunk = try? handle.read(upToCount: 4096), !chunk.isEmpty {
                // Keep reading after the cap so the pipe still drains; only the
                // head is kept, and that is all the classifier and log use.
                if collected.count < cap { collected.append(chunk) }
            }
            return String(decoding: collected, as: UTF8.self)
        }

        try await withTaskCancellationHandler {
            var sawText = false
            var failedSubtype: String?

            for try await line in stdout.fileHandleForReading.bytes.lines {
                try Task.checkCancellation()
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = json["type"] as? String
                else { continue }

                switch type {
                case "stream_event":
                    guard let event = json["event"] as? [String: Any],
                          event["type"] as? String == "content_block_delta",
                          let delta = event["delta"] as? [String: Any]
                    else { break }
                    switch delta["type"] as? String {
                    case "text_delta":
                        if let text = delta["text"] as? String, !text.isEmpty {
                            sawText = true
                            onEvent(.text(text))
                        }
                    case "thinking_delta":
                        if let text = delta["thinking"] as? String, !text.isEmpty {
                            onEvent(.thinking(text))
                        }
                    default:
                        break
                    }

                case "result":
                    let subtype = json["subtype"] as? String ?? ""
                    if subtype != "success" {
                        // Recorded, not thrown: the reason lives in stderr, and
                        // stderr is only complete once the process has exited.
                        // Draining stdout to EOF also keeps the child from
                        // blocking on a write while we walk away.
                        failedSubtype = subtype
                    } else if !sawText, let text = json["result"] as? String, !text.isEmpty {
                        // Belt and braces: if partial deltas never arrived (older
                        // CLI, changed flag), the final text still reaches the panel.
                        onEvent(.text(text))
                    }

                default:
                    break
                }
            }

            process.waitUntilExit()
            let exitCode = process.terminationStatus
            guard exitCode == 0, failedSubtype == nil else {
                let stderrText = await stderrTask.value
                Log.d("cli: exit \(exitCode) subtype=\(failedSubtype ?? "-") "
                    + "stderr=\(CLIErrorClassifier.logExcerpt(stderrText))")
                throw ClaudeClient.ClientError.cli(
                    CLIErrorClassifier.message(
                        exitCode: exitCode, stderr: stderrText, subtype: failedSubtype))
            }
            Log.d("cli: level \(level.rawValue) done")
        } onCancel: {
            // Ends the stream (the pipe closes), which unwinds the read loop.
            process.terminate()
        }
    }
}
