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
            case .typesAndVariables: return L("Переменные и типы")
            case .strings: return L("Строки")
            case .listsAndTuples: return L("Списки и кортежи")
            case .dictsAndSets: return L("Словари и множества")
            case .conditionsAndLoops: return L("Условия и циклы")
            case .functions: return L("Функции")
            case .errors: return L("Ошибки и исключения")
            case .oop: return L("Классы и ООП")
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
            case .notStarted: return L("не начинал")
            case .started: return L("начал")
            case .confident: return L("уверенно")
            case .mastered: return L("освоил")
            }
        }
    }

    /// What the review concluded about one attempt. Parsed from the model's
    /// final "ИТОГ:" line — see TrainerPrompts.
    enum Verdict: String {
        case solved = "решено"
        case partial = "частично"
        case failed = "не решено"
    }

    struct SolvedTask: Codable {
        let topic: Topic
        let title: String
        let date: Date
        let verdict: String
    }

    struct Profile: Codable {
        var probeDone: Bool = false
        var map: [String: Level] = [:]
        var solved: [SolvedTask] = []

        func level(of topic: Topic) -> Level { map[topic.rawValue] ?? .notStarted }
        mutating func set(_ topic: Topic, to level: Level) { map[topic.rawValue] = level }
    }

    /// The probe: five quick tasks over the core topics, easy difficulty. Its
    /// job is a first sketch of the map, not an exam — OOP and errors are left
    /// at "not started" until regular training reaches them.
    static let probeTopics: [Topic] = [
        .typesAndVariables, .strings, .conditionsAndLoops, .listsAndTuples, .functions,
    ]

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
    /// "ИТОГ: решено|частично|не решено" line; scanning from the end tolerates
    /// the model mentioning the word earlier in the explanation.
    static func parseVerdict(from answer: String) -> Verdict? {
        for line in answer.split(separator: "\n").reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let range = trimmed.range(of: "ИТОГ:") else { continue }
            let value = trimmed[range.upperBound...]
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            if value.hasPrefix("решено") { return .solved }
            if value.hasPrefix("частично") { return .partial }
            if value.hasPrefix("не решено") || value.hasPrefix("не_решено") { return .failed }
        }
        return nil
    }

    /// Task titles the generator should avoid repeating, most recent first.
    static func recentTitles(of profile: Profile, limit: Int = 12) -> [String] {
        profile.solved.suffix(limit).reversed().map(\.title)
    }
}
