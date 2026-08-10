import Foundation

/// The brains behind the code editor's assistance: completion candidates,
/// auto-indent, bracket pairing. Pure and AppKit-free so the rules are
/// testable. Deliberately NOT a language server: for a learner, recalling
/// `heappush` is part of the exercise — the editor helps with spelling and
/// mechanics, not with thinking.
enum CodeAssist {

    /// Python keywords plus the builtins a beginner actually meets. A static
    /// dictionary, not introspection: the trainer teaches standard Python.
    static let pythonWords: [String] = [
        // keywords
        "and", "as", "assert", "async", "await", "break", "class", "continue",
        "def", "del", "elif", "else", "except", "finally", "for", "from",
        "global", "if", "import", "in", "is", "lambda", "nonlocal", "not",
        "or", "pass", "raise", "return", "try", "while", "with", "yield",
        "True", "False", "None",
        // builtins
        "abs", "all", "any", "bool", "dict", "enumerate", "filter", "float",
        "format", "input", "int", "isinstance", "len", "list", "map", "max",
        "min", "open", "ord", "chr", "print", "range", "reversed", "round",
        "set", "sorted", "str", "sum", "tuple", "type", "zip",
        // common methods a beginner uses constantly
        "append", "pop", "insert", "remove", "extend", "index", "count",
        "split", "join", "strip", "lower", "upper", "replace", "startswith",
        "endswith", "keys", "values", "items", "get", "add", "update",
    ]

    /// Completion candidates for a typed prefix. Sources: the Python
    /// dictionary, plus identifiers already present in the learner's code and
    /// in the task statement (variable names the task suggests). The typed
    /// prefix itself is excluded — completing a word with itself is noise.
    static func completions(
        for prefix: String, document: String, context: String = ""
    ) -> [String] {
        guard prefix.count >= 2 else { return [] }
        var seen = Set<String>()
        var result: [String] = []

        let docWords = identifiers(in: document).union(identifiers(in: context))
        for word in pythonWords + docWords.sorted() {
            guard word.hasPrefix(prefix), word != prefix, seen.insert(word).inserted
            else { continue }
            result.append(word)
        }
        // Shorter candidates first: the near-complete word the learner is
        // probably typing beats a long identifier sharing the prefix.
        return result.sorted { ($0.count, $0) < ($1.count, $1) }
    }

    static func identifiers(in text: String) -> Set<String> {
        var words = Set<String>()
        var current = ""
        for ch in text {
            if ch.isLetter || ch.isNumber || ch == "_" {
                current.append(ch)
            } else {
                if current.count >= 2, !current.first!.isNumber { words.insert(current) }
                current = ""
            }
        }
        if current.count >= 2, !current.first!.isNumber { words.insert(current) }
        return words
    }

    /// The indentation a new line should start with, given the line the caret
    /// leaves: keep its leading whitespace, plus one level after a colon —
    /// the Python rule every editor implements.
    static func indentation(afterLine line: String) -> String {
        let leading = line.prefix { $0 == " " || $0 == "\t" }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // A trailing comment does not cancel the colon rule; a colon inside a
        // comment must not trigger it.
        let code = trimmed.split(separator: "#", maxSplits: 1).first.map(String.init) ?? ""
        let opensBlock = code.trimmingCharacters(in: .whitespaces).hasSuffix(":")
        return String(leading) + (opensBlock ? "    " : "")
    }

    /// Bracket and quote pairing.
    static let pairs: [Character: Character] = [
        "(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'",
    ]
    static let closers: Set<Character> = [")", "]", "}", "\"", "'"]

    /// Whether typing an opening character should also insert its closer:
    /// only when the caret is at a boundary (end of line, before whitespace or
    /// a closer) — auto-closing a quote in the middle of a word turns
    /// `it's` into `it''s`.
    static func shouldAutoClose(opening: Character, nextChar: Character?) -> Bool {
        guard pairs[opening] != nil else { return false }
        guard let next = nextChar else { return true }
        return next == " " || next == "\n" || next == "\t" || closers.contains(next)
    }
}
