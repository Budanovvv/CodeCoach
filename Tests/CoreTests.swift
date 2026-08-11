import XCTest

final class HintLevelTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Assertions below are written against the Russian base strings; on an
        // English-system CI they would otherwise test the translation tables.
        Localization.shared.setLanguage(.ru)
    }

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
        XCTAssertTrue(nudge.contains("FORBIDDEN"))
        XCTAssertTrue(nudge.localizedCaseInsensitiveContains("code"))

        let approach = Prompts.instruction(for: .approach, language: nil)
        XCTAssertTrue(approach.contains("FORBIDDEN"))

        // Only the last rung is allowed to hand over a solution.
        let solution = Prompts.instruction(for: .solution, language: nil)
        XCTAssertFalse(solution.contains("FORBIDDEN"))
    }

    func testLanguagePreferenceStillDefersToTheScreenshot() {
        let withLang = Prompts.instruction(for: .solution, language: "Python")
        XCTAssertTrue(withLang.contains("Python"))
        // A configured language must not override what is visibly on screen —
        // the user's editor is the ground truth during an exercise.
        XCTAssertTrue(withLang.localizedCaseInsensitiveContains("on screen"))

        let noLang = Prompts.instruction(for: .solution, language: nil)
        XCTAssertTrue(noLang.localizedCaseInsensitiveContains("screenshot"))
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
            XCTAssertTrue(v.contains("working code in full"))
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
            XCTAssertTrue(solution.contains("CODE ONLY"), "grade \(s.rawValue)")
            XCTAssertTrue(solution.localizedCaseInsensitiveContains("working code in full"), "grade \(s.rawValue)")
            // The prose the flag exists to remove must actually be gone.
            XCTAssertFalse(solution.contains("interviewer"), "grade \(s.rawValue)")
            // ...except the one allowed line: unexplained imports in pasted
            // code are a whiteboard question the user cannot answer.
            XCTAssertTrue(solution.contains("libraries"), "grade \(s.rawValue)")
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

final class LocalizationTests: XCTestCase {

    func testEveryTableEntryIsNonEmpty() {
        for (key, value) in Localization.ru {
            XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty, "ru: \(key)")
        }
        for (key, value) in Localization.uk {
            XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty, "uk: \(key)")
        }
    }

    func testFormatPlaceholdersSurviveTranslation() {
        // A dropped %@ or %d in a translation would crash String(format:) or
        // silently swallow the argument. Both tables must keep every
        // placeholder of their key.
        for table in [Localization.ru, Localization.uk] {
            for (key, value) in table {
                for marker in ["%@", "%d"] {
                    XCTAssertEqual(
                        key.components(separatedBy: marker).count,
                        value.components(separatedBy: marker).count,
                        "placeholder \(marker) mismatch for: \(key)")
                }
            }
        }
    }

    func testSystemPromptsFollowTheAnswerLanguage() {
        // Both system prompts must carry the language rule — this is the whole
        // "one setting drives the prompts too" contract. The rule text itself
        // stays Russian scaffolding; what varies is which language it demands.
        XCTAssertTrue(Prompts.system.contains(Localization.shared.answerRule))
        XCTAssertTrue(TrainerPrompts.system(age: nil).contains(Localization.shared.answerRule))
    }

    func testMachineMarkersStayEnglishInEveryLanguage() {
        // The verdict and title markers are parsed by code, so the prompts pin
        // them to the exact English spelling regardless of answer language.
        XCTAssertTrue(TrainerPrompts.review(taskText: "t", code: "c").contains("VERDICT:"))
        XCTAssertTrue(TrainerPrompts
            .generateTask(topic: .strings, level: .started, avoidTitles: [])
            .contains("TITLE:"))
    }
}

final class TrainerTests: XCTestCase {

    func testVerdictParsing() {
        XCTAssertEqual(Trainer.parseVerdict(from: "Молодец!\nVERDICT: solved"), .solved)
        XCTAssertEqual(Trainer.parseVerdict(from: "Есть ошибка.\n VERDICT: partial "), .partial)
        XCTAssertEqual(Trainer.parseVerdict(from: "VERDICT: not solved"), .failed)
        // The word appearing mid-explanation must not confuse the parser —
        // only the last ИТОГ line counts.
        XCTAssertEqual(
            Trainer.parseVerdict(from: "The previous VERDICT: solved was wrong.\nVERDICT: partial"),
            .partial)
        XCTAssertNil(Trainer.parseVerdict(from: "no verdict at all"))
    }

    func testMapUpdateRules() {
        var profile = Trainer.Profile()
        profile.set(.strings, to: .started)

        // Solved lifts one rung; a partial attempt does not move the level.
        let up = Trainer.updated(profile, topic: .strings, verdict: .solved, gaveUp: false)
        XCTAssertEqual(up.level(of: .strings), .confident)
        let same = Trainer.updated(profile, topic: .strings, verdict: .partial, gaveUp: false)
        XCTAssertEqual(same.level(of: .strings), .started)

        // Giving up drops one rung and wins over any verdict; both directions clamp.
        let down = Trainer.updated(profile, topic: .strings, verdict: .solved, gaveUp: true)
        XCTAssertEqual(down.level(of: .strings), .notStarted)
        let floor = Trainer.updated(down, topic: .strings, verdict: .failed, gaveUp: true)
        XCTAssertEqual(floor.level(of: .strings), .notStarted)
        var top = Trainer.Profile()
        top.set(.strings, to: .mastered)
        XCTAssertEqual(
            Trainer.updated(top, topic: .strings, verdict: .solved, gaveUp: false)
                .level(of: .strings), .mastered)
    }

    func testNextTopicPicksTheWeakest() {
        var profile = Trainer.Profile()
        for topic in Trainer.Topic.allCases { profile.set(topic, to: .confident) }
        profile.set(.dictsAndSets, to: .notStarted)
        XCTAssertEqual(Trainer.nextTopic(for: profile), .dictsAndSets)

        // Everything mastered: keep training the last topic rather than crash.
        for topic in Trainer.Topic.allCases { profile.set(topic, to: .mastered) }
        XCTAssertEqual(Trainer.nextTopic(for: profile), .oop)
    }

    func testProbeCoversDistinctCoreTopics() {
        XCTAssertEqual(Trainer.probeTopics.count, 5)
        XCTAssertEqual(Set(Trainer.probeTopics).count, 5)
    }

    func testTrainerPromptsKeepTheLadderDiscipline() {
        // Review must demand a machine-readable verdict and refuse to hand the
        // solution over; the hint must forbid code. Same product rule as the
        // interview ladder, and more load-bearing for a learner.
        let review = TrainerPrompts.review(taskText: "задача", code: "print(1)")
        XCTAssertTrue(review.contains("VERDICT:"))
        XCTAssertTrue(review.contains("FORBIDDEN"))
        XCTAssertTrue(review.contains("print(1)"))

        let hint = TrainerPrompts.hint(taskText: "задача")
        XCTAssertTrue(hint.contains("FORBIDDEN"))

        // Task generation must not leak a solution either.
        let task = TrainerPrompts.generateTask(topic: .strings, level: .started, avoidTitles: [])
        XCTAssertTrue(task.contains("NO solution"))
        XCTAssertTrue(task.contains("TITLE:"))

        // Nothing volatile in the system prompt (it is the cacheable prefix),
        // and every age register produces its own distinct stable prompt.
        for age in [nil] + Trainer.AgeBand.allCases.map(Optional.some) {
            XCTAssertEqual(TrainerPrompts.system(age: age), TrainerPrompts.system(age: age))
        }
        XCTAssertNotEqual(TrainerPrompts.system(age: .child), TrainerPrompts.system(age: .adult))
    }

    func testOnboardingShapesTheProbeButTheProbeWins() {
        // Size: a never-coder gets a shorter probe; everyone else the full one.
        XCTAssertEqual(Trainer.probeTopics(for: .never).count, 3)
        XCTAssertEqual(Trainer.probeTopics(for: .experienced).count, 5)
        XCTAssertEqual(Trainer.probeTopics(for: nil).count, 5)

        // Seed difficulty and priors follow the claim…
        XCTAssertEqual(Trainer.probeSeedLevel(for: .never), .notStarted)
        XCTAssertEqual(Trainer.probeSeedLevel(for: .experienced), .confident)
        XCTAssertEqual(Trainer.priorLevel(for: .experienced), .confident)
        XCTAssertEqual(Trainer.priorLevel(for: nil), .notStarted)

        // …but the surprise detector reports when behaviour disagrees, in
        // either direction, and stays quiet without a claim to compare against.
        let aced: [Trainer.Topic: Trainer.Verdict] = [
            .strings: .solved, .functions: .solved, .listsAndTuples: .solved,
        ]
        let bombed: [Trainer.Topic: Trainer.Verdict] = [
            .strings: .failed, .functions: .failed, .listsAndTuples: .failed,
        ]
        XCTAssertEqual(Trainer.probeSurprise(selfLevel: .never, verdicts: aced), .higher)
        XCTAssertEqual(Trainer.probeSurprise(selfLevel: .experienced, verdicts: bombed), .lower)
        XCTAssertEqual(Trainer.probeSurprise(selfLevel: .basics, verdicts: [
            .strings: .partial, .functions: .partial, .listsAndTuples: .solved,
        ]), .asExpected)
        XCTAssertEqual(Trainer.probeSurprise(selfLevel: nil, verdicts: aced), .asExpected)
    }

    func testOldProfileJSONStillDecodes() {
        // Profiles written before onboarding existed have none of the new
        // fields; they must decode and skip onboarding iff the probe ran.
        let json = """
        [{"probeDone":true,"map":{"strings":2},"solved":[]}]
        """.data(using: .utf8)!
        let decoded = try? History.makeDecoder().decode([Trainer.Profile].self, from: json)
        XCTAssertEqual(decoded?.first?.probeDone, true)
        XCTAssertEqual(decoded?.first?.needsOnboarding, false)
        XCTAssertNil(decoded?.first?.ageBand)

        var fresh = Trainer.Profile()
        XCTAssertTrue(fresh.needsOnboarding)
        fresh.onboardingDone = true
        XCTAssertFalse(fresh.needsOnboarding)
    }

    func testProfileSurvivesRoundTrip() {
        var profile = Trainer.Profile()
        profile.probeDone = true
        profile.set(.loopsTopicForTest, to: .confident)
        profile.solved.append(Trainer.SolvedTask(
            topic: .strings, title: "Шифр", date: Date(timeIntervalSince1970: 1_754_000_000),
            verdict: "решено"))

        let data = try! History.makeEncoder().encode(profile)
        let decoded = try! History.makeDecoder().decode(Trainer.Profile.self, from: data)
        XCTAssertEqual(decoded.probeDone, true)
        XCTAssertEqual(decoded.level(of: .loopsTopicForTest), .confident)
        XCTAssertEqual(decoded.solved.first?.title, "Шифр")
    }
}

private extension Trainer.Topic {
    /// Alias so the test reads naturally without repeating the raw case name.
    static let loopsTopicForTest = Trainer.Topic.conditionsAndLoops
}

final class UserLevelTests: XCTestCase {
    /// Every step must land on some register and some trainer level — the
    /// switch statements guarantee it, this guards against a new case being
    /// added to one mapping and forgotten in the other.
    func testEveryLevelMapsToBothSurfaces() {
        for level in UserLevel.allCases {
            _ = level.seniority
            _ = level.trainerLevel
        }
    }

    func testLearnersGetJuniorRegister() {
        XCTAssertEqual(UserLevel.beginner.seniority, .junior)
        XCTAssertEqual(UserLevel.basics.seniority, .junior)
        XCTAssertEqual(UserLevel.confident.seniority, .middle)
        XCTAssertEqual(UserLevel.pro.seniority, .senior)
    }

    func testTrainerLevelRoundTrips() {
        for level in UserLevel.allCases {
            XCTAssertEqual(UserLevel(trainerLevel: level.trainerLevel), level)
        }
    }

    /// Seniority migration is lossy by design (3 → 4 steps), but must stay
    /// stable: migrating and mapping back yields the original register.
    func testSeniorityMigrationPreservesRegister() {
        for old in Seniority.allCases {
            XCTAssertEqual(UserLevel(seniority: old).seniority, old)
        }
    }
}

final class CodeAssistTests: XCTestCase {

    func testCompletionsMixDictionaryAndDocumentWords() {
        let doc = "score_total = 0\nfor letter in word:\n    pri"
        let hits = CodeAssist.completions(for: "pri", document: doc)
        XCTAssertTrue(hits.contains("print"))
        // The half-typed word itself must not offer to complete itself.
        XCTAssertFalse(hits.contains("pri"))

        // Identifiers from the learner's own code and from the task statement
        // complete too — those are the names they are about to retype.
        let fromDoc = CodeAssist.completions(for: "sco", document: doc)
        XCTAssertTrue(fromDoc.contains("score_total"))
        let fromTask = CodeAssist.completions(
            for: "pla", document: "", context: "напиши функцию playlist_length")
        XCTAssertTrue(fromTask.contains("playlist_length"))

        // One character is too little signal to pop a list over.
        XCTAssertTrue(CodeAssist.completions(for: "p", document: doc).isEmpty)
    }

    func testIndentationFollowsPythonRules() {
        XCTAssertEqual(CodeAssist.indentation(afterLine: "def f():"), "    ")
        XCTAssertEqual(CodeAssist.indentation(afterLine: "    if x > 0:"), "        ")
        XCTAssertEqual(CodeAssist.indentation(afterLine: "    x = 1"), "    ")
        XCTAssertEqual(CodeAssist.indentation(afterLine: "x = 1"), "")
        // A colon hiding in a comment must not indent; a real colon with a
        // trailing comment must.
        XCTAssertEqual(CodeAssist.indentation(afterLine: "x = 1  # not a block:"), "")
        XCTAssertEqual(CodeAssist.indentation(afterLine: "for i in y:  # loop"), "    ")
    }

    func testAutoCloseOnlyAtBoundaries() {
        XCTAssertTrue(CodeAssist.shouldAutoClose(opening: "(", nextChar: nil))
        XCTAssertTrue(CodeAssist.shouldAutoClose(opening: "\"", nextChar: " "))
        XCTAssertTrue(CodeAssist.shouldAutoClose(opening: "[", nextChar: ")"))
        // Mid-word auto-closing is how `it's` becomes `it''s`.
        XCTAssertFalse(CodeAssist.shouldAutoClose(opening: "'", nextChar: "s"))
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

    override func setUp() {
        super.setUp()
        // Assertions below are written against the Russian base strings; on an
        // English-system CI they would otherwise test the translation tables.
        Localization.shared.setLanguage(.ru)
    }

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
