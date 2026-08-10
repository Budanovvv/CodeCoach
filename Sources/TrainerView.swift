import SwiftUI

/// The training window: knowledge map on top, the task card in the middle,
/// the mentor's streamed response below. The learner codes in their own
/// editor — this window is the assignment and the feedback, not an IDE.
struct TrainerView: View {
    @ObservedObject var controller: TrainerController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            topicMap
            Divider()
            content
            Spacer(minLength: 0)
            buttons
        }
        .padding(16)
        .frame(minWidth: 560, idealWidth: 640, minHeight: 480, idealHeight: 640)
    }

    // MARK: - Knowledge map

    private var topicMap: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(controller.probeIndex != nil ? "Первое знакомство" : "Карта знаний")
                    .font(.system(size: 12, weight: .semibold))
                if let index = controller.probeIndex {
                    Text("задача \(min(index + 1, Trainer.probeTopics.count)) из \(Trainer.probeTopics.count)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
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
                         ? "Пять коротких задач, чтобы понять, что ты уже знаешь. Решай в PyCharm; когда готов — жми «Проверить»."
                         : "Нажми «Дальше» — получишь задачу под свой уровень.")
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
                            Text("наставник смотрит…")
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
                Button(controller.probeIndex != nil ? "Начать" : "Дальше") {
                    controller.nextTask()
                }
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Проверить") { controller.review() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(controller.isBusy || controller.taskText.isEmpty)
                Button("Намёк") { controller.hint() }
                    .disabled(controller.isBusy || controller.taskText.isEmpty)
                Button("Сдаюсь") { controller.giveUp() }
                    .disabled(controller.isBusy || controller.taskText.isEmpty)
                Spacer()
                if controller.isBusy {
                    Button("Стоп") { controller.cancel() }
                } else {
                    Button("Дальше →") { controller.nextTask() }
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
