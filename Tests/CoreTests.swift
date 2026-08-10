import XCTest

final class HintLevelTests: XCTestCase {

    func testLadderIsOrderedAndTerminates() {
        XCTAssertEqual(HintLevel.nudge.next, .approach)
        XCTAssertEqual(HintLevel.approach.next, .solution)
        // The ladder must end. If .solution reported a next level, the controller
        // would keep promising more help and the panel badge would read "4/3".
        XCTAssertNil(HintLevel.solution.next)
        XCTAssertNil(HintLevel.nudge.previous)
        XCTAssertTrue(HintLevel.nudge < HintLevel.solution)
    }

    func testMaxTokensLeavesRoomForThinking() {
        // Fable 5 always thinks, and thinking is billed against the same
        // max_tokens as the answer. A ceiling sized only for the visible text
        // truncates the answer mid-sentence, so every rung needs real headroom.
        for level in HintLevel.allCases {
            XCTAssertGreaterThanOrEqual(level.maxTokens, 8_000, "level \(level.rawValue)")
        }
        XCTAssertGreaterThan(HintLevel.solution.maxTokens, HintLevel.nudge.maxTokens)
    }

    func testEffortIsAValidAPILevel() {
        // A value outside this set is a 400 from the API, and the failure would
        // only ever show up at runtime on a real keypress.
        let valid: Set<String> = ["low", "medium", "high", "xhigh", "max"]
        for level in HintLevel.allCases {
            XCTAssertTrue(valid.contains(level.effort), "level \(level.rawValue): \(level.effort)")
        }
    }

    func testBadgeShowsPositionInLadder() {
        XCTAssertEqual(HintLevel.nudge.badge, "Намёк · 1/3")
        XCTAssertEqual(HintLevel.solution.badge, "Решение · 3/3")
    }
}

final class PromptsTests: XCTestCase {

    func testEachLevelWithholdsWhatTheNextOneGives() {
        // The product IS this restraint: a level-1 prompt that permits code
        // turns the trainer into a cheat sheet.
        let nudge = Prompts.instruction(for: .nudge, language: nil)
        XCTAssertTrue(nudge.contains("ЗАПРЕЩЕНО"))
        XCTAssertTrue(nudge.localizedCaseInsensitiveContains("код"))

        let approach = Prompts.instruction(for: .approach, language: nil)
        XCTAssertTrue(approach.contains("ЗАПРЕЩЕНО"))

        // Only the last rung is allowed to hand over a solution.
        let solution = Prompts.instruction(for: .solution, language: nil)
        XCTAssertFalse(solution.contains("ЗАПРЕЩЕНО"))
    }

    func testLanguagePreferenceStillDefersToTheScreenshot() {
        let withLang = Prompts.instruction(for: .solution, language: "Python")
        XCTAssertTrue(withLang.contains("Python"))
        // A configured language must not override what is visibly on screen —
        // the user's editor is the ground truth during an exercise.
        XCTAssertTrue(withLang.localizedCaseInsensitiveContains("на экране"))

        let noLang = Prompts.instruction(for: .solution, language: nil)
        XCTAssertTrue(noLang.localizedCaseInsensitiveContains("скриншот"))
    }

    func testSeniorityShapesOnlyTheSolution() {
        // The ladder is the same at any grade — only the code register differs.
        // If seniority ever leaks into levels 1–2, the ladder's prohibitions
        // would need re-verification per grade; keep it contained.
        for s in Seniority.allCases {
            XCTAssertEqual(Prompts.instruction(for: .nudge, language: nil, seniority: s),
                           Prompts.instruction(for: .nudge, language: nil))
            XCTAssertEqual(Prompts.instruction(for: .approach, language: nil, seniority: s),
                           Prompts.instruction(for: .approach, language: nil))
        }

        // Each grade produces a distinct solution register, and every one of
        // them still demands complete working code.
        let variants = Seniority.allCases.map {
            Prompts.instruction(for: .solution, language: nil, seniority: $0)
        }
        XCTAssertEqual(Set(variants).count, Seniority.allCases.count)
        for v in variants {
            XCTAssertTrue(v.contains("Рабочий код целиком"))
        }
    }

    func testCodeOnlyStripsProseButKeepsTheLadderIntact() {
        // The code-only ask must not weaken the ladder: levels 1-2 are
        // unchanged, and the solution still demands complete working code.
        for s in Seniority.allCases {
            XCTAssertEqual(
                Prompts.instruction(for: .nudge, language: nil, seniority: s, codeOnly: true),
                Prompts.instruction(for: .nudge, language: nil, seniority: s))
            XCTAssertEqual(
                Prompts.instruction(for: .approach, language: nil, seniority: s, codeOnly: true),
                Prompts.instruction(for: .approach, language: nil, seniority: s))

            let solution = Prompts.instruction(
                for: .solution, language: nil, seniority: s, codeOnly: true)
            XCTAssertTrue(solution.contains("ТОЛЬКО КОД"), "grade \(s.rawValue)")
            XCTAssertTrue(solution.contains("рабочий код целиком")
                          || solution.contains("Рабочий код целиком"), "grade \(s.rawValue)")
            // The prose the flag exists to remove must actually be gone.
            XCTAssertFalse(solution.contains("интервьюер"), "grade \(s.rawValue)")
            // ...except the one allowed line: unexplained imports in pasted
            // code are a whiteboard question the user cannot answer.
            XCTAssertTrue(solution.contains("библиотек"), "grade \(s.rawValue)")
        }
    }

    func testSystemPromptCarriesNothingVolatile() {
        // The system prompt is the front of the cached prefix. A timestamp, a
        // uuid, or any per-request value here changes the bytes every call and
        // silently destroys the cache hit that makes levels 2 and 3 cheap.
        let system = Prompts.system
        XCTAssertFalse(system.contains("\(Calendar.current.component(.year, from: Date()))"))
        XCTAssertEqual(system, Prompts.system)
    }
}

final class AnswerFormatTests: XCTestCase {

    func testSplitsProseFromFencedCode() {
        let answer = """
        Держим два указателя.

        ```python
        def f(x):
            return x
        ```

        Сложность O(n).
        """
        let segments = AnswerFormat.segments(answer)
        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments[0].kind, .prose)
        XCTAssertEqual(segments[1].kind, .code(language: "python"))
        XCTAssertEqual(segments[2].kind, .prose)
    }

    func testCodeIndentationSurvives() {
        // Leading whitespace is structure in Python; trimming it would produce
        // code that does not run.
        let answer = "```python\ndef f():\n    return 1\n```"
        let segments = AnswerFormat.segments(answer)
        XCTAssertEqual(segments.first?.text, "def f():\n    return 1")
    }

    func testUnterminatedFenceStaysCode() {
        // The normal state while streaming. Treating a half-arrived block as
        // prose would flash it in the wrong style and then reflow it.
        let answer = "Вот решение:\n\n```python\ndef f():\n    ret"
        let segments = AnswerFormat.segments(answer)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[1].kind, .code(language: "python"))
    }

    func testFenceWithoutLanguage() {
        let segments = AnswerFormat.segments("```\nx = 1\n```")
        XCTAssertEqual(segments.first?.kind, .code(language: nil))
    }

    func testSummaryStripsMarkdownAndTruncates() {
        XCTAssertEqual(
            AnswerFormat.summary("**Задача:** найти пару чисел"),
            "Задача: найти пару чисел")

        let long = String(repeating: "а", count: 200)
        let summary = AnswerFormat.summary(long, limit: 20)
        XCTAssertTrue(summary.hasSuffix("…"))
        XCTAssertLessThanOrEqual(summary.count, 21)
    }

    func testSummaryOfCodeOnlyAnswerDoesNotCrash() {
        XCTAssertNoThrow(AnswerFormat.summary("```python\nx = 1\n```"))
    }
}

final class HistoryCodecTests: XCTestCase {

    func testEntriesSurviveAnEncodeDecodeRoundTrip() {
        // The regression this test pins down: persist() wrote ISO-8601 dates
        // while load() expected numeric timestamps, so every relaunch read an
        // empty history and the next write clobbered the real one.
        let entry = History.Entry(
            id: "test", date: Date(timeIntervalSince1970: 1_754_000_000),
            maxLevel: 3, answers: ["3": "```python\nx = 1\n```"],
            screenshotFile: "test.png")

        let data = try! History.makeEncoder().encode([entry])
        let decoded = try! History.makeDecoder().decode([History.Entry].self, from: data)

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].id, entry.id)
        XCTAssertEqual(decoded[0].date, entry.date)
        XCTAssertEqual(decoded[0].answers, entry.answers)
    }

    func testDecoderReadsTheOnDiskDateFormat() {
        // A sample of the actual on-disk format, so a strategy change on either
        // side of the codec fails loudly here instead of silently at launch.
        let json = """
        [{"id":"a","date":"2026-08-10T20:59:58Z","maxLevel":3,
          "answers":{"3":"code"},"screenshotFile":"a.png"}]
        """.data(using: .utf8)!
        let decoded = try? History.makeDecoder().decode([History.Entry].self, from: json)
        XCTAssertEqual(decoded?.count, 1)
    }
}

final class CLIErrorClassifierTests: XCTestCase {

    private func message(
        _ stderr: String, exit: Int32 = 1, subtype: String? = nil,
        timeZone: TimeZone = TimeZone(identifier: "UTC")!
    ) -> String {
        CLIErrorClassifier.message(
            exitCode: exit, stderr: stderr, subtype: subtype, timeZone: timeZone)
    }

    func testSubscriptionLimitIsNotReportedAsBeingLoggedOut() {
        // The regression this class exists for: on 2026-08-10 a one-off CLI
        // failure told a logged-in user to log in.
        let m = message("Claude AI usage limit reached")
        XCTAssertTrue(m.contains("Лимит подписки"), m)
        XCTAssertFalse(m.localizedCaseInsensitiveContains("claude login"), m)
    }

    func testLimitCarriesResetTimeWhenTheCLIGivesOne() {
        // The CLI's own format: message, pipe, unix timestamp.
        XCTAssertTrue(
            message("Claude AI usage limit reached|1754913600").contains("12:00"))
        XCTAssertTrue(
            message("Rate limit exceeded, resets at 5pm").contains("5pm"))
        // Without a time the sentence must still read cleanly.
        let plain = message("usage limit reached")
        XCTAssertFalse(plain.contains("("), plain)
    }

    func testNotLoggedIn() {
        for stderr in [
            "Invalid API key · Please run /login",
            "Error: not logged in",
            "request failed with status 401",
        ] {
            XCTAssertTrue(
                message(stderr).contains("не вошли в Claude Code"), stderr)
        }
    }

    func testNetwork() {
        for stderr in [
            "FetchError: request to https://api.anthropic.com failed, reason: getaddrinfo ENOTFOUND",
            "Error: connect ECONNREFUSED 127.0.0.1:443",
            "Request timed out",
        ] {
            XCTAssertTrue(message(stderr).contains("Нет связи с Claude"), stderr)
        }
    }

    func testUnknownFailureShowsTheRealStderrOnOneLine() {
        // Anything unrecognized must reach the user as-is. A friendly guess here
        // is exactly what sent the owner debugging a login that was fine.
        let m = message("TypeError: cannot read property 'x'\n    at foo.js:12\n    at bar.js:3")
        XCTAssertTrue(m.contains("TypeError: cannot read property 'x' at foo.js:12"), m)
        XCTAssertFalse(m.contains("\n"), m)
    }

    func testLongStderrIsTruncatedAndAnsiCodesStripped() {
        let m = message("\u{1B}[31mError:\u{1B}[0m " + String(repeating: "z", count: 500))
        XCTAssertFalse(m.contains("\u{1B}"))
        XCTAssertTrue(m.hasSuffix("…"))
        XCTAssertLessThan(m.count, CLIErrorClassifier.snippetLimit + 40)
    }

    func testEmptyStderrFallsBackToSubtypeThenExitCode() {
        XCTAssertTrue(
            message("", subtype: "error_max_turns").contains("error_max_turns"))
        XCTAssertTrue(message("   \n ", exit: 137).contains("137"))
    }

    func testSubtypeAloneCanIdentifyTheCause() {
        // Some failures surface only in the JSON result, with stderr empty.
        XCTAssertTrue(
            message("", subtype: "error_rate_limit").contains("Лимит подписки"))
    }

    func testLogExcerptIsShortAndSingleLine() {
        let excerpt = CLIErrorClassifier.logExcerpt(
            String(repeating: "line of noise\n", count: 40))
        XCTAssertFalse(excerpt.contains("\n"))
        XCTAssertLessThanOrEqual(excerpt.count, CLIErrorClassifier.logLimit + 1)
    }
}

final class KeyNamesTests: XCTestCase {

    func testLeftAndRightModifiersAreDistinct() {
        // Same flag, different keycodes. Conflating them is what makes a user
        // press "the other Option" and conclude the app is broken.
        XCTAssertNotEqual(KeyNames.name(for: 54), KeyNames.name(for: 55))
        XCTAssertTrue(KeyNames.name(for: 54).contains("Right"))
        XCTAssertTrue(KeyNames.name(for: 61).contains("Right"))
    }

    func testDefaultHotkeyDoesNotCollideWithDictate() {
        // Dictate's push-to-talk default is right Option (61). Sharing it would
        // fire a screenshot and a dictation on the same press.
        XCTAssertNotEqual(Settings.defaultHotkeyKeyCode, 61)
        XCTAssertEqual(Settings.defaultHotkeyKeyCode, 54)
    }

    func testOnlyPlainKeysTypeCharacters() {
        // A listen-only tap cannot swallow the keystroke, so a plain key as the
        // hotkey types into whatever has focus. Modifiers and F-keys do not.
        XCTAssertFalse(KeyNames.typesCharacters(54))   // right ⌘
        XCTAssertFalse(KeyNames.typesCharacters(122))  // F1
        XCTAssertTrue(KeyNames.typesCharacters(0))     // "a"
    }
}
