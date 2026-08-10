import AppKit

/// Problems the user has worked through, kept on disk so practice accumulates
/// instead of evaporating when the panel closes.
///
/// Everything lives under Application Support, never in the debug log: these are
/// the user's interview problems and their own attempts at them.
final class History {
    static let shared = History()

    struct Entry: Codable, Identifiable {
        let id: String
        let date: Date
        /// Highest level the user actually asked for. A problem solved at level 1
        /// means something different from one that needed the full solution, and
        /// that difference is the point of reviewing later.
        var maxLevel: Int
        /// Answer text per level, keyed by the level's raw value as a string
        /// (JSON object keys cannot be integers).
        var answers: [String: String]
        var screenshotFile: String

        var summary: String {
            AnswerFormat.summary(answers["1"] ?? answers["2"] ?? answers["3"] ?? "")
        }
    }

    private let root: URL
    private let indexURL: URL
    private let queue = DispatchQueue(label: "com.valentynbudanov.CodeCoach.history")
    private(set) var entries: [Entry] = []

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = support.appendingPathComponent("CodeCoach", isDirectory: true)
        indexURL = root.appendingPathComponent("history.json")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        load()
    }

    var storageURL: URL { root }

    /// Encoder and decoder MUST agree on the date strategy. They did not once:
    /// persist() wrote ISO-8601 strings while load() used a default decoder
    /// expecting numeric timestamps, so every relaunch decoded nothing — and
    /// the next persist() overwrote the index with the near-empty in-memory
    /// list, silently destroying the history it failed to read. Keep both
    /// halves of the codec here, next to each other, and nowhere else.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL), !data.isEmpty else { return }
        guard let decoded = try? Self.makeDecoder().decode([Entry].self, from: data) else {
            // A file that exists but does not decode is user data at risk: the
            // next persist() would overwrite it. Set it aside instead, so a
            // future format bug degrades to "history looks empty" rather than
            // "history is gone".
            let backup = indexURL.deletingPathExtension().appendingPathExtension("json.unreadable")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: indexURL, to: backup)
            Log.d("history: index failed to decode — preserved as \(backup.lastPathComponent)")
            return
        }
        entries = decoded.sorted { $0.date > $1.date }
    }

    private func persist() {
        let snapshot = entries
        queue.async { [indexURL] in
            guard let data = try? History.makeEncoder().encode(snapshot) else { return }
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    /// Starts an entry when a screenshot is taken. Returns nil when history is
    /// switched off, and callers treat that as "nothing to record".
    func begin(screenshot: Data) -> String? {
        guard Settings.shared.historyEnabled else { return nil }
        let id = UUID().uuidString
        let filename = "\(id).png"
        let url = root.appendingPathComponent(filename)
        do {
            try screenshot.write(to: url, options: .atomic)
        } catch {
            Log.d("history: screenshot write failed: \(error.localizedDescription)")
            return nil
        }
        entries.insert(Entry(id: id, date: Date(), maxLevel: 0,
                             answers: [:], screenshotFile: filename), at: 0)
        persist()
        return id
    }

    func record(id: String, level: HintLevel, answer: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].answers[String(level.rawValue)] = answer
        entries[index].maxLevel = max(entries[index].maxLevel, level.rawValue)
        persist()
    }

    /// Drops an entry that never got an answer — a mis-press should not leave a
    /// blank row and an orphaned screenshot behind.
    func discardIfEmpty(id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }),
              entries[index].answers.isEmpty else { return }
        let entry = entries.remove(at: index)
        try? FileManager.default.removeItem(at: root.appendingPathComponent(entry.screenshotFile))
        persist()
    }

    func screenshot(for entry: Entry) -> NSImage? {
        NSImage(contentsOf: root.appendingPathComponent(entry.screenshotFile))
    }

    func delete(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        try? FileManager.default.removeItem(at: root.appendingPathComponent(entry.screenshotFile))
        persist()
    }

    func deleteAll() {
        for entry in entries {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(entry.screenshotFile))
        }
        entries = []
        persist()
    }
}
