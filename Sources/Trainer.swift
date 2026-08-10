import Foundation

/// The learning mode's domain model: a per-topic knowledge map instead of one
/// skill number, because the whole reason this mode exists is a learner whose
/// knowledge is patchy — strong in lists, blank in dicts. Pure logic, no
/// AppKit, so the update rules are testable.
enum Trainer {

    /// The Python topics the map tracks, in teaching order. Raw values are
    /// stable storage keys — do not rename without migrating the profile.
    enum Topic: String, Codable, CaseIterable {
        case typesAndVariables = "types"
        case strings = "strings"
        case listsAndTuples = "lists"
        case dictsAndSets = "dicts"
        case conditionsAndLoops = "loops"
        case functions = "functions"
        case errors = "errors"
        case oop = "oop"

        var title: String {
            switch self {
            case .typesAndVariables: return L("Variables and types")
            case .strings: return L("Strings")
            case .listsAndTuples: return L("Lists and tuples")
            case .dictsAndSets: return L("Dicts and sets")
            case .conditionsAndLoops: return L("Conditions and loops")
            case .functions: return L("Functions")
            case .errors: return L("Errors and exceptions")
            case .oop: return L("Classes and OOP")
            }
        }
    }

    /// 0 — not started, 3 — mastered. Coarse on purpose: a 12-year-old's level
    /// in a topic is not a float, and coarse levels make the update rules
    /// legible.
    enum Level: Int, Codable, Comparable {
        case notStarted = 0, started = 1, confident = 2, mastered = 3
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }

        var title: String {
            switch self {
            case .notStarted: return L("not started")
            case .started: return L("started")
            case .confident: return L("confident")
            case .mastered: return L("mastered")
            }
        }
    }

    /// What the review concluded about one attempt. Parsed from the model's
    /// final "VERDICT:" line — see TrainerPrompts.
    enum Verdict: String {
        case solved, partial
        case failed = "not solved"
    }

    struct SolvedTask: Codable {
        let topic: Topic
        let title: String
        let date: Date
        let verdict: String
    }

    /// Age register — bands, not a number: the prompt only needs the tone, and
    /// a public app should not collect a child's exact age it has no use for.
    enum AgeBand: String, Codable, CaseIterable {
        case child, teen, adult

        var title: String {
            switch self {
            case .child: return L("Under 13")
            case .teen: return L("13–17")
            case .adult: return L("Adult")
            }
        }
    }

    /// Self-assessed Python level. A hypothesis, never a verdict: it picks the
    /// probe's size and starting difficulty and seeds unprobed topics — the
    /// probe's actual results always win.
    enum SelfLevel: String, Codable, CaseIterable {
        case never, basics, confident, experienced

        var title: String {
            switch self {
            case .never: return L("Never wrote code")
            case .basics: return L("Tried it, know the basics")
            case .confident: return L("Write confidently")
            case .experienced: return L("Experienced developer")
            }
        }
    }

    struct Profile: Codable {
        var probeDone: Bool = false
        var map: [String: Level] = [:]
        var solved: [SolvedTask] = []
        // Optional so profiles written before onboarding existed still decode.
        var ageBand: AgeBand?
        var selfLevel: SelfLevel?
        var onboardingDone: Bool?

        func level(of topic: Topic) -> Level { map[topic.rawValue] ?? .notStarted }
        mutating func set(_ topic: Topic, to level: Level) { map[topic.rawValue] = level }

        /// Profiles that already ran the probe predate onboarding and skip it.
        var needsOnboarding: Bool { !(onboardingDone ?? false) && !probeDone }
    }

    /// The probe: quick tasks over the core topics. Its job is a first sketch
    /// of the map, not an exam.
    static let probeTopics: [Topic] = [
        .typesAndVariables, .strings, .conditionsAndLoops, .listsAndTuples, .functions,
    ]

    /// Probe size follows the self-assessment: someone who never wrote code
    /// gets three tasks, not five — the probe must not feel like an exam they
    /// are failing.
    static func probeTopics(for selfLevel: SelfLevel?) -> [Topic] {
        selfLevel == SelfLevel.never ? Array(probeTopics.prefix(3)) : probeTopics
    }

    /// The difficulty the probe's tasks are generated at. A confident coder
    /// probed with print("hi") learns nothing and gets bored; a beginner
    /// probed at medium gets crushed.
    static func probeSeedLevel(for selfLevel: SelfLevel?) -> Level {
        switch selfLevel {
        case .confident, .experienced: return .confident
        case .basics: return .started
        default: return .notStarted
        }
    }

    /// The prior for topics the probe did not touch (OOP, errors…): claimed
    /// experience keeps the schedule from dragging an experienced person
    /// through the basics, and nothing more — the first real task per topic
    /// corrects it.
    static func priorLevel(for selfLevel: SelfLevel?) -> Level {
        switch selfLevel {
        case .experienced: return .confident
        case .confident: return .started
        default: return .notStarted
        }
    }

    /// Did the probe agree with the self-assessment? Behavioral evidence wins
    /// either way; this only decides whether to say a friendly line about it.
    enum ProbeSurprise { case asExpected, higher, lower }

    static func probeSurprise(
        selfLevel: SelfLevel?, verdicts: [Topic: Verdict]
    ) -> ProbeSurprise {
        guard let selfLevel, !verdicts.isEmpty else { return .asExpected }
        let score = verdicts.values.reduce(0.0) {
            switch $1 {
            case .solved: return $0 + 2
            case .partial: return $0 + 1
            case .failed: return $0
            }
        } / Double(verdicts.count)
        let expected: Double
        switch selfLevel {
        case .never: expected = 0.4
        case .basics: expected = 1.0
        case .confident: expected = 1.5
        case .experienced: expected = 1.8
        }
        if score - expected >= 0.7 { return .higher }
        if expected - score >= 0.7 { return .lower }
        return .asExpected
    }

    /// Which topic the next task should train: the weakest not-yet-mastered
    /// one, ties broken by teaching order. Simple on purpose — the fancy
    /// 70/20/10 scheduler can replace this once the slice has survived contact
    /// with the learner.
    static func nextTopic(for profile: Profile) -> Topic {
        Topic.allCases
            .filter { profile.level(of: $0) < .mastered }
            .min { profile.level(of: $0) < profile.level(of: $1) }
            ?? .oop
    }

    /// Map update after a finished task. Solved lifts the topic one rung,
    /// giving up drops it one; a partial attempt is information about the
    /// boundary, not a reason to move it.
    static func updated(_ profile: Profile, topic: Topic, verdict: Verdict, gaveUp: Bool) -> Profile {
        var next = profile
        let current = profile.level(of: topic)
        if gaveUp {
            next.set(topic, to: Level(rawValue: max(0, current.rawValue - 1)) ?? .notStarted)
        } else if verdict == .solved {
            next.set(topic, to: Level(rawValue: min(3, current.rawValue + 1)) ?? .mastered)
        }
        return next
    }

    /// Probe scoring: one verdict per probe task becomes the map's first
    /// sketch. Solved = confident (not mastered — one easy task proves less
    /// than mastery), partial = started, failed = not started.
    static func mapFromProbe(_ verdicts: [Topic: Verdict]) -> [String: Level] {
        var map: [String: Level] = [:]
        for (topic, verdict) in verdicts {
            switch verdict {
            case .solved: map[topic.rawValue] = .confident
            case .partial: map[topic.rawValue] = .started
            case .failed: map[topic.rawValue] = .notStarted
            }
        }
        return map
    }

    /// Pulls the verdict out of a review answer. The prompt asks for a final
    /// "VERDICT: solved|partial|not solved" line pinned to English in any
    /// answer language; scanning from the end tolerates the model mentioning
    /// the word earlier in the explanation.
    static func parseVerdict(from answer: String) -> Verdict? {
        for line in answer.split(separator: "\n").reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let range = trimmed.range(of: "VERDICT:", options: .caseInsensitive)
            else { continue }
            let value = trimmed[range.upperBound...]
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            if value.hasPrefix("solved") { return .solved }
            if value.hasPrefix("partial") { return .partial }
            if value.hasPrefix("not solved") || value.hasPrefix("not_solved") { return .failed }
        }
        return nil
    }

    /// Task titles the generator should avoid repeating, most recent first.
    static func recentTitles(of profile: Profile, limit: Int = 12) -> [String] {
        profile.solved.suffix(limit).reversed().map(\.title)
    }
}
