import Foundation

/// The three rungs of the hint ladder. The whole product is this progression:
/// the trainer withholds the answer until the user has had a chance to solve it,
/// which is the difference between practising and copying.
enum HintLevel: Int, CaseIterable, Comparable {
    case nudge = 1      // the idea and the data structure, no approach, no code
    case approach = 2   // full approach, complexity, edge cases — still no code
    case solution = 3   // working code with brief comments

    static func < (a: HintLevel, b: HintLevel) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .nudge: return L("Nudge")
        case .approach: return L("Approach")
        case .solution: return L("Solution")
        }
    }

    /// Shown in the panel as "Намёк · 1/3".
    var badge: String { "\(title) · \(rawValue)/\(HintLevel.allCases.count)" }

    var next: HintLevel? { HintLevel(rawValue: rawValue + 1) }
    var previous: HintLevel? { HintLevel(rawValue: rawValue - 1) }

    /// Reasoning effort per rung. A nudge is a small ask and should come back
    /// fast; a full solution is worth the deeper pass. Fable 5 performs well
    /// even at the lower rungs, so this is a latency win rather than a quality
    /// sacrifice.
    var effort: String {
        switch self {
        case .nudge: return "medium"
        case .approach: return "high"
        case .solution: return "high"
        }
    }

    /// Model per rung on the subscription path (headless Claude Code). The
    /// nudge is a small ask — Haiku turns it around fastest; the deeper rungs
    /// get Sonnet, near-Opus on coding at a fraction of the latency. Chosen
    /// after the first live run showed 11–23 s per rung on the default Fable 5,
    /// which the owner found too slow. The API-key path ignores this and uses
    /// Fable 5 with per-level effort instead.
    var cliModel: String {
        switch self {
        case .nudge: return "haiku"
        case .approach: return "sonnet"
        case .solution: return "sonnet"
        }
    }

    /// Output ceiling. On Fable 5 thinking is always on and counts against
    /// max_tokens together with the visible answer, so this needs real headroom
    /// — a tight ceiling truncates the answer mid-sentence.
    var maxTokens: Int {
        switch self {
        case .nudge: return 8_000
        case .approach: return 16_000
        case .solution: return 32_000
        }
    }
}
