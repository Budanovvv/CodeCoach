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
        textView.completionProvider = { [weak coordinator = ctx.coordinator] prefix, document in
            coordinator?.candidates(for: prefix, in: document) ?? []
        }

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

        func candidates(for prefix: String, in document: String) -> [String] {
            CodeAssist.completions(for: prefix, document: document, context: contextText)
        }
    }
}

/// The mechanics live in the view subclass because they are keystroke
/// behaviours, not text-storage observations.
final class PythonTextView: NSTextView {

    var completionProvider: ((String, String) -> [String])?
    private let completionPanel = CompletionPanel()
    private var panelConfigured = false

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
        refreshCompletions()
    }

    // MARK: - Passive completion popup

    private func configurePanelIfNeeded() {
        guard !panelConfigured else { return }
        panelConfigured = true
        completionPanel.onAccept = { [weak self] word in self?.accept(word) }
    }

    /// Recomputes candidates for the word before the caret and shows, updates
    /// or hides the panel. Called after every text change — the panel follows
    /// the text instead of interrupting it.
    private func refreshCompletions() {
        configurePanelIfNeeded()
        let range = rangeForUserCompletion
        guard range.length >= 2, range.location != NSNotFound,
              let swiftRange = Range(range, in: string),
              let provider = completionProvider
        else { return completionPanel.hide() }

        let prefix = String(string[swiftRange])
        let words = provider(prefix, string)
        guard !words.isEmpty else { return completionPanel.hide() }
        let caret = firstRect(forCharacterRange: selectedRange(), actualRange: nil)
        completionPanel.show(words, under: caret, attachedTo: window)
    }

    private func accept(_ word: String) {
        let range = rangeForUserCompletion
        guard range.location != NSNotFound,
              shouldChangeText(in: range, replacementString: word) else { return }
        textStorage?.replaceCharacters(in: range, with: word)
        didChangeText()
        setSelectedRange(NSRange(location: range.location + (word as NSString).length, length: 0))
        completionPanel.hide()
    }

    /// While the panel is up, the keys that operate it must not reach the
    /// text: arrows navigate the list, Return/Tab accept, Esc dismisses.
    /// Everything else falls through and re-filters via didChangeText.
    override func keyDown(with event: NSEvent) {
        if completionPanel.isVisible {
            switch event.keyCode {
            case 125: return completionPanel.moveSelection(by: 1)    // down
            case 126: return completionPanel.moveSelection(by: -1)   // up
            case 36, 48:                                             // return, tab
                if let word = completionPanel.selected { accept(word) }
                return
            case 53:                                                 // esc
                return completionPanel.hide()
            default:
                break
            }
        }
        super.keyDown(with: event)
    }

    override func deleteBackward(_ sender: Any?) {
        super.deleteBackward(sender)
        if completionPanel.isVisible { refreshCompletions() }
    }

    override func mouseDown(with event: NSEvent) {
        completionPanel.hide()
        super.mouseDown(with: event)
    }

    override func resignFirstResponder() -> Bool {
        completionPanel.hide()
        return super.resignFirstResponder()
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
