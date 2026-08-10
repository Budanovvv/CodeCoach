import AppKit

// Single instance. Two copies would mean two event taps on the same hotkey and
// two screenshots per press.
//
// The bundle identifier is compared only when it is non-nil: an app built with a
// custom Info.plist that lost CFBundleIdentifier reports nil, and `nil == nil`
// then matches the first system daemon without one, making the app exit
// instantly with no crash report and no explanation.
let bundleID = Bundle.main.bundleIdentifier
if let bundleID {
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    if let existing = others.first {
        existing.activate(options: [])
        exit(0)
    }
}

let app = NSApplication.shared
// Top-level code in main.swift is not main-actor isolated, but it does run on
// the main thread — assumeIsolated states that to the compiler instead of
// stripping the isolation off AppDelegate, which genuinely is main-actor work.
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate

// A menu bar utility gets no Edit menu automatically, and without one the system
// Cmd-C / Cmd-V shortcuts do not work inside its own text fields — which is
// where the user pastes their API key.
let mainMenu = NSMenu()
let editItem = NSMenuItem()
mainMenu.addItem(editItem)
let editMenu = NSMenu(title: "Edit")
editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
editItem.submenu = editMenu
app.mainMenu = mainMenu

app.setActivationPolicy(.accessory)
app.run()
