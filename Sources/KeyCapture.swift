import AppKit
import SwiftUI

/// Captures a real keypress to assign the hotkey.
///
/// The hotkey is never chosen from a text list: left and right modifiers are
/// different keycodes behind one flag, so a user who picks "Option" from a menu
/// and then presses the other Option sees nothing happen and concludes the app
/// is broken. Pressing the actual key removes the ambiguity.
final class KeyCapture: ObservableObject {
    @Published var isCapturing = false
    @Published var capturedName = ""
    @Published var capturedKeyCode = 0

    private var monitor: Any?

    func start() {
        stop()
        isCapturing = true
        // A local monitor is enough: the settings window has focus while the user
        // is assigning the key, so no event tap is involved.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isCapturing else { return event }

            if event.type == .flagsChanged {
                let code = Int(event.keyCode)
                guard KeyNames.isModifier(code) else { return nil }
                // flagsChanged fires on both press and release; only take the
                // press, i.e. the transition where this key's flag is now set.
                guard HotkeyMonitor.isModifierFlagActive(event.modifierFlags.cgEventFlags,
                                                         keyCode: Int64(code)) else { return nil }
                self.finish(code: code)
                return nil
            }

            if event.keyCode == 53 {   // Esc cancels assignment
                self.stop()
                return nil
            }
            self.finish(code: Int(event.keyCode))
            return nil
        }
    }

    func stop() {
        isCapturing = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Order matters: the view observes capturedKeyCode, so the name has to be
    /// in place before the code changes, or the first assignment renders with a
    /// stale label and only looks right on the second try.
    private func finish(code: Int) {
        capturedName = KeyNames.name(for: code)
        capturedKeyCode = code
        stop()
    }
}

private extension NSEvent.ModifierFlags {
    /// NSEvent and CGEvent carry the same device-dependent bits in the low word;
    /// the side-detection logic in HotkeyMonitor reads those, so reuse it rather
    /// than writing a second, subtly different copy.
    var cgEventFlags: CGEventFlags { CGEventFlags(rawValue: UInt64(rawValue)) }
}
