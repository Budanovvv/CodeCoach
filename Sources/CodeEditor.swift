import AppKit
import SwiftUI

/// Plain-text code input. SwiftUI's TextEditor is unusable for code: the
/// system substitutes smart quotes and dashes, which silently corrupts Python
/// string literals — the learner's code would fail for a reason they cannot
/// see. An NSTextView with every automatic substitution off is the fix, and a
/// PythonTextView subclass adds the editor mechanics: completions, auto-indent
/// after a colon, bracket pairing, Tab as four spaces (CodeAssist has the
/// rules).
struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    /// Extra completion source — the task statement, so the variable names the
    /// task mentions complete too.
    var context: String = ""

    func makeNSView(context ctx: Context) -> NSScrollView {
        let textView = PythonTextView()
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.delegate = ctx.coordinator

        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0, height: CGFloat.greatestFiniteMagnitude)

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        ctx.coordinator.contextText = context
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context ctx: Context) {
        ctx.coordinator.contextText = context
        guard let textView = scroll.documentView as? NSTextView,
              textView.string != text else { return }
        textView.string = text
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: CodeEditor
        var contextText: String = ""

        init(_ parent: CodeEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textView(
            _ textView: NSTextView,
            completions words: [String],
            forPartialWordRange charRange: NSRange,
            indexOfSelectedItem index: UnsafeMutablePointer<Int>?
        ) -> [String] {
            guard let range = Range(charRange, in: textView.string) else { return [] }
            index?.pointee = 0
            return CodeAssist.completions(
                for: String(textView.string[range]),
                document: textView.string,
                context: contextText)
        }
    }
}

/// The mechanics live in the view subclass because they are keystroke
/// behaviours, not text-storage observations.
final class PythonTextView: NSTextView {

    /// Suppresses completion auto-popup while a completion session inserts its
    /// own text — otherwise accepting a candidate immediately reopens the list.
    private var isInsertingCompletion = false

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let typed = (insertString as? String)
            ?? (insertString as? NSAttributedString)?.string ?? ""

        // Typing the closer that is already at the caret steps over it instead
        // of doubling it — the companion of auto-closing.
        if typed.count == 1, let ch = typed.first, CodeAssist.closers.contains(ch),
           nextCharacter() == ch {
            setSelectedRange(NSRange(location: selectedRange().location + 1, length: 0))
            return
        }

        // An opening bracket around a selection wraps it; at a boundary it
        // brings its closer along and parks the caret between them.
        if typed.count == 1, let ch = typed.first, let closer = CodeAssist.pairs[ch] {
            let selection = selectedRange()
            if selection.length > 0, ch != "\"", ch != "'" || nextCharacter() == nil {
                let selected = (string as NSString).substring(with: selection)
                super.insertText("\(ch)\(selected)\(closer)", replacementRange: selection)
                setSelectedRange(NSRange(location: selection.location + selection.length + 2,
                                         length: 0))
                return
            }
            if selection.length == 0, CodeAssist.shouldAutoClose(opening: ch, nextChar: nextCharacter()) {
                super.insertText("\(ch)\(closer)", replacementRange: replacementRange)
                setSelectedRange(NSRange(location: selectedRange().location - 1, length: 0))
                return
            }
        }

        super.insertText(insertString, replacementRange: replacementRange)

        // Auto-popup: two identifier characters are enough to complete from.
        if !isInsertingCompletion, typed.count == 1, let ch = typed.first,
           ch.isLetter || ch == "_",
           rangeForUserCompletion.length >= 2 {
            complete(nil)
        }
    }

    override func insertCompletion(
        _ word: String, forPartialWordRange charRange: NSRange,
        movement: Int, isFinal flag: Bool
    ) {
        isInsertingCompletion = true
        super.insertCompletion(word, forPartialWordRange: charRange,
                               movement: movement, isFinal: flag)
        isInsertingCompletion = false
    }

    override func insertNewline(_ sender: Any?) {
        let currentLine = lineBeforeCaret()
        super.insertNewline(sender)
        let indent = CodeAssist.indentation(afterLine: currentLine)
        if !indent.isEmpty { super.insertText(indent, replacementRange: selectedRange()) }
    }

    override func insertTab(_ sender: Any?) {
        // Four spaces, the Python convention — a literal tab renders with a
        // different width in every viewer the code is later pasted into.
        super.insertText("    ", replacementRange: selectedRange())
    }

    private func nextCharacter() -> Character? {
        let location = selectedRange().location + selectedRange().length
        guard location < (string as NSString).length,
              let range = Range(NSRange(location: location, length: 1), in: string)
        else { return nil }
        return string[range].first
    }

    private func lineBeforeCaret() -> String {
        let caret = selectedRange().location
        let ns = string as NSString
        guard caret <= ns.length else { return "" }
        let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
        let upToCaret = NSRange(location: lineRange.location,
                                length: caret - lineRange.location)
        return ns.substring(with: upToCaret)
    }
}
