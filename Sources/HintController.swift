import AppKit

/// Orchestrates one problem: screenshot, then a hint level per keypress.
///
/// The interaction is deliberately one key with no chords:
///   press with no session  -> capture the screen, show level 1
///   press with a session   -> reveal the next level for the same screenshot
///   Esc                    -> close, ending the session
///
/// Arrow keys or a modifier chord would be the obvious alternative, but the
/// event tap is listen-only and cannot swallow a keystroke: an arrow that
/// advanced the panel would simultaneously move the cursor in the editor
/// underneath. One unused key avoids that entirely.
@MainActor
final class HintController {

    private let panel = HintPanel()
    private let client = ClaudeClient()

    /// The screenshot the current session is answering about. nil means no
    /// session, so the next press starts a new capture.
    private var screenshot: Data?
    private var historyID: String?
    private var level: HintLevel = .nudge
    private var task: Task<Void, Never>?

    /// A session left open goes stale: after this long the next press is treated
    /// as a new problem, because the screen has almost certainly moved on.
    private static let sessionTimeout: TimeInterval = 15 * 60
    private var lastActivity = Date.distantPast

    var onStateChange: ((Bool) -> Void)?

    /// Forwarded to the AppDelegate, which owns the history window.
    var onOpenHistory: (() -> Void)?

    init() {
        panel.onCopyCode = { [weak self] in self?.copy(codeOnly: true) }
        panel.onCopyAll = { [weak self] in self?.copy(codeOnly: false) }
        panel.onRetry = { [weak self] in self?.retry() }
        panel.onRecapture = { [weak self] in self?.recapture() }
        panel.onOpenHistory = { [weak self] in self?.onOpenHistory?() }
        // The close button is Esc for the mouse: same cancel-and-hide path.
        panel.onClose = { [weak self] in self?.handleEsc() }
    }

    var isBusy: Bool { task != nil }

    // MARK: - Input

    func handleHotkey() {
        // Cheap fail-fast only: Claude Code present or a key on disk. Whether
        // Claude Code is actually logged in is discovered by the request itself.
        guard Auth.anySourceAvailable else {
            panel.showError("Нет доступа к Claude — установите Claude Code (подписка) "
                + "или введите ключ API в настройках CodeCoach")
            return
        }
        // A press while a request is in flight is a mis-press, not a queue: the
        // answer is already on its way and starting a second one would just
        // spend tokens racing the first.
        guard task == nil else {
            Log.d("hotkey: ignored — request in flight")
            return
        }

        let sessionAlive = screenshot != nil
            && panel.isVisible
            && Date().timeIntervalSince(lastActivity) < Self.sessionTimeout

        if sessionAlive, let next = level.next {
            advance(to: next)
        } else {
            // Either no session, or the ladder is exhausted — after the solution
            // the next press wraps around to a fresh problem (owner's request:
            // by then the screen usually shows a different task already).
            startNewProblem()
        }
    }

    func handleEsc() {
        guard panel.isVisible || task != nil else { return }
        task?.cancel()
        task = nil
        endSession()
        panel.hide()
        onStateChange?(false)
        Log.d("session: cancelled by Esc")
    }

    // MARK: - Flow

    private func startNewProblem() {
        endSession()
        // Straight-to-solution skips the ladder — a comparison/test mode; the
        // trainer's default remains starting from the nudge.
        let startLevel: HintLevel = Settings.shared.straightToSolution ? .solution : .nudge
        level = startLevel
        lastActivity = Date()
        panel.showCapturing(level: level)
        onStateChange?(true)

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let shot = try await ScreenCapture.captureDisplayUnderCursor()
                guard !Task.isCancelled else { return }
                self.screenshot = shot.png
                self.historyID = History.shared.begin(screenshot: shot.png)
                await self.run(level: startLevel, png: shot.png)
            } catch {
                self.fail(error)
            }
        }
    }

    private func advance(to next: HintLevel) {
        guard let png = screenshot else { return }
        level = next
        lastActivity = Date()
        panel.showThinking(level: next)
        onStateChange?(true)
        Log.d("session: advancing to level \(next.rawValue)")

        task = Task { [weak self] in
            await self?.run(level: next, png: png)
        }
    }

    private func run(level: HintLevel, png: Data) async {
        panel.showThinking(level: level)
        var collected = ""

        do {
            try await client.stream(
                screenshotPNG: png,
                level: level,
                language: Settings.shared.solutionLanguage
            ) { [weak self] event in
                guard let self else { return }
                // The client streams off a background task; every UI touch has to
                // hop to main.
                Task { @MainActor in
                    switch event {
                    case .thinking(let text):
                        self.panel.appendThinking(text)
                    case .text(let text):
                        collected += text
                        self.panel.appendAnswer(text)
                    }
                }
            }
        } catch {
            if !Task.isCancelled { fail(error) }
            task = nil
            onStateChange?(false)
            return
        }

        guard !Task.isCancelled else {
            task = nil
            return
        }

        panel.finish()
        lastActivity = Date()
        if let historyID, !collected.isEmpty {
            History.shared.record(id: historyID, level: level, answer: collected)
        }
        task = nil
        onStateChange?(false)
        Log.d("session: level \(level.rawValue) done, \(collected.count) chars")
    }

    private func fail(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        Log.d("session: failed — \(message)")
        panel.showError(message)
        task = nil
        onStateChange?(false)

        // A capture that never produced an answer leaves no history row.
        if let historyID {
            History.shared.discardIfEmpty(id: historyID)
            if History.shared.entries.first(where: { $0.id == historyID }) == nil {
                self.historyID = nil
                self.screenshot = nil
            }
        }
    }

    private func endSession() {
        if let historyID { History.shared.discardIfEmpty(id: historyID) }
        screenshot = nil
        historyID = nil
        level = .nudge
    }

    /// Re-runs the level that just failed with the screenshot already in hand;
    /// a failure before the screenshot existed becomes a fresh capture.
    private func retry() {
        guard task == nil else { return }
        guard let png = screenshot else {
            startNewProblem()
            return
        }
        lastActivity = Date()
        panel.showThinking(level: level)
        onStateChange?(true)
        Log.d("session: retry level \(level.rawValue)")
        task = Task { [weak self] in
            await self?.run(level: level, png: png)
        }
    }

    /// Fresh screenshot, same rung: for when the model picked the wrong of two
    /// visible problems, or the screen has been scrolled to show the condition
    /// better. The ladder does not reset — that is what distinguishes this from
    /// a new problem.
    private func recapture() {
        guard task == nil else { return }
        let current = level
        lastActivity = Date()
        panel.showCapturing(level: current)
        onStateChange?(true)
        Log.d("session: recapture at level \(current.rawValue)")

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let shot = try await ScreenCapture.captureDisplayUnderCursor()
                guard !Task.isCancelled else { return }
                self.screenshot = shot.png
                self.historyID = History.shared.begin(screenshot: shot.png)
                await self.run(level: current, png: shot.png)
            } catch {
                self.fail(error)
            }
        }
    }

    private func copy(codeOnly: Bool) {
        let answer = panel.currentAnswer
        guard !answer.isEmpty else { return }
        // The code-only button exists because at level 3 the code is what the
        // user is reaching for, and pasting the prose around it into an editor
        // is never what they meant.
        let code = AnswerFormat.segments(answer)
            .compactMap { segment -> String? in
                if case .code = segment.kind { return segment.text }
                return nil
            }
            .joined(separator: "\n\n")

        let text = codeOnly && !code.isEmpty ? code : answer
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        Log.d("session: copied \(codeOnly && !code.isEmpty ? "code" : "answer") to clipboard")
    }
}
