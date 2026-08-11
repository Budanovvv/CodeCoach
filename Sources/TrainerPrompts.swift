import Foundation

/// Prompt text for the trainer mode. A separate voice from Prompts.swift: the
/// interview ladder briefs a candidate, this one teaches a learner. The
/// same product discipline holds — and harder: a review must never leak the
/// solution, because for a learner a leaked solution ends the learning.
/// English scaffolding (the base language); the answer language follows the
/// app-language setting via the injected rule.
enum TrainerPrompts {

    /// Stable across every trainer request for a given profile. Nothing
    /// volatile may go in here — the answer-language rule and the age register
    /// are stable for as long as the settings are.
    static func system(age: Trainer.AgeBand?) -> String {
        let register: String
        switch age {
        case .some(.child):
            register = """
            The learner is a child under 13. Very simple words, short sentences, \
            playful tone — but never babyish. Tasks are about play: games, \
            animals, sweets, school adventures.
            """
        case .some(.teen):
            register = """
            The learner is a teenager. Friendly and direct, no talking down. \
            Tasks are about things a teenager relates to: games, messages, \
            school, music, sport — not warehouses and bookkeeping.
            """
        case .some(.adult):
            register = """
            The learner is an adult. Plain, respectful, never condescending. \
            Tasks come from everyday life, hobbies and small practical tools.
            """
        case .none:
            register = """
            The learner's age is unknown. Neutral, friendly tone that works for \
            anyone. Tasks about everyday things: messages, games, lists, music.
            """
        }
        return """
        You are a patient Python mentor. The learner's knowledge is patchy: \
        some things they know well, some they have never seen. Your job is that \
        they FIGURE THINGS OUT themselves, with you steering.

        \(register)

        Rules:
        - \(Localization.shared.answerRule) Code and function names stay in \
        English.
        - Never shame mistakes. A mistake is material to examine, not a failure.
        - Answer densely: the reply is read in a small window.
        - Code always goes in triple backticks with a language tag.

        You receive four kinds of requests: invent a task, check a solution, \
        give a hint, show the solution. Stay strictly within the request — \
        running ahead takes away the learner's chance to figure it out.
        """
    }

    /// Task generation. The answer is shown to the learner as-is, so the format
    /// contract (TITLE first) doubles as the UI parser's contract.
    static func generateTask(
        topic: Trainer.Topic, level: Trainer.Level, avoidTitles: [String]
    ) -> String {
        let difficulty: String
        switch level {
        case .notStarted:
            difficulty = "the very simplest, a first meeting with the topic; a single action"
        case .started:
            difficulty = "simple, 5–10 lines of code"
        case .confident, .mastered:
            difficulty = "medium, 10–20 lines, with one non-obvious moment"
        }
        let avoid = avoidTitles.isEmpty ? "" :
            "\nRecent tasks (do NOT repeat them or near-duplicates): " + avoidTitles.joined(separator: "; ")

        return """
        INVENT ONE Python task.

        Topic: \(topic.title). Difficulty: \(difficulty).\(avoid)

        The answer format — exactly this:
        TITLE: <a short task name>
        <the statement in 2–5 sentences the learner easily understands>

        Example:
        <input and expected output, in a code block>

        Write the word "TITLE:" exactly like that — never translate it; the \
        program parses it to find the task name.

        Write the statement and the example in \(Localization.shared.answerLanguageName). \
        Ignore the language of the recent-task names above — they are data, not \
        a language cue.

        NO solution, NO hints, NO plan — only the task and the example.
        """
    }

    /// Level-0 review of the code the learner typed in the trainer window.
    /// Feedback yes, solution no. The trailing "VERDICT:" line is machine-read —
    /// see Trainer.parseVerdict.
    static func review(taskText: String, code: String) -> String {
        """
        CHECK A SOLUTION. The task the learner is solving:

        \(taskText)

        His code (may be unfinished):

        ```python
        \(code)
        ```

        Examine HIS attempt specifically:
        1. What is already done right — name it, this matters.
        2. If there is a mistake — show ON WHICH input it appears, but do not \
        say how to fix it. Let him see it himself.
        3. If the code is correct — say so and, if there is one, ask a single \
        "what happens if…" question about an edge case.

        FORBIDDEN: writing correct code, dictating fixes line by line, \
        retelling the solution algorithm.

        Answer in \(Localization.shared.answerLanguageName).

        End the answer with the verdict on its own last line, exactly in this \
        format — never translate these three words; the program reads this line:
        VERDICT: solved | partial | not solved
        """
    }

    /// A nudge for a stuck learner: direction, not the path.
    static func hint(taskText: String) -> String {
        """
        A HINT. The learner is stuck on the task:

        \(taskText)

        Give one guiding question or observation that pushes towards the idea, \
        and name which Python construct helps here (for example: a for loop, a \
        dict, string slicing) — but do NOT show how to apply it.

        FORBIDDEN: a solution plan, pseudocode, code. At most 60 words. \
        Answer in \(Localization.shared.answerLanguageName).
        """
    }

    /// "I give up": the full solution, taught rather than dumped.
    static func solution(taskText: String) -> String {
        """
        THE LEARNER GAVE UP. The task:

        \(taskText)

        Show the solution so it can be LEARNED from:
        1. First, one sentence: what the key idea was.
        2. The working code — the simplest, most readable variant, no tricks.
        3. A step-by-step walkthrough: 2–4 points on what each part does.
        4. One line: which similar task would cement this idea.

        Answer in \(Localization.shared.answerLanguageName).
        """
    }
}
