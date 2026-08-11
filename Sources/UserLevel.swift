import Foundation

/// The one system-wide answer to "how well does this person code". Both
/// surfaces derive from it: the interview ladder maps it to a solution
/// register (what grade the code is written for), the trainer maps it to a
/// starting point (probe size and difficulty, priors for unprobed topics).
/// The wording is the trainer's human scale, not job-grade jargon — a
/// 12-year-old picks "never wrote code", not "junior".
enum UserLevel: String, Codable, CaseIterable {
    case beginner, basics, confident, pro

    var title: String {
        switch self {
        case .beginner: return L("Never wrote code")
        case .basics: return L("Tried it, know the basics")
        case .confident: return L("Write confidently")
        case .pro: return L("Experienced developer")
        }
    }

    /// The interview ladder's solution register. Four steps fold into three
    /// registers: anyone still learning gets the junior register — simple,
    /// readable code is what they can actually study.
    var seniority: Seniority {
        switch self {
        case .beginner, .basics: return .junior
        case .confident: return .middle
        case .pro: return .senior
        }
    }

    /// The trainer's starting-point scale, one to one.
    var trainerLevel: Trainer.SelfLevel {
        switch self {
        case .beginner: return .never
        case .basics: return .basics
        case .confident: return .confident
        case .pro: return .experienced
        }
    }

    /// Migration from the pre-unification per-surface values.
    init(seniority: Seniority) {
        switch seniority {
        case .junior: self = .basics
        case .middle: self = .confident
        case .senior: self = .pro
        }
    }

    init(trainerLevel: Trainer.SelfLevel) {
        switch trainerLevel {
        case .never: self = .beginner
        case .basics: self = .basics
        case .confident: self = .confident
        case .experienced: self = .pro
        }
    }
}
