import Foundation

/// How the level-3 solution should be written. The same problem wants
/// different code at different grades — an interviewer reads a junior's
/// straightforward loop and a senior's invariant-heavy solution differently,
/// and training against the wrong register is training for the wrong interview.
enum Seniority: String, CaseIterable {
    case junior, middle, senior

    var title: String {
        switch self {
        case .junior: return L("Junior")
        case .middle: return L("Middle")
        case .senior: return L("Senior")
        }
    }
}

/// Prompt text for the trainer. Kept in one place because this — not the
/// plumbing — is the product: the difference between a useful trainer and a
/// cheat sheet is entirely in what the system prompt refuses to hand over.
/// The scaffolding is English (the base language); the model's answer language
/// comes from the injected rule and follows the app-language setting.
enum Prompts {

    /// Stable across every request in a session, so it sits at the front of the
    /// prefix and stays cacheable. Nothing volatile (no timestamps, no ids) may
    /// be interpolated into it — the answer-language rule is stable for as long
    /// as the language setting is.
    static var system: String { """
    You are a trainer for algorithmic problems. The user is preparing for \
    technical interviews and sends a screenshot with the problem statement. \
    Your job is to lead them to solving it themselves, not to hand over the \
    answer.

    General rules:
    - \(Localization.shared.answerRule) Data-structure and algorithm names, and \
    all code, stay in English, as the industry writes them.
    - The answer is read in a small window under the menu bar. Write densely: \
    no preamble, no "great question", no restating what was already said.
    - Code always goes in triple backticks with a language tag.
    - If no problem statement is visible on the screenshot, say so in one line \
    and suggest capturing the screen again — do not invent a problem.
    - If SEVERAL problem statements are visible (a neighbouring tab, a second \
    window), work on the one in the foreground window — it is fully visible and \
    not occluded. Name the problem you are solving in the first line, so the \
    user immediately notices a wrong pick.
    - If the screenshot shows the user already writing code, take their approach \
    into account: point at concrete mistakes in it rather than proposing to \
    start over.

    You receive a request for one of three levels and must stay strictly within \
    it. Running ahead robs the person of the training.
    """ }

    /// Per-level instruction. Goes after the image, so the system prompt and the
    /// screenshot stay a shared cacheable prefix across all three levels.
    /// Seniority and codeOnly shape only the last rung: the nudge and the
    /// approach are the same ladder at any grade, it is the code that differs.
    /// codeOnly strips the prose around the solution — for users who want the
    /// answer pasteable and fast (fewer tokens to generate); the grade still
    /// governs how the code itself is written.
    static func instruction(
        for level: HintLevel, language: String?, seniority: Seniority = .middle,
        codeOnly: Bool = false
    ) -> String {
        let langLine = language.map {
            "\nSolution language: \($0). If the screenshot clearly shows a different language — use the one on screen."
        } ?? "\nDetermine the solution language from the screenshot (from the function template or the code already written)."

        switch level {
        case .nudge:
            return """
            LEVEL 1 — NUDGE.

            Give exactly this and nothing more:
            1. One or two sentences: how you understood the problem (input, \
            output, constraints).
            2. A guiding question or observation that pushes towards the key idea.
            3. Which data structure or technique fits here — name it, but do NOT \
            explain how to apply it.

            FORBIDDEN: a step-by-step algorithm, pseudocode, code, complexity \
            analysis. At most 120 words.
            """

        case .approach:
            return """
            LEVEL 2 — APPROACH.

            Give exactly this:
            1. The algorithm step by step (a numbered list, 3–7 items).
            2. Time and space complexity with a one-line justification.
            3. The edge cases this solution most often fails on.
            4. If the obvious naive solution does not fit the constraints — say why.

            FORBIDDEN: finished code, or pseudocode close enough to transcribe. \
            The person must write the code themselves. At most 250 words.
            """

        case .solution:
            let style: String
            switch seniority {
            case .junior:
                style = codeOnly
                    ? """
                    Write the code the way a strong junior would: as simple and \
                    readable as possible, standard language facilities, clear \
                    names, no clever tricks and no dense one-liners.
                    """
                    : """
                    Write the code the way a strong junior would: as simple and \
                    readable as possible, standard language facilities, clear \
                    names, no clever tricks and no dense one-liners. If the \
                    optimal solution is noticeably harder, give the simple \
                    correct one first, and close with a single line on how it \
                    could be optimised.
                    """
            case .middle:
                style = """
                Write the code like a confident middle: optimal in complexity, \
                idiomatic, tidy — what most interviews expect. No survey of \
                alternatives you did not choose.
                """
            case .senior:
                style = codeOnly
                    ? """
                    Write the code like a senior: the optimal solution with \
                    explicit invariants and structure that speaks for itself.
                    """
                    : """
                    Write the code like a senior: the optimal solution with \
                    explicit invariants and structure that speaks for itself. \
                    After the code add 1–2 lines: the trade-off of the chosen \
                    approach against the main alternative and when that \
                    alternative would be the better fit.
                    """
            }
            // Imports are the one thing worth a line of prose even in code-only
            // mode: an unfamiliar library in pasted code is a question the user
            // cannot answer at a whiteboard.
            let importsLine = """
            If the code pulls in libraries or modules (import/include/using), \
            explain each below the code block in 1–2 PLAIN-language sentences: \
            what it does and why this solution needs it. Do not define a term \
            with a term ("heapq — a min-heap module" explains nothing; right: \
            "heapq — a built-in Python module that keeps a list arranged so the \
            smallest element is always first and can be taken in O(log n) — here \
            it tracks the k largest numbers"). Skip trivialities like typing.List.
            """
            if codeOnly {
                return """
                LEVEL 3 — SOLUTION, CODE ONLY.
                \(langLine)

                Give the working code in full, in one block. NO other text \
                before or after the code block: no introduction, no complexity \
                analysis, no advice. Short comments inside the code are fine \
                where the logic is not obvious. The single exception: \(importsLine)

                \(style)
                """
            }
            return """
            LEVEL 3 — SOLUTION.
            \(langLine)

            Give exactly this:
            1. The working code in full, in one block, with short comments only \
            where the logic is not obvious.
            2. \(importsLine)
            3. Below the code — 2–3 lines: what to be ready for when the \
            interviewer starts probing (why this complexity, what changes under \
            a different constraint).

            \(style)
            """
        }
    }
}
