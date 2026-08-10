import SwiftUI

/// Settings apply immediately — no Apply button, per Apple's HIG.
struct SettingsView: View {
    @StateObject private var keyCapture = KeyCapture()
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
            Section("Доступ") {
                permissionRow(
                    title: "Универсальный доступ",
                    detail: "нужен, чтобы слышать горячую клавишу",
                    granted: accessibilityOK,
                    action: Permissions.openAccessibilitySettings)
                permissionRow(
                    title: "Запись экрана",
                    detail: "нужен, чтобы снимать условие задачи; "
                        + "после выдачи перезапустите CodeCoach",
                    granted: screenOK,
                    action: Permissions.promptOrRevealScreenRecording)

                if !accessibilityOK {
                    // The dead end this rescues: System Settings shows the switch
                    // ON while AXIsProcessTrusted() still returns false, so the
                    // user can neither grant the permission nor understand why
                    // it is refused. Resetting our own record restores the prompt.
                    Button("Разрешение уже выдано, но не работает — сбросить") {
                        Permissions.resetAccessibility()
                    }
                    .font(.system(size: 11))
                }
            }

            Section("Доступ к Claude") {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: subscriptionOK ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(subscriptionOK ? Color.green : Color.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Подписка Claude — через Claude Code").font(.system(size: 12))
                        Text(subscriptionOK
                             ? "Claude Code найден, подсказки идут от подписки — ключ API не нужен"
                             : "установите Claude Code и войдите в него, либо введите ключ API ниже")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                SecureField("sk-ant-… (не нужен, если есть Claude Code)", text: $apiKeyField)
                    .onSubmit(saveKey)
                HStack {
                    Button("Сохранить", action: saveKey)
                        .disabled(apiKeyField.trimmingCharacters(in: .whitespaces).isEmpty)
                    if apiKeySaved {
                        Label("Ключ сохранён", systemImage: "checkmark.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                if let apiKeyError {
                    Text(apiKeyError)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
                Text("Ключ хранится в \(Settings.shared.apiKeyPath) с правами 0600. "
                    + "Без ключа подсказки идут через Claude Code от вашей подписки; "
                    + "ключ, если задан, имеет приоритет.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Section("Горячая клавиша") {
                HStack {
                    Text(keyCapture.isCapturing ? "Нажмите клавишу…" : hotkeyName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(keyCapture.isCapturing ? Brand.accent : .primary)
                    Spacer()
                    Button(keyCapture.isCapturing ? "Отмена" : "Изменить") {
                        if keyCapture.isCapturing { keyCapture.stop() } else { keyCapture.start() }
                    }
                }
                Text("Нажатие — новая задача. Ещё раз — следующий уровень подсказки. Esc — закрыть.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                if KeyNames.typesCharacters(Settings.shared.hotkeyKeyCode) {
                    // A listen-only tap cannot swallow the keystroke, so a plain
                    // key both triggers us and types its character into whatever
                    // has focus.
                    Text("⚠️ Эта клавиша печатает символ в активное окно. Лучше выбрать модификатор или F-клавишу.")
                        .font(.system(size: 10))
                        .foregroundStyle(Brand.accentWarm)
                }
            }

            Section("Решение") {
                Picker("Язык кода", selection: $language) {
                    ForEach(languages, id: \.self) { lang in
                        Text(lang.isEmpty ? "Определять по экрану" : lang).tag(lang)
                    }
                }
                .onChange(of: language) { _, new in
                    Settings.shared.solutionLanguage = new.isEmpty ? nil : new
                }

                Picker("Уровень разбора", selection: $seniority) {
                    ForEach(Seniority.allCases, id: \.self) { s in
                        Text(s.title).tag(s)
                    }
                }
                .onChange(of: seniority) { _, new in
                    Settings.shared.seniority = new
                }
                Text("Каким по грейду должен быть код решения: джуну — просто и "
                    + "читаемо, синьору — с инвариантами и трейд-оффами.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Toggle("Только код, без пояснений", isOn: $codeOnly)
                    .onChange(of: codeOnly) { _, new in
                        Settings.shared.codeOnly = new
                    }
                Text("Решение приходит одним блоком кода — быстрее и сразу "
                    + "вставляется. Комментарии внутри кода остаются.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Toggle("Сразу показывать решение", isOn: $straightToSolution)
                    .onChange(of: straightToSolution) { _, new in
                        Settings.shared.straightToSolution = new
                    }
                Text("Режим для сравнения грейдов: каждое нажатие — новый снимок "
                    + "и сразу уровень 3, без лестницы подсказок. Для тренировки "
                    + "выключите.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Toggle("Хранить историю разборов", isOn: $historyEnabled)
                    .onChange(of: historyEnabled) { _, new in
                        Settings.shared.historyEnabled = new
                    }
                Text("Задачи и ответы лежат в \(History.shared.storageURL.path). В логи они не пишутся никогда.")
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
            if !granted { Button("Открыть", action: action) }
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
