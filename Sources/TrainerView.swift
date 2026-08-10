import SwiftUI

/// The training window: knowledge map on top, the task card in the middle,
/// the mentor's streamed response below. The learner codes in their own
/// editor — this window is the assignment and the feedback, not an IDE.
struct TrainerView: View {
    @ObservedObject var controller: TrainerController
    @ObservedObject private var loc = Localization.shared

    var body: some View {
        if controller.profile.needsOnboarding {
            onboarding
                .padding(20)
                .frame(minWidth: 560, idealWidth: 660, minHeight: 540, idealHeight: 720)
        } else {
            main
        }
    }

    /// Two optional questions and a start button — deliberately nothing more.
    /// Both answers only tune the starting point; the probe's results win.
    private var onboarding: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Quick setup")).font(.system(size: 16, weight: .semibold))
            Text(L("Two optional questions to pick the right tone and difficulty. A short probe follows and adjusts everything to your actual level."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker(L("Age (optional)"), selection: $onboardingAge) {
                Text(L("Prefer not to say")).tag(Trainer.AgeBand?.none)
                ForEach(Trainer.AgeBand.allCases, id: \.self) { band in
                    Text(band.title).tag(Trainer.AgeBand?.some(band))
                }
            }
            Picker(L("How well do you know Python? (optional)"), selection: $onboardingLevel) {
                Text(L("Prefer not to say")).tag(Trainer.SelfLevel?.none)
                ForEach(Trainer.SelfLevel.allCases, id: \.self) { level in
                    Text(level.title).tag(Trainer.SelfLevel?.some(level))
                }
            }

            Text(L("Everything stays on this Mac and is used only to pick the tone and task difficulty."))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Button(L("Start")) {
                controller.completeOnboarding(age: onboardingAge, selfLevel: onboardingLevel)
            }
            .keyboardShortcut(.defaultAction)
            Spacer(minLength: 0)
        }
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 12) {
            topicMap
            Divider()
            content
            if hasTask {
                editor
            } else {
                Spacer(minLength: 0)
            }
            buttons
        }
        .padding(16)
        .frame(minWidth: 560, idealWidth: 660, minHeight: 540, idealHeight: 720)
    }

    @State private var onboardingAge: Trainer.AgeBand?
    @State private var onboardingLevel: Trainer.SelfLevel?

    private var hasTask: Bool {
        switch controller.phase {
        case .working, .responding: return !controller.taskText.isEmpty
        default: return false
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("Your code"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            CodeEditor(text: $controller.codeInput)
                .frame(minHeight: 140, idealHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.quaternary, lineWidth: 1))
        }
    }

    // MARK: - Knowledge map

    private var topicMap: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(controller.probeIndex != nil ? L("Getting to know you") : L("Knowledge map"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button {
                    controller.redoSetup()
                } label: {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .disabled(controller.isBusy)
                .help(L("Set up again: age, level and a fresh probe"))
                if let index = controller.probeIndex {
                    Text(LF("task %d of %d", min(index + 1, controller.activeProbeTopics.count), controller.activeProbeTopics.count))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            if let note = controller.probeNote {
                Text(note)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Chips wrap on narrow widths instead of clipping.
            FlowLayout(spacing: 6) {
                ForEach(Trainer.Topic.allCases, id: \.self) { topic in
                    topicChip(topic)
                }
            }
        }
    }

    private func topicChip(_ topic: Trainer.Topic) -> some View {
        let level = controller.profile.level(of: topic)
        let isCurrent = controller.currentTopic == topic
        return HStack(spacing: 4) {
            Circle()
                .fill(chipColor(level))
                .frame(width: 7, height: 7)
            Text(topic.title).font(.system(size: 10.5))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(.quaternary.opacity(isCurrent ? 1 : 0.45)))
        .overlay(isCurrent ? Capsule().strokeBorder(Brand.accent, lineWidth: 1) : nil)
        .help("\(topic.title): \(level.title)")
    }

    private func chipColor(_ level: Trainer.Level) -> Color {
        switch level {
        case .notStarted: return .secondary.opacity(0.4)
        case .started: return Brand.accentWarm
        case .confident: return Brand.accent
        case .mastered: return .green
        }
    }

    // MARK: - Task + response

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                switch controller.phase {
                case .idle:
                    Text(controller.probeIndex != nil
                         ? L("A few short tasks to see what you already know. Write code right here in the field below; when ready, hit “Check”.")
                         : L("Hit “Next” to get a task at your level."))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                default:
                    if !controller.taskText.isEmpty {
                        answerSegments(controller.taskText)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.4)))
                    } else if controller.phase == .generating {
                        ProgressView().controlSize(.small)
                    }
                    if !controller.responseText.isEmpty {
                        Divider()
                        answerSegments(controller.responseText)
                    } else if controller.phase == .responding {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(L("the mentor is looking…"))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func answerSegments(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(AnswerFormat.segments(text).enumerated()), id: \.offset) { _, segment in
                switch segment.kind {
                case .prose:
                    Text(LocalizedStringKey(segment.text))
                        .font(.system(size: 12.5))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                case .code(let language):
                    VStack(alignment: .leading, spacing: 3) {
                        if let language, !language.isEmpty {
                            Text(language).font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary)
                        }
                        Text(segment.text)
                            .font(.system(size: 11.5, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.08)))
                    }
                }
            }
        }
    }

    // MARK: - Buttons

    private var buttons: some View {
        HStack(spacing: 10) {
            if controller.phase == .idle {
                Button(controller.probeIndex != nil ? L("Start") : L("Next")) {
                    controller.nextTask()
                }
                .keyboardShortcut(.defaultAction)
            } else {
                Button(L("Check")) { controller.review() }
                    .disabled(controller.isBusy || controller.taskText.isEmpty
                              || controller.codeInput.trimmingCharacters(
                                  in: .whitespacesAndNewlines).isEmpty)
                Button(L("Nudge")) { controller.hint() }
                    .disabled(controller.isBusy || controller.taskText.isEmpty)
                Button(L("I give up")) { controller.giveUp() }
                    .disabled(controller.isBusy || controller.taskText.isEmpty)
                Spacer()
                if controller.isBusy {
                    Button(L("Stop")) { controller.cancel() }
                } else {
                    Button(L("Next →")) { controller.nextTask() }
                        .disabled(controller.taskText.isEmpty)
                }
            }
        }
    }
}

/// Minimal wrapping HStack for the topic chips; SwiftUI's Layout protocol
/// makes this small enough to keep local.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(in: proposal.width ?? 600, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let positions = arrange(in: bounds.width, subviews: subviews).positions
        for (subview, position) in zip(subviews, positions) {
            subview.place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified)
        }
    }

    private func arrange(in width: CGFloat, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (positions, CGSize(width: width, height: y + rowHeight))
    }
}
