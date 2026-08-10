import Foundation

/// User preferences (UserDefaults) plus the API key, which deliberately lives in
/// a 0600 file rather than the Keychain: a Keychain item asks for access again
/// on every rebuild that changes the binary, which turns development into a
/// stream of authorization dialogs. A 0600 file is the same protection level as
/// a .env and produces none of them.
final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    /// Virtual keycode of the capture key. Right ⌘.
    ///
    /// NOT right ⌥ (61): that is Dictate's default push-to-talk key, and with
    /// both apps running one press would fire a screenshot and a dictation at
    /// the same time.
    static let defaultHotkeyKeyCode = 54

    var hotkeyKeyCode: Int {
        get { d.object(forKey: "hotkeyKeyCode") as? Int ?? Self.defaultHotkeyKeyCode }
        set { d.set(newValue, forKey: "hotkeyKeyCode") }
    }

    var hotkeyName: String {
        get { d.string(forKey: "hotkeyName") ?? "Right Command (⌘)" }
        set { d.set(newValue, forKey: "hotkeyName") }
    }

    /// Preferred solution language; nil means "read it off the screenshot".
    var solutionLanguage: String? {
        get {
            guard let v = d.string(forKey: "solutionLanguage"), !v.isEmpty else { return nil }
            return v
        }
        set { d.set(newValue ?? "", forKey: "solutionLanguage") }
    }

    /// What grade the level-3 solution should be written for.
    var seniority: Seniority {
        get { d.string(forKey: "seniority").flatMap(Seniority.init) ?? .middle }
        set { d.set(newValue.rawValue, forKey: "seniority") }
    }

    /// Level-3 answers carry only the code block — no prose around it. Faster
    /// (fewer tokens to generate) and pasteable as-is.
    var codeOnly: Bool {
        get { d.bool(forKey: "codeOnly") }
        set { d.set(newValue, forKey: "codeOnly") }
    }

    /// Skip the ladder and answer every press with a level-3 solution.
    /// A comparison/test mode (owner's request — to see how the junior, middle
    /// and senior registers differ on the same problem), not the product's
    /// default: the ladder stays the way to actually train.
    var straightToSolution: Bool {
        get { d.bool(forKey: "straightToSolution") }
        set { d.set(newValue, forKey: "straightToSolution") }
    }

    /// Keep solved problems on disk for later review.
    var historyEnabled: Bool {
        get { d.object(forKey: "historyEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "historyEnabled") }
    }

    /// Where the user dragged or stretched the hint panel, as its EXPANDED
    /// frame. nil means untouched — and only while it is nil does the panel keep
    /// snapping under the notch on whichever display holds the cursor. Stored as
    /// a string because a rect is four numbers that only make sense together.
    var panelFrame: NSRect? {
        get {
            guard let raw = d.string(forKey: "panelFrame"), !raw.isEmpty else { return nil }
            let rect = NSRectFromString(raw)
            // A zero-sized rect is a corrupted or half-written value; treating it
            // as "untouched" is better than showing an invisible panel.
            guard rect.width > 1, rect.height > 1 else { return nil }
            return rect
        }
        set {
            guard let newValue else { return d.removeObject(forKey: "panelFrame") }
            d.set(NSStringFromRect(newValue), forKey: "panelFrame")
        }
    }

    var onboardingDone: Bool {
        get { d.bool(forKey: "onboardingDone") }
        set { d.set(newValue, forKey: "onboardingDone") }
    }

    // MARK: - API key

    private static let keyURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/codecoach/api-key")

    var apiKey: String? {
        guard let raw = try? String(contentsOf: Self.keyURL, encoding: .utf8) else { return nil }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    var apiKeyPath: String { Self.keyURL.path }

    /// Writes the key with 0600 permissions. The mode is set in the create
    /// attributes rather than after the write, so the key is never briefly
    /// readable by other users.
    func saveAPIKey(_ key: String) throws {
        let dir = Self.keyURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])

        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else { return }

        try? FileManager.default.removeItem(at: Self.keyURL)
        guard FileManager.default.createFile(
            atPath: Self.keyURL.path, contents: data,
            attributes: [.posixPermissions: 0o600])
        else {
            throw NSError(domain: "CodeCoach", code: 1, userInfo: [
                NSLocalizedDescriptionKey: LF("Could not save the key to %@", Self.keyURL.path)
            ])
        }
        Log.d("settings: api key saved (\(trimmed.count) chars)")
    }
}
