import AppKit
import SwiftUI

/// Plain-text code input. SwiftUI's TextEditor is unusable for code: the
/// system substitutes smart quotes and dashes, which silently corrupts Python
/// string literals — the learner's code would fail for a reason they cannot
/// see. An NSTextView with every automatic substitution off is the fix.
struct CodeEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let textView = scroll.documentView as! NSTextView

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
        textView.delegate = context.coordinator

        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView,
              textView.string != text else { return }
        textView.string = text
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: CodeEditor
        init(_ parent: CodeEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
