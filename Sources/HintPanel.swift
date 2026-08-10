import AppKit
import SwiftUI

/// State of the panel. One object changing shape, not a set of screens replacing
/// each other — the compact bar grows into the answer sheet and shrinks back.
final class HintPanelModel: ObservableObject {
    enum Phase: Equatable {
        case capturing          // taking the screenshot
        case thinking           // request in flight, no visible tokens yet
        case answering          // tokens arriving
        case done
        case failed(String)
    }

    @Published var phase: Phase = .capturing
    @Published var level: HintLevel = .nudge
    @Published var answer: String = ""
    /// Tail of the summarized reasoning, shown while waiting so a long think
    /// doesn't look like a hang.
    @Published var thinkingLine: String = ""
    /// Answers of the rungs already climbed this session, keyed by raw level.
    /// This is what makes flipping back to the nudge possible after the
    /// solution has replaced it on screen.
    @Published var cachedAnswers: [Int: String] = [:]
    /// When the current wait started — feeds the seconds counter that keeps a
    /// 10–20 s model call from reading as a hang.
    @Published var waitStarted: Date?
    /// True once the user has seen the last rung — the hint used up.
    var atLastLevel: Bool { level.next == nil }

    /// Pure display switch between already-fetched rungs. Never touches the
    /// controller's idea of ladder progress: the hotkey still advances from the
    /// highest rung reached, no matter which one is being read.
    func displayCached(_ target: HintLevel) {
        guard phase == .done, let text = cachedAnswers[target.rawValue] else { return }
        level = target
        answer = text
    }

    func cachedNeighbor(_ delta: Int) -> HintLevel? {
        guard phase == .done, let target = HintLevel(rawValue: level.rawValue + delta),
              cachedAnswers[target.rawValue] != nil else { return nil }
        return target
    }
}

/// Borderless panel: pinned under the notch until the user moves it.
final class HintPanel {
    private let model = HintPanelModel()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    /// Explicit intent flag. A hide() fade that finishes AFTER a new show() must
    /// not order the panel out — reading alphaValue in the completion is not
    /// reliable, because a fresh show() has already animated it back up while
    /// the window's model value still reads 0.
    private var wantsVisible = false

    var onCopyCode: (() -> Void)?
    var onCopyAll: (() -> Void)?
    var onRetry: (() -> Void)?
    var onRecapture: (() -> Void)?
    var onOpenHistory: (() -> Void)?
    var onClose: (() -> Void)?

    /// Which of the two shapes the panel is currently in. Sizes are derived from
    /// it rather than passed around as numbers, because the expanded height is
    /// no longer a constant once the user has resized the panel.
    private enum PanelSize { case compact, expanded }
    private var currentSize: PanelSize = .compact

    /// The frame our own setFrame is driving towards, nil when nothing is in
    /// flight. Also the guard against restarting the unfold animation on every
    /// streamed token.
    private var pendingFrame: NSRect?
    /// The last frame we put the panel at ourselves. didMoveNotification does not
    /// say who moved the window, and it may arrive after the flag above is
    /// cleared — a frame that is still exactly where we left it means nobody
    /// dragged anything.
    private var ownFrame: NSRect?
    private var frameObservers: [NSObjectProtocol] = []

    // Compact bar and answer sheet. Both are DEFAULTS only: the moment the user
    // drags an edge or the panel itself, their frame wins (Settings.panelFrame).
    private static let width: CGFloat = 660
    private static let compactHeight: CGFloat = 52
    private static let expandedHeight: CGFloat = 460
    /// Narrower than this and the header (title, badge, copy button) stops
    /// fitting; shorter than this and the answer sheet shows one line of text.
    private static let minWidth: CGFloat = 380
    private static let minExpandedHeight: CGFloat = 200
    /// Left free around the window edges so the resize grip of the borderless
    /// window is reachable instead of being swallowed by the drag strip.
    private static let resizeGrip: CGFloat = 5
    /// Trailing part of the header the drag strip must not cover: the copy
    /// button and the level badge live there.
    private static let headerControlsZone: CGFloat = 140

    // MARK: - Lifecycle

    func showCapturing(level: HintLevel) {
        cancelHide()
        model.phase = .capturing
        model.level = level
        model.answer = ""
        model.thinkingLine = ""
        // New problem: the previous ladder's answers are stale.
        model.cachedAnswers = [:]
        model.waitStarted = Date()
        show()
    }

    func showThinking(level: HintLevel) {
        cancelHide()
        model.level = level
        model.answer = ""
        model.thinkingLine = ""
        model.phase = .thinking
        if model.waitStarted == nil { model.waitStarted = Date() }
        show()
    }

    func appendThinking(_ text: String) {
        guard model.phase == .thinking else { return }
        // Only the tail is kept: this is a progress signal, not a transcript.
        let combined = (model.thinkingLine + text).replacingOccurrences(of: "\n", with: " ")
        model.thinkingLine = String(combined.suffix(160))
    }

    func appendAnswer(_ text: String) {
        if model.phase != .answering {
            model.phase = .answering
            model.thinkingLine = ""
            model.waitStarted = nil
        }
        model.answer += text
        resize(to: .expanded)
    }

    func finish() {
        guard case .answering = model.phase else {
            // Stream ended without a single visible token: report it rather than
            // leaving a spinner running forever.
            if model.phase == .thinking {
                showError("Пустой ответ — попробуйте снять экран ещё раз")
            }
            return
        }
        model.phase = .done
        // The rung is complete — keep it, so the user can flip back to it after
        // the next one replaces it on screen.
        model.cachedAnswers[model.level.rawValue] = model.answer
    }

    func showError(_ message: String) {
        cancelHide()
        model.phase = .failed(message)
        model.thinkingLine = ""
        model.waitStarted = nil
        show()
        resize(to: .compact)
        // Long enough to read the message and reach the retry button; the old
        // 6 s vanished mid-read and took the button with it.
        scheduleHide(after: 20)
    }

    func hide() {
        cancelHide()
        wantsVisible = false
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            guard let self, let panel else { return }
            if self.wantsVisible {
                Log.d("panel: hide skipped — a new show is in flight")
            } else {
                panel.orderOut(nil)
            }
        }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    var currentAnswer: String { model.answer }

    // MARK: - private

    private func scheduleHide(after delay: Double) {
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelHide() {
        hideWork?.cancel()
        hideWork = nil
    }

    private func show() {
        let panel = ensurePanel()
        wantsVisible = true
        if !panel.isVisible {
            resize(to: .compact, animated: false)
            panel.alphaValue = 0
        }
        panel.orderFrontRegardless()
        Log.d("panel: show \(model.phase) level=\(model.level.rawValue) activeSpace=\(panel.isOnActiveSpace)")
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let bounds = NSRect(x: 0, y: 0, width: Self.width, height: Self.compactHeight)
        let hosting = NSHostingView(rootView: HintView(
            model: model,
            onCopyCode: { [weak self] in self?.onCopyCode?() },
            onCopyAll: { [weak self] in self?.onCopyAll?() },
            onRetry: { [weak self] in self?.onRetry?() },
            onRecapture: { [weak self] in self?.onRecapture?() },
            onOpenHistory: { [weak self] in self?.onOpenHistory?() },
            onClose: { [weak self] in self?.onClose?() }))
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]

        let content = NSView(frame: bounds)
        content.autoresizesSubviews = true
        content.addSubview(hosting)
        content.addSubview(dragHandle(over: bounds))

        let panel = NSPanel(
            contentRect: bounds,
            // .resizable on a borderless window adds no chrome, only the edge
            // and corner grips — which is the whole point here.
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered, defer: false)
        panel.contentView = content
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        // Mouse events are ON, unlike a pure status pill: the answer scrolls and
        // the code needs selecting. .nonactivatingPanel keeps focus in the
        // editor underneath, so typing never lands in our window.
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = true
        // Dragging is the header strip's job, not the background's: with
        // isMovableByWindowBackground the window takes the mouse-down before the
        // content sees it, and selecting a line of the answer would move the
        // panel instead of selecting text.
        panel.isMovableByWindowBackground = false
        // .canJoinAllSpaces, not .moveToActiveSpace. The original reason for
        // moveToActiveSpace still holds — the panel must show up on whichever
        // Space is active, including another app's full-screen Space, which is
        // exactly where a coding editor lives, and .fullScreenAuxiliary stays
        // for that. But moveToActiveSpace drags the window along on every Space
        // switch, and the owner works across several desktops: joining all
        // Spaces leaves the panel where it was put and visible everywhere.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        applyLimits(for: .compact, to: panel)
        observeUserFrameChanges(of: panel)
        self.panel = panel
        return panel
    }

    /// Drag strip over the header. Insets keep it clear of the window edges (the
    /// resize grip) and of the trailing corner (copy button, level badge).
    private func dragHandle(over bounds: NSRect) -> NSView {
        let handle = DragHandleView(frame: NSRect(
            x: Self.resizeGrip,
            y: bounds.height - Self.compactHeight,
            width: max(0, bounds.width - Self.resizeGrip - Self.headerControlsZone),
            height: Self.compactHeight - Self.resizeGrip))
        // Flexible width and bottom margin: the strip keeps its fixed distance
        // from the top and both sides while the sheet grows below it.
        handle.autoresizingMask = [.width, .minYMargin]
        return handle
    }

    private func observeUserFrameChanges(of panel: NSPanel) {
        let center = NotificationCenter.default
        frameObservers = [
            // didMove fires for our own unfolding too, and it may arrive AFTER
            // the animation completion has cleared pendingFrame. pendingFrame
            // filters the in-flight case; ownFrame catches the late delivery —
            // a window sitting exactly where we last put it was not dragged.
            center.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
                guard let self, self.pendingFrame == nil else { return }
                if let own = self.ownFrame, Self.nearlyEqual(panel.frame, own) { return }
                self.rememberUserFrame()
            },
            // Live resize is only ever the user's doing.
            center.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: panel, queue: .main) { [weak self] _ in
                self?.rememberUserFrame()
            },
        ]
    }

    private func resize(to size: PanelSize, animated: Bool = true) {
        guard let panel else { return }
        currentSize = size

        let frame = frameFor(size: size)
        if let pendingFrame, Self.nearlyEqual(pendingFrame, frame) { return }
        guard !Self.nearlyEqual(panel.frame, frame) else { return }

        // Both heights must be legal while the frame is in motion. min/max clamp
        // every intermediate frame of the animation as well, so a limit set
        // ahead of time turns the unfold into a jump; the phase limits go back
        // on once the panel has arrived.
        panel.minSize = NSSize(width: Self.minWidth, height: Self.compactHeight)
        panel.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                               height: CGFloat.greatestFiniteMagnitude)

        pendingFrame = frame
        ownFrame = frame
        if animated, panel.isVisible {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            } completionHandler: { [weak self] in
                guard let self, let panel = self.panel else { return }
                self.pendingFrame = nil
                self.applyLimits(for: self.currentSize, to: panel)
            }
        } else {
            panel.setFrame(frame, display: false)
            pendingFrame = nil
            applyLimits(for: size, to: panel)
        }
    }

    /// The compact bar is a status strip: it may be widened, never stretched
    /// vertically. The answer sheet gets a floor instead, below which the
    /// header and the text stop coexisting.
    private func applyLimits(for size: PanelSize, to panel: NSPanel) {
        panel.minSize = NSSize(
            width: Self.minWidth,
            height: size == .compact ? Self.compactHeight : Self.minExpandedHeight)
        panel.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: size == .compact ? Self.compactHeight : CGFloat.greatestFiniteMagnitude)
    }

    private func height(for size: PanelSize) -> CGFloat {
        switch size {
        case .compact:
            return Self.compactHeight
        case .expanded:
            guard let saved = Settings.shared.panelFrame else { return Self.expandedHeight }
            return max(Self.minExpandedHeight, saved.height)
        }
    }

    /// Two regimes. An untouched panel snaps under the notch on the display
    /// holding the cursor; once the user has moved or resized it, their frame
    /// wins from then on.
    ///
    /// For the default, visibleFrame is the right anchor rather than
    /// safeAreaInsets arithmetic: it already excludes the menu bar and the notch
    /// cutout, and it degrades correctly on external displays that have neither.
    private func frameFor(size: PanelSize) -> NSRect {
        let height = height(for: size)

        if let saved = Settings.shared.panelFrame {
            // Folding anchors the top edge: that is the edge the user aimed at,
            // so the bar collapses upward instead of jumping across the screen.
            let frame = NSRect(x: saved.minX, y: saved.maxY - height,
                               width: max(Self.minWidth, saved.width), height: height)
            if Self.isReachable(frame) { return frame }
            Settings.shared.panelFrame = nil
            Log.d("panel: remembered frame is off every screen — back to the default spot")
        }

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let screen else {
            return NSRect(x: 0, y: 0, width: Self.width, height: height)
        }
        let visible = screen.visibleFrame
        let x = visible.midX - Self.width / 2
        let y = visible.maxY - height - 6
        return NSRect(x: x, y: y, width: Self.width, height: height)
    }

    /// Stores where the user put the panel. What is stored is always the
    /// EXPANDED frame: while the compact bar is up only its top edge and width
    /// are news, and the sheet height has to survive the fold.
    private func rememberUserFrame() {
        guard let panel else { return }
        let frame = panel.frame
        let previous = Settings.shared.panelFrame
        let expandedHeight: CGFloat
        if currentSize == .expanded {
            expandedHeight = max(Self.minExpandedHeight, frame.height)
        } else {
            expandedHeight = previous.map { max(Self.minExpandedHeight, $0.height) }
                ?? Self.expandedHeight
        }
        Settings.shared.panelFrame = NSRect(
            x: frame.minX, y: frame.maxY - expandedHeight,
            width: frame.width, height: expandedHeight)
        if previous == nil {
            Log.d("panel: user placed the panel — its frame is remembered from now on")
        }
    }

    /// Off-screen means off EVERY screen. A panel hanging over an edge is still
    /// usable; one remembered on an unplugged display is not.
    private static func isReachable(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
    }

    private static func nearlyEqual(_ a: NSRect, _ b: NSRect) -> Bool {
        abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5
            && abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
    }

    deinit {
        frameObservers.forEach(NotificationCenter.default.removeObserver)
    }
}

/// Grab strip for moving the panel, laid over the header only. Everything below
/// it is answer text that has to stay selectable, so the drag affordance is
/// deliberately narrow rather than the whole window background.
private final class DragHandleView: NSView {
    override func mouseDown(with event: NSEvent) {
        // performDrag hands the whole drag to AppKit: no mouse-tracking loop of
        // our own, and window snapping comes for free.
        window?.performDrag(with: event)
    }
}

// MARK: - View

private struct HintView: View {
    @ObservedObject var model: HintPanelModel
    let onCopyCode: () -> Void
    let onCopyAll: () -> Void
    let onRetry: () -> Void
    let onRecapture: () -> Void
    let onOpenHistory: () -> Void
    let onClose: () -> Void

    /// Which copy button just fired, for the transient checkmark. View-local:
    /// it is pure presentation and must not survive a phase change.
    @State private var copiedFlash: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            if showsAnswer {
                Divider().opacity(0.5)
                answerBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        .animation(.easeInOut(duration: 0.2), value: model.phase)
    }

    private var showsAnswer: Bool {
        switch model.phase {
        case .answering, .done: return !model.answer.isEmpty
        default: return false
        }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 10) {
            statusIcon
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(isError ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                subtitleView
            }
            Spacer(minLength: 8)
            if isError {
                Button("Повторить", action: onRetry)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .fixedSize()
            }
            if model.phase == .done {
                levelChevrons
                headerButton("camera.on.rectangle", help: "Переснять экран этим же уровнем",
                             action: onRecapture)
                headerButton("clock.arrow.circlepath", help: "Открыть историю разборов",
                             action: onOpenHistory)
            }
            if showsAnswer {
                if answerHasCode {
                    copyButton("curlybraces", help: "Скопировать только код",
                               flashKey: "code", action: onCopyCode)
                }
                copyButton("doc.on.doc", help: "Скопировать весь ответ",
                           flashKey: "all", action: onCopyAll)
            }
            levelBadge
            // Mouse-reachable close. Esc still works, but a visible button
            // needs no explaining.
            headerButton("xmark", help: "Закрыть (Esc)", action: onClose)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
    }

    /// Seconds tick only while waiting; everywhere else the subtitle is static
    /// text and a TimelineView would be pointless redraw.
    @ViewBuilder
    private var subtitleView: some View {
        if model.phase == .capturing || model.phase == .thinking, let started = model.waitStarted {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = max(0, Int(context.date.timeIntervalSince(started)))
                Text(seconds > 2 ? "\(subtitle) · \(seconds) c" : subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } else if !subtitle.isEmpty {
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// Flip between rungs already climbed. Rendered only when a neighbor
    /// exists, so early in the session the header stays uncluttered.
    @ViewBuilder
    private var levelChevrons: some View {
        if model.cachedNeighbor(-1) != nil || model.cachedNeighbor(+1) != nil {
            HStack(spacing: 2) {
                chevron("chevron.left", delta: -1, help: "Предыдущий уровень")
                chevron("chevron.right", delta: +1, help: "Следующий из уже полученных")
            }
        }
    }

    private func chevron(_ icon: String, delta: Int, help: String) -> some View {
        Button {
            if let target = model.cachedNeighbor(delta) { model.displayCached(target) }
        } label: {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(model.cachedNeighbor(delta) == nil
                         ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.secondary))
        .disabled(model.cachedNeighbor(delta) == nil)
        .fixedSize()
        .help(help)
    }

    private func headerButton(
        _ icon: String, help: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 11))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .fixedSize()
        .help(help)
    }

    private func copyButton(
        _ icon: String, help: String, flashKey: String, action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            copiedFlash = flashKey
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if copiedFlash == flashKey { copiedFlash = nil }
            }
        } label: {
            Image(systemName: copiedFlash == flashKey ? "checkmark" : icon)
                .font(.system(size: 11))
        }
        .buttonStyle(.plain)
        .foregroundStyle(copiedFlash == flashKey ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
        .fixedSize()
        .help(help)
    }

    private var answerHasCode: Bool {
        AnswerFormat.segments(model.answer).contains {
            if case .code = $0.kind { return true }
            return false
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch model.phase {
        case .capturing, .thinking:
            PulsingDot(color: Brand.tint(for: model.level))
        case .answering:
            Image(systemName: "text.alignleft")
                .font(.system(size: 12))
                .foregroundStyle(Brand.tint(for: model.level))
        case .done:
            Image(systemName: "checkmark.circle")
                .font(.system(size: 13))
                .foregroundStyle(Brand.tint(for: model.level))
        case .failed:
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var levelBadge: some View {
        Text(model.level.badge)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Brand.tint(for: model.level))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Brand.tint(for: model.level).opacity(0.14)))
            // At the minimum width the title is the part that may truncate; the
            // badge is two words and has to stay whole.
            .fixedSize()
            .opacity(isError ? 0 : 1)
    }

    private var isError: Bool {
        if case .failed = model.phase { return true }
        return false
    }

    private var title: String {
        switch model.phase {
        case .capturing: return "Снимаю экран…"
        case .thinking: return "Читаю задачу…"
        case .answering, .done: return model.level.title
        case .failed(let message): return message
        }
    }

    /// The hint line does double duty: it shows reasoning progress while
    /// waiting, and the next-step affordance once the answer is on screen.
    private var subtitle: String {
        switch model.phase {
        case .capturing:
            return ""
        case .thinking:
            return model.thinkingLine.isEmpty ? "модель думает" : model.thinkingLine
        case .answering:
            return "Esc — закрыть"
        case .done:
            if model.cachedNeighbor(-1) != nil || model.cachedNeighbor(+1) != nil {
                return "‹ › — уровни · хоткей — дальше · Esc — закрыть"
            }
            return model.atLastLevel
                ? "Хоткей — новая задача · Esc — закрыть"
                : "Ещё раз хоткей — следующий уровень · Esc — закрыть"
        case .failed:
            return ""
        }
    }

    // MARK: answer

    private var answerBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(AnswerFormat.segments(model.answer).enumerated()), id: \.offset) { index, segment in
                        switch segment.kind {
                        case .prose:
                            // LocalizedStringKey renders inline markdown (**bold**,
                            // `code`) that the model reliably produces.
                            Text(LocalizedStringKey(segment.text))
                                .font(.system(size: 12.5))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        case .code(let language):
                            CodeBlock(code: segment.text, language: language)
                        }
                    }
                    // Anchor for follow-the-stream scrolling.
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: model.answer) { _, _ in
                // Keeps the newest text in view while it streams. Once the answer
                // is complete the user scrolls freely — nothing moves after .done.
                guard model.phase == .answering else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }
}

private struct CodeBlock: View {
    let code: String
    let language: String?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let language, !language.isEmpty {
                Text(language)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            // Horizontal scrolling rather than wrapping: wrapped code loses the
            // indentation that carries its structure.
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 11.5, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 18% black reads as a code well on the dark material but as smudge on
        // the light one — the light variant needs to be much fainter.
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(.black.opacity(scheme == .dark ? 0.18 : 0.06)))
    }
}

private struct PulsingDot: View {
    let color: Color
    @State private var on = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .opacity(on ? 1 : 0.3)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}
