import SwiftUI

/// Past problems. This is what turns the tool into preparation rather than a
/// one-off lookup: the value is in coming back to a problem you needed level 3
/// for and trying it again cold.
struct HistoryView: View {
    @ObservedObject private var loc = Localization.shared
    @State private var entries = History.shared.entries
    @State private var selection: History.Entry.ID?
    @State private var confirmingClear = false

    var body: some View {
        NavigationSplitView {
            list
        } detail: {
            if let entry = entries.first(where: { $0.id == selection }) {
                detail(for: entry)
            } else {
                ContentUnavailableView(
                    L("Выберите задачу"),
                    systemImage: "clock.arrow.circlepath",
                    description: Text(L("Слева — разобранные задачи, свежие сверху.")))
            }
        }
        .frame(minWidth: 820, minHeight: 520)
    }

    private var list: some View {
        List(entries, selection: $selection) { entry in
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.summary.isEmpty ? L("Без описания") : entry.summary)
                    .font(.system(size: 12))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(entry.date, format: .dateTime.day().month().hour().minute())
                    if let level = HintLevel(rawValue: entry.maxLevel) {
                        Text("·")
                        // How far the user had to go is the most useful signal in
                        // this list: a problem that needed level 3 is one to redo.
                        Text(level.title).foregroundStyle(Brand.tint(for: level))
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
            .contextMenu {
                Button(L("Удалить"), role: .destructive) { delete(entry) }
            }
        }
        .frame(minWidth: 240)
        .toolbar {
            ToolbarItem {
                Button(L("Очистить всё")) { confirmingClear = true }
                    .disabled(entries.isEmpty)
            }
        }
        .confirmationDialog(
            L("Удалить всю историю разборов?"),
            isPresented: $confirmingClear, titleVisibility: .visible
        ) {
            Button(L("Удалить"), role: .destructive) {
                History.shared.deleteAll()
                entries = []
                selection = nil
            }
            Button(L("Отмена"), role: .cancel) {}
        } message: {
            Text(L("Скриншоты и ответы будут удалены с диска безвозвратно."))
        }
    }

    private func detail(for entry: History.Entry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let image = History.shared.screenshot(for: entry) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.separator, lineWidth: 0.5))
                }

                ForEach(HintLevel.allCases, id: \.rawValue) { level in
                    if let answer = entry.answers[String(level.rawValue)] {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(level.badge)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Brand.tint(for: level))
                            Text(answer)
                                .font(.system(size: 12))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func delete(_ entry: History.Entry) {
        History.shared.delete(entry)
        entries = History.shared.entries
        if selection == entry.id { selection = nil }
    }
}
