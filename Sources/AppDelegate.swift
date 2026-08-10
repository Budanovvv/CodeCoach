import AppKit
import Sparkle
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: StatusItemController!
    private var controller: HintController!
    private let hotkey = HotkeyMonitor()
    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var tapHealthTimer: Timer?
    /// Sparkle. Checks run on the schedule from Info.plist; the menu item
    /// triggers a manual check. Updates install silently and apply on the
    /// next launch (SUAutomaticallyUpdate).
    private let updater = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = HintController()
        statusItem = StatusItemController()

        statusItem.onCapture = { [weak self] in self?.controller.handleHotkey() }
        statusItem.onSettings = { [weak self] in self?.showSettings() }
        statusItem.onCheckUpdates = { [weak self] in
            self?.updater.checkForUpdates(nil)
        }
        statusItem.onHistory = { [weak self] in self?.showHistory() }

        controller.onOpenHistory = { [weak self] in self?.showHistory() }
        controller.onStateChange = { [weak self] busy in
            self?.statusItem.setBusy(busy)
        }

        hotkey.keyCode = Int64(Settings.shared.hotkeyKeyCode)
        hotkey.onHotkey = { [weak self] in self?.controller.handleHotkey() }
        hotkey.onEsc = { [weak self] in self?.controller.handleEsc() }
        startHotkey()

        if !Settings.shared.onboardingDone || !Permissions.allGranted || !Auth.anySourceAvailable {
            // First run, or a permission that has gone away: open settings, which
            // is where every one of those problems is fixed.
            Permissions.registerAccessibilityQuietly()
            if Permissions.screenRecording != .granted {
                // Registers the app in the Screen Recording pane and shows the
                // one-shot system prompt; on later launches it is a no-op.
                Permissions.requestScreenRecording()
            }
            showSettings()
            Settings.shared.onboardingDone = true
        }

        Log.d("app: launched, hotkey=\(Settings.shared.hotkeyName), permissions=\(Permissions.allGranted)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        tapHealthTimer?.invalidate()
        hotkey.stop()
    }

    // MARK: - Hotkey

    private func startHotkey() {
        let ok = hotkey.start()
        if !ok { Permissions.promptAccessibilityIfNeeded() }

        // The tap fails silently without Accessibility, and a tap created before
        // the grant stays dead forever even once the switch is flipped. Both are
        // only detectable by polling, and recreating on a timer is what lets the
        // permission take effect without an app restart.
        tapHealthTimer?.invalidate()
        tapHealthTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard !self.hotkey.isAlive else { return }
                Log.d("hotkey: tap dead at health check -> recreating")
                _ = self.hotkey.start()
                self.statusItem.rebuildMenu()
            }
        }
    }

    private func applyHotkey(code: Int, name: String) {
        Settings.shared.hotkeyKeyCode = code
        Settings.shared.hotkeyName = name
        hotkey.keyCode = Int64(code)
        _ = hotkey.start()
        statusItem.rebuildMenu()
        Log.d("hotkey: reassigned to \(name) (\(code))")
    }

    // MARK: - Windows

    private func showSettings() {
        if let settingsWindow {
            present(settingsWindow)
            return
        }
        let view = SettingsView { [weak self] code, name in
            self?.applyHotkey(code: code, name: name)
        }
        let window = makeWindow(title: "Настройки CodeCoach", content: AnyView(view))
        settingsWindow = window
        present(window)
    }

    private func showHistory() {
        if let historyWindow {
            present(historyWindow)
            return
        }
        let window = makeWindow(title: "История разборов", content: AnyView(HistoryView()))
        historyWindow = window
        present(window)
    }

    private func makeWindow(title: String, content: AnyView) -> NSWindow {
        let hosting = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        // Without this the window is deallocated on close and reopening it
        // resurrects a dead object; the reference is cleared in windowWillClose.
        window.isReleasedWhenClosed = false
        window.center()
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification, object: window)
        return window
    }

    private func present(_ window: NSWindow) {
        // A menu bar utility has no permanent Dock icon, but a real window needs
        // one to be reachable via Cmd-Tab and to take focus properly.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func windowWillClose(_ note: Notification) {
        guard let window = note.object as? NSWindow else { return }
        if window === settingsWindow { settingsWindow = nil }
        if window === historyWindow { historyWindow = nil }
        statusItem.rebuildMenu()

        // Back to accessory once none of our windows are left, so the Dock icon
        // disappears again. Deferred: the closing window is still in the list at
        // notification time.
        DispatchQueue.main.async {
            let hasWindows = NSApp.windows.contains {
                $0.isVisible && ($0 === self.settingsWindow || $0 === self.historyWindow)
            }
            if !hasWindows { NSApp.setActivationPolicy(.accessory) }
        }
    }
}
