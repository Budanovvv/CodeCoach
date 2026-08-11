import AppKit

/// The PyCharm-style completion popup: a passive list under the caret.
/// Passive is the whole point — the system NSTextView completion provisionally
/// REPLACES the typed text while the list is open, flickers on every keystroke
/// and steals Return; this panel touches nothing until the user accepts with
/// Tab or Return, narrows silently as they type, and Esc just closes it.
final class CompletionPanel {

    private let panel: NSPanel
    private let table: NSTableView
    private let scroll: NSScrollView
    private var candidates: [String] = []

    /// Called with the accepted candidate.
    var onAccept: ((String) -> Void)?

    private static let rowHeight: CGFloat = 20
    private static let width: CGFloat = 220
    private static let maxVisibleRows = 8

    init() {
        table = NSTableView()
        let column = NSTableColumn(identifier: .init("word"))
        column.width = Self.width - 4
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = Self.rowHeight
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.selectionHighlightStyle = .regular
        table.backgroundColor = .clear

        scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false

        // Nonactivating and non-key: the text view keeps focus and the caret
        // keeps blinking; the panel is furniture, not a window the user is in.
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true

        let background = NSVisualEffectView()
        background.material = .menu
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true
        background.addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: background.topAnchor, constant: 2),
            scroll.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -2),
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 2),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -2),
        ])
        panel.contentView = background

        table.dataSource = dataSource
        table.delegate = dataSource
        table.target = self
        table.doubleAction = #selector(rowDoubleClicked)
        dataSource.words = { [weak self] in self?.candidates ?? [] }
    }

    private let dataSource = WordListDataSource()

    var isVisible: Bool { panel.isVisible }

    var selected: String? {
        let row = table.selectedRow
        guard row >= 0, row < candidates.count else { return candidates.first }
        return candidates[row]
    }

    /// Shows or refreshes the list under the caret. Screen rect comes from the
    /// text view's firstRect(forCharacterRange:) — already in screen space.
    func show(_ words: [String], under caretRect: NSRect, attachedTo parent: NSWindow?) {
        guard !words.isEmpty else { return hide() }
        candidates = words
        table.reloadData()
        table.selectRowIndexes([0], byExtendingSelection: false)
        table.scrollRowToVisible(0)

        let rows = min(words.count, Self.maxVisibleRows)
        let height = CGFloat(rows) * (Self.rowHeight + 2) + 6
        var origin = NSPoint(x: caretRect.minX - 4, y: caretRect.minY - height - 4)
        // Keep it on screen: flip above the caret at the bottom edge.
        if let screen = parent?.screen ?? NSScreen.main {
            if origin.y < screen.visibleFrame.minY {
                origin.y = caretRect.maxY + 4
            }
            origin.x = min(origin.x, screen.visibleFrame.maxX - Self.width - 8)
        }
        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: Self.width, height: height),
                       display: true)
        if let parent, panel.parent == nil {
            parent.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
    }

    func hide() {
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        candidates = []
    }

    func moveSelection(by delta: Int) {
        guard !candidates.isEmpty else { return }
        let row = max(0, min(candidates.count - 1, table.selectedRow + delta))
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    @objc private func rowDoubleClicked() {
        if let word = selected { onAccept?(word) }
    }

    /// Plain data source kept separate so the panel object owns no NSTable
    /// protocol conformances itself.
    final class WordListDataSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var words: () -> [String] = { [] }

        func numberOfRows(in tableView: NSTableView) -> Int { words().count }

        func tableView(
            _ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int
        ) -> NSView? {
            let id = NSUserInterfaceItemIdentifier("cell")
            let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTextField
                ?? {
                    let field = NSTextField(labelWithString: "")
                    field.identifier = id
                    field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
                    field.lineBreakMode = .byTruncatingTail
                    return field
                }()
            cell.stringValue = words()[row]
            return cell
        }
    }
}
