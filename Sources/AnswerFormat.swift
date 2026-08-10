import Foundation

/// Splits a model answer into prose and fenced code so the panel can render code
/// in a monospaced block instead of letting SwiftUI's markdown flatten it into
/// a paragraph.
enum AnswerFormat {

    struct Segment: Equatable {
        enum Kind: Equatable { case prose, code(language: String?) }
        let kind: Kind
        let text: String
    }

    /// Splits on ``` fences. An unterminated fence (the common case while a
    /// response is still streaming) is treated as code that runs to the end —
    /// otherwise a half-arrived code block would flash as prose and then reflow.
    static func segments(_ answer: String) -> [Segment] {
        var result: [Segment] = []
        var prose: [String] = []
        var code: [String] = []
        var language: String?
        var inCode = false

        func flushProse() {
            let text = prose.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { result.append(Segment(kind: .prose, text: text)) }
            prose = []
        }

        func flushCode() {
            // Only the trailing newline is stripped: leading whitespace is
            // indentation and must survive.
            var text = code.joined(separator: "\n")
            while text.hasSuffix("\n") { text.removeLast() }
            if !text.isEmpty { result.append(Segment(kind: .code(language: language), text: text)) }
            code = []
            language = nil
        }

        for line in answer.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inCode {
                    flushCode()
                    inCode = false
                } else {
                    flushProse()
                    let tag = line.trimmingCharacters(in: .whitespaces).dropFirst(3)
                        .trimmingCharacters(in: .whitespaces)
                    language = tag.isEmpty ? nil : String(tag)
                    inCode = true
                }
                continue
            }
            if inCode { code.append(line) } else { prose.append(line) }
        }

        if inCode { flushCode() } else { flushProse() }
        return result
    }

    /// One-line summary for the history list. Markdown noise and code fences are
    /// stripped so the row reads as a sentence.
    static func summary(_ answer: String, limit: Int = 90) -> String {
        let firstProse = segments(answer).first { if case .prose = $0.kind { return true }; return false }
        var line = (firstProse?.text ?? answer)
            .components(separatedBy: "\n")
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        line = line.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "#*-• ").union(.whitespaces))
        guard line.count > limit else { return line }
        return String(line.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
