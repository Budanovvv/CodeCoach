import AppKit
import ApplicationServices
import CoreGraphics

/// The two macOS grants this app cannot work without: Accessibility (to hear the
/// global hotkey) and Screen Recording (to take the screenshot).
enum Permissions {
    enum Status { case granted, denied }

    // MARK: Accessibility — required for the event tap

    static var accessibility: Status { AXIsProcessTrusted() ? .granted : .denied }

    /// Shows the system dialog and registers the app in the Accessibility list.
    ///
    /// Deliberately does NOT open System Settings as well: the dialog's own
    /// button does that and dismisses itself. Doing both leaves the original
    /// dialog hanging behind the settings window with its "Deny" button live,
    /// and one stray click writes a denial that suppresses future prompts.
    static func promptAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func promptAccessibilityIfNeeded() {
        guard accessibility != .granted else { return }
        promptAccessibility()
    }

    /// Registers the app in the Accessibility list without showing a dialog, so
    /// the user can find and flip the switch manually.
    static func registerAccessibilityQuietly() { _ = AXIsProcessTrusted() }

    /// Clears our own Accessibility record. This is the sanctioned escape from
    /// the dead end where System Settings shows the toggle ON but
    /// AXIsProcessTrusted() still returns false (a stale TCC entry after the
    /// bundle was replaced) — there the user can neither grant the permission
    /// nor be told it is missing, because the UI insists it is already there.
    static func resetAccessibility() {
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            p.arguments = ["reset", "Accessibility",
                           Bundle.main.bundleIdentifier ?? "com.valentynbudanov.CodeCoach"]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = out
            do {
                try p.run()
                p.waitUntilExit()
                // Exit 64 ("No such bundle identifier") just means no record
                // existed, which is harmless — the prompt below re-registers us.
                Log.d("permissions: tccutil reset exit=\(p.terminationStatus)")
            } catch {
                Log.d("permissions: tccutil spawn failed: \(error.localizedDescription)")
            }
            DispatchQueue.main.async { promptAccessibility() }
        }
    }

    // MARK: Screen Recording — required for the screenshot

    static var screenRecording: Status {
        CGPreflightScreenCaptureAccess() ? .granted : .denied
    }

    /// Triggers the system prompt. macOS shows it only once per app identity;
    /// afterwards the user has to flip the switch in System Settings, and the
    /// app must be relaunched for a fresh grant to take effect in-process.
    @discardableResult
    static func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// The Screen Recording pane lists an app only after it has asked for
    /// access at least once — opening the pane before that shows a list with
    /// no CodeCoach in it and nothing to grant. So: always ask first (the
    /// one-shot prompt also registers us in the list; on later calls it is a
    /// no-op), and open the pane on repeat clicks, when the switch exists.
    static func promptOrRevealScreenRecording() {
        let d = UserDefaults.standard
        let alreadyAsked = d.bool(forKey: "screenPromptShown")
        d.set(true, forKey: "screenPromptShown")
        requestScreenRecording()
        if alreadyAsked { openScreenRecordingSettings() }
    }

    static func openSettingsPane(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
        else { return }
        NSWorkspace.shared.open(url)
    }

    static func openAccessibilitySettings() { openSettingsPane("Privacy_Accessibility") }
    static func openScreenRecordingSettings() { openSettingsPane("Privacy_ScreenCapture") }

    static var allGranted: Bool {
        accessibility == .granted && screenRecording == .granted
    }
}
