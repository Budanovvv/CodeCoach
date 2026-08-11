import SwiftUI

/// Settings apply immediately — no Apply button, per Apple's HIG.
struct SettingsView: View {
    @StateObject private var keyCapture = KeyCapture()
    @ObservedObject private var loc = Localization.shared
    @State private var uiLanguage = Localization.shared.language
    @State private var userName = Settings.shared.userName ?? ""
    @State private var apiKeyField = ""
    @State private var apiKeySaved = Settings.shared.apiKey != nil
    @State private var apiKeyError: String?
    @State private var hotkeyName = Settings.shared.hotkeyName
    @State private var language = Settings.shared.solutionLanguage ?? ""
    @State private var seniority = Settings.shared.seniority
    @State private var straightToSolution = Settings.shared.straightToSolution
    @State private var codeOnly = Settings.shared.codeOnly
    @State private var historyEnabled = Settings.shared.historyEnabled
    @State private var accessibilityOK = Permissions.accessibility == .granted
    @State private var screenOK = Permissions.screenRecording == .granted
    @State private var subscriptionOK = ClaudeCodeCLI.installed

    var onHotkeyChanged: (Int, String) -> Void

    private let languages = ["", "Python", "JavaScript", "TypeScript", "Java",
                             "C++", "Go", "Swift", "Kotlin", "C#", "Rust"]

    var body: some View {
        Form {
            Section(L("Language")) {
                Picker(L("App and answer language"), selection: $uiLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.label).tag(lang)
                    }
                }
                .onChange(of: uiLanguage) { _, new in
                    Localization.shared.setLanguage(new)
                }
                TextField(L("Name (optional)"), text: $userName)
                    .onChange(of: userName) { _, new in
                        Settings.shared.userName = new
                    }
                Text(L("The trainer's mentor will use it. Stays on this Mac."))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Section(L("Permissions")) {
                permissionRow(
                    title: L("Accessibility"),
                    detail: L("needed to hear the hotkey"),
                    granted: accessibilityOK,
                    action: Permissions.openAccessibilitySettings)
                permissionRow(
                    title: L("Screen Recording"),
                    detail: L("needed to capture the problem; restart CodeCoach after granting"),
                    granted: screenOK,
                    action: Permissions.promptOrRevealScreenRecording)

                if !accessibilityOK {
                    // The dead end this rescues: System Settings shows the switch
                    // ON while AXIsProcessTrusted() still returns false, so the
                    // user can neither grant the permission nor understand why
                    // it is refused. Resetting our own record restores the prompt.
                    Button(L("Permission granted but not working — reset")) {
                        Permissions.resetAccessibility()
                    }
                    .font(.system(size: 11))
                }
            }

            Section(L("Claude access")) {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: subscriptionOK ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(subscriptionOK ? Color.green : Color.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("Claude subscription — via Claude Code")).font(.system(size: 12))
                        Text(subscriptionOK
                             ? L("Claude Code found; hints run on your subscription — no API key needed")
                             : L("install and log into Claude Code, or paste an API key below"))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                SecureField(L("sk-ant-… (not needed with Claude Code)"), text: $apiKeyField)
                    .onSubmit(saveKey)
                HStack {
                    Button(L("Save"), action: saveKey)
                        .disabled(apiKeyField.trimmingCharacters(in: .whitespaces).isEmpty)
                    if apiKeySaved {
                        Label(L("Key saved"), systemImage: "checkmark.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                if let apiKeyError {
                    Text(apiKeyError)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
                Text(LF("The key is stored at %@ with 0600 permissions. Without a key, hints run through Claude Code on your subscription; a key, when set, takes priority.", Settings.shared.apiKeyPath))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Section(L("Hotkey")) {
                HStack {
                    Text(keyCapture.isCapturing ? L("Press a key…") : hotkeyName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(keyCapture.isCapturing ? Brand.accent : .primary)
                    Spacer()
                    Button(keyCapture.isCapturing ? L("Cancel") : L("Change")) {
                        if keyCapture.isCapturing { keyCapture.stop() } else { keyCapture.start() }
                    }
                }
                Text(L("Press — new problem. Press again — next hint level. Esc — close."))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                if KeyNames.typesCharacters(Settings.shared.hotkeyKeyCode) {
                    // A listen-only tap cannot swallow the keystroke, so a plain
                    // key both triggers us and types its character into whatever
                    // has focus.
                    Text(L("⚠️ This key types a character into the active window. Prefer a modifier or an F-key."))
                        .font(.system(size: 10))
                        .foregroundStyle(Brand.accentWarm)
                }
            }

            Section(L("Solution")) {
                Picker(L("Code language"), selection: $language) {
                    ForEach(languages, id: \.self) { lang in
                        Text(lang.isEmpty ? L("Detect from screen") : lang).tag(lang)
                    }
                }
                .onChange(of: language) { _, new in
                    Settings.shared.solutionLanguage = new.isEmpty ? nil : new
                }

                Picker(L("Solution register"), selection: $seniority) {
                    ForEach(Seniority.allCases, id: \.self) { s in
                        Text(s.title).tag(s)
                    }
                }
                .onChange(of: seniority) { _, new in
                    Settings.shared.seniority = new
                }
                Text(L("What grade the solution code targets: junior — simple and readable, senior — invariants and trade-offs."))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Toggle(L("Code only, no explanations"), isOn: $codeOnly)
                    .onChange(of: codeOnly) { _, new in
                        Settings.shared.codeOnly = new
                    }
                Text(L("The solution arrives as one code block — faster and paste-ready. In-code comments stay."))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Toggle(L("Show the solution right away"), isOn: $straightToSolution)
                    .onChange(of: straightToSolution) { _, new in
                        Settings.shared.straightToSolution = new
                    }
                Text(L("A register-comparison mode: every press is a fresh capture straight to level 3, no hint ladder. Turn off for actual practice."))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Toggle(L("Keep history"), isOn: $historyEnabled)
                    .onChange(of: historyEnabled) { _, new in
                        Settings.shared.historyEnabled = new
                    }
                Text(LF("Problems and answers live in %@. They are never written to logs.", History.shared.storageURL.path))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        // A grouped Form is a scroll container with no intrinsic height: with
        // width alone the hosting window collapses to a bare title bar.
        .frame(width: 460, height: 620)
        .onChange(of: keyCapture.capturedKeyCode) { _, code in
            guard code != 0 else { return }
            hotkeyName = keyCapture.capturedName
            onHotkeyChanged(code, keyCapture.capturedName)
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            // Permissions and installed tools change outside the app; refresh
            // whenever the user comes back.
            accessibilityOK = Permissions.accessibility == .granted
            screenOK = Permissions.screenRecording == .granted
            subscriptionOK = ClaudeCodeCLI.installed
        }
        .onDisappear { keyCapture.stop() }
    }

    private func permissionRow(
        title: String, detail: String, granted: Bool, action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12))
                Text(detail).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Spacer()
            if !granted { Button(L("Open"), action: action) }
        }
    }

    private func saveKey() {
        let key = apiKeyField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try Settings.shared.saveAPIKey(key)
            apiKeySaved = true
            apiKeyError = nil
            apiKeyField = ""
        } catch {
            apiKeyError = error.localizedDescription
        }
    }
}
