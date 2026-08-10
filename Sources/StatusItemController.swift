import AppKit

/// The menu bar item: the app's only permanent surface, and the thing that
/// proves it is running at all.
final class StatusItemController {
    private let item: NSStatusItem
    private var busy = false

    var onSettings: (() -> Void)?
    var onHistory: (() -> Void)?
    var onCapture: (() -> Void)?
    var onCheckUpdates: (() -> Void)?

    init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "graduationcap", accessibilityDescription: "CodeCoach")
        item.button?.image?.isTemplate = true
        rebuildMenu()
    }

    func setBusy(_ busy: Bool) {
        guard busy != self.busy else { return }
        self.busy = busy
        item.button?.image = NSImage(
            systemSymbolName: busy ? "graduationcap.fill" : "graduationcap",
            accessibilityDescription: "CodeCoach")
        item.button?.image?.isTemplate = true
    }

    /// Rebuilt on demand so permission warnings and the hotkey name stay current
    /// without an observer per setting.
    func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let hotkey = Settings.shared.hotkeyName
        let capture = NSMenuItem(
            title: "Разобрать задачу (\(hotkey))",
            action: #selector(capture), keyEquivalent: "")
        capture.target = self
        menu.addItem(capture)

        // Permission trouble is stated in the menu rather than only in a dialog
        // the user may have dismissed: a silently dead hotkey is the single most
        // confusing failure this class of app has.
        if !Permissions.allGranted {
            menu.addItem(.separator())
            if Permissions.accessibility != .granted {
                let warn = NSMenuItem(
                    title: "⚠️ Нет доступа к Универсальному доступу",
                    action: #selector(openAccessibility), keyEquivalent: "")
                warn.target = self
                menu.addItem(warn)
            }
            if Permissions.screenRecording != .granted {
                let warn = NSMenuItem(
                    title: "⚠️ Нет доступа к записи экрана",
                    action: #selector(openScreenRecording), keyEquivalent: "")
                warn.target = self
                menu.addItem(warn)
            }
        }

        menu.addItem(.separator())

        let history = NSMenuItem(
            title: "История разборов…", action: #selector(showHistory), keyEquivalent: "")
        history.target = self
        menu.addItem(history)

        let settings = NSMenuItem(
            title: "Настройки…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let updates = NSMenuItem(
            title: "Проверить обновления…", action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)

        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Выйти из CodeCoach", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        menu.addItem(quit)

        item.menu = menu
    }

    @objc private func capture() { onCapture?() }
    @objc private func showSettings() { onSettings?() }
    @objc private func showHistory() { onHistory?() }
    @objc private func checkForUpdates() { onCheckUpdates?() }
    @objc private func openAccessibility() { Permissions.openAccessibilitySettings() }
    @objc private func openScreenRecording() { Permissions.promptOrRevealScreenRecording() }
}
