import Foundation

/// Human-readable names for virtual keycodes, for the hotkey picker.
enum KeyNames {

    /// Left and right modifiers are DIFFERENT keycodes sharing one flag. A user
    /// who presses the wrong side sees nothing happen and concludes the app is
    /// broken — which is why the picker captures a real keypress instead of
    /// letting anyone type a key name.
    static let modifiers: [Int: String] = [
        54: "Right Command (⌘)",
        55: "Left Command (⌘)",
        56: "Left Shift (⇧)",
        60: "Right Shift (⇧)",
        58: "Left Option (⌥)",
        61: "Right Option (⌥)",
        59: "Left Control (⌃)",
        62: "Right Control (⌃)",
        63: "Function (fn)",
    ]

    private static let functionKeys: [Int: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    static func name(for keyCode: Int) -> String {
        if let name = modifiers[keyCode] { return name }
        if let name = functionKeys[keyCode] { return name }
        return "Key \(keyCode)"
    }

    static func isModifier(_ keyCode: Int) -> Bool { (54...63).contains(keyCode) }

    /// A plain key held as a hotkey types its character into whatever has focus —
    /// a listen-only event tap cannot swallow it. Modifiers and F-keys don't.
    static func typesCharacters(_ keyCode: Int) -> Bool {
        !isModifier(keyCode) && functionKeys[keyCode] == nil
    }
}
