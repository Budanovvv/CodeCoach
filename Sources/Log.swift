import Foundation

/// Debug log, off in production:
///   defaults write com.valentynbudanov.CodeCoach debugLog -bool YES
/// Written to ~/Library/Logs/CodeCoach/codecoach.log.
///
/// The log NEVER records screenshot bytes, problem text, or model answers — the
/// user's interview problems are their business. Only state transitions, timings
/// and error shapes go here, which is what makes a bug report possible without
/// leaking the content.
enum Log {
    private static let enabled = UserDefaults.standard.bool(forKey: "debugLog")
    private static let queue = DispatchQueue(label: "com.valentynbudanov.CodeCoach.log")

    private static let fileURL: URL? = {
        guard enabled else { return nil }
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/CodeCoach", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("codecoach.log")
    }()

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func d(_ message: @autoclosure () -> String) {
        guard enabled, let fileURL else { return }
        let line = "\(stamp.string(from: Date())) \(message())\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL)
            }
        }
    }
}
