import Foundation
import SwiftUI

/// One setting drives both the UI language and the language the model answers
/// in. The pattern mirrors Dictate's Localization.swift with one deliberate
/// difference: there the base strings are English; here they are Russian,
/// because the app was written Russian-first — the keys ARE the Russian
/// strings, and the tables translate them. A missing table entry therefore
/// degrades to Russian instead of to a bare key.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, ru, en, uk
    var id: String { rawValue }

    /// Shown in the picker in its own language, so everyone can find theirs.
    var label: String {
        switch self {
        case .system:
            switch Localization.systemLanguage {
            case .uk: return "Як у системі"
            case .en: return "Follow system"
            default: return "Как в системе"
            }
        case .ru: return "Русский"
        case .en: return "English"
        case .uk: return "Українська"
        }
    }
}

/// Translation store. ObservableObject so SwiftUI surfaces re-render the
/// moment the language changes; AppKit surfaces (the status menu) listen for
/// `Localization.changed` instead.
final class Localization: ObservableObject {
    static let shared = Localization()
    static let changed = Notification.Name("codecoach.languageChanged")

    @Published private(set) var language: AppLanguage

    private init() {
        let stored = UserDefaults.standard.string(forKey: "uiLanguage") ?? AppLanguage.system.rawValue
        language = AppLanguage(rawValue: stored) ?? .system
    }

    func setLanguage(_ lang: AppLanguage) {
        language = lang
        UserDefaults.standard.set(lang.rawValue, forKey: "uiLanguage")
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    /// What .system resolves to right now (never .system itself).
    static var systemLanguage: AppLanguage {
        let code = Locale.preferredLanguages.first?
            .split(separator: "-").first.map(String.init) ?? "en"
        switch code {
        case "ru": return .ru
        case "uk": return .uk
        default: return .en
        }
    }

    var resolved: AppLanguage { language == .system ? Self.systemLanguage : language }

    func translate(_ ru: String) -> String {
        switch resolved {
        case .en: return Self.en[ru] ?? ru
        case .uk: return Self.uk[ru] ?? ru
        default: return ru
        }
    }

    /// The line injected into every system prompt: which language the model
    /// answers in. This is the whole "prompts follow the same setting" story —
    /// the prompt scaffolding stays Russian (the model reads it fine), only
    /// the answer language switches.
    var answerRule: String {
        switch resolved {
        case .en: return "Отвечай по-английски (in English)."
        case .uk: return "Отвечай на украинском языке (українською)."
        default: return "Отвечай по-русски."
        }
    }

    // MARK: - Tables (Russian key → translation)

    static let en: [String: String] = [
        // Status menu + About
        "Разобрать задачу": "Solve the problem",
        "⚠️ Нет доступа к Универсальному доступу": "⚠️ Accessibility permission missing",
        "⚠️ Нет доступа к записи экрана": "⚠️ Screen Recording permission missing",
        "Тренировка Python…": "Python Training…",
        "История разборов…": "History…",
        "Настройки…": "Settings…",
        "Проверить обновления…": "Check for Updates…",
        "О CodeCoach": "About CodeCoach",
        "Выйти из CodeCoach": "Quit CodeCoach",
        "Тренажёр по задачам для технических собеседований": "A trainer for technical-interview problems",
        // Window titles
        "Настройки CodeCoach": "CodeCoach Settings",
        "История разборов": "History",
        "Тренировка Python": "Python Training",
        // Settings
        "Язык": "Language",
        "Язык приложения и ответов": "App and answer language",
        "Доступ": "Permissions",
        "Универсальный доступ": "Accessibility",
        "нужен, чтобы слышать горячую клавишу": "needed to hear the hotkey",
        "Запись экрана": "Screen Recording",
        "нужен, чтобы снимать условие задачи; после выдачи перезапустите CodeCoach":
            "needed to capture the problem; restart CodeCoach after granting",
        "Разрешение уже выдано, но не работает — сбросить":
            "Permission granted but not working — reset",
        "Открыть": "Open",
        "Доступ к Claude": "Claude access",
        "Подписка Claude — через Claude Code": "Claude subscription — via Claude Code",
        "Claude Code найден, подсказки идут от подписки — ключ API не нужен":
            "Claude Code found; hints run on your subscription — no API key needed",
        "установите Claude Code и войдите в него, либо введите ключ API ниже":
            "install and log into Claude Code, or paste an API key below",
        "sk-ant-… (не нужен, если есть Claude Code)": "sk-ant-… (not needed with Claude Code)",
        "Сохранить": "Save",
        "Ключ сохранён": "Key saved",
        "Ключ хранится в %@ с правами 0600. Без ключа подсказки идут через Claude Code от вашей подписки; ключ, если задан, имеет приоритет.":
            "The key is stored at %@ with 0600 permissions. Without a key, hints run through Claude Code on your subscription; a key, when set, takes priority.",
        "Горячая клавиша": "Hotkey",
        "Нажмите клавишу…": "Press a key…",
        "Отмена": "Cancel",
        "Изменить": "Change",
        "Нажатие — новая задача. Ещё раз — следующий уровень подсказки. Esc — закрыть.":
            "Press — new problem. Press again — next hint level. Esc — close.",
        "⚠️ Эта клавиша печатает символ в активное окно. Лучше выбрать модификатор или F-клавишу.":
            "⚠️ This key types a character into the active window. Prefer a modifier or an F-key.",
        "Решение": "Solution",
        "Язык кода": "Code language",
        "Определять по экрану": "Detect from screen",
        "Уровень разбора": "Solution register",
        "Джун": "Junior", "Мидл": "Middle", "Синьор": "Senior",
        "Каким по грейду должен быть код решения: джуну — просто и читаемо, синьору — с инвариантами и трейд-оффами.":
            "What grade the solution code targets: junior — simple and readable, senior — invariants and trade-offs.",
        "Только код, без пояснений": "Code only, no explanations",
        "Решение приходит одним блоком кода — быстрее и сразу вставляется. Комментарии внутри кода остаются.":
            "The solution arrives as one code block — faster and paste-ready. In-code comments stay.",
        "Сразу показывать решение": "Show the solution right away",
        "Режим для сравнения грейдов: каждое нажатие — новый снимок и сразу уровень 3, без лестницы подсказок. Для тренировки выключите.":
            "A register-comparison mode: every press is a fresh capture straight to level 3, no hint ladder. Turn off for actual practice.",
        "Хранить историю разборов": "Keep history",
        "Задачи и ответы лежат в %@. В логи они не пишутся никогда.":
            "Problems and answers live in %@. They are never written to logs.",
        // Hint levels + panel
        "Намёк": "Nudge", "Подход": "Approach",
        "Снимаю экран…": "Capturing the screen…",
        "Читаю задачу…": "Reading the problem…",
        "модель думает": "the model is thinking",
        "с": "s",
        "Esc — закрыть": "Esc — close",
        "‹ › — уровни · хоткей — дальше · Esc — закрыть": "‹ › — levels · hotkey — next · Esc — close",
        "Хоткей — новая задача · Esc — закрыть": "Hotkey — new problem · Esc — close",
        "Ещё раз хоткей — следующий уровень · Esc — закрыть": "Hotkey again — next level · Esc — close",
        "Пустой ответ — попробуйте снять экран ещё раз": "Empty answer — try capturing again",
        "Повторить": "Retry",
        "Переснять экран этим же уровнем": "Recapture at the same level",
        "Открыть историю разборов": "Open history",
        "Скопировать только код": "Copy code only",
        "Скопировать весь ответ": "Copy the whole answer",
        "Предыдущий уровень": "Previous level",
        "Следующий из уже полученных": "Next of the already fetched",
        "Закрыть (Esc)": "Close (Esc)",
        // History window
        "Выберите задачу": "Select a problem",
        "Слева — разобранные задачи, свежие сверху.": "Solved problems on the left, newest first.",
        "Без описания": "No description",
        "Удалить": "Delete",
        "Очистить всё": "Clear all",
        "Удалить всю историю разборов?": "Delete the entire history?",
        "Скриншоты и ответы будут удалены с диска безвозвратно.":
            "Screenshots and answers will be permanently removed from disk.",
        // Trainer
        "Первое знакомство": "Getting to know you",
        "Карта знаний": "Knowledge map",
        "задача %d из %d": "task %d of %d",
        "Переменные и типы": "Variables and types", "Строки": "Strings",
        "Списки и кортежи": "Lists and tuples", "Словари и множества": "Dicts and sets",
        "Условия и циклы": "Conditions and loops", "Функции": "Functions",
        "Ошибки и исключения": "Errors and exceptions", "Классы и ООП": "Classes and OOP",
        "не начинал": "not started", "начал": "started", "уверенно": "confident", "освоил": "mastered",
        "Пять коротких задач, чтобы понять, что ты уже знаешь. Пиши код прямо здесь, в поле ниже; когда готов — жми «Проверить».":
            "Five short tasks to see what you already know. Write code right here in the field below; when ready, hit “Check”.",
        "Нажми «Дальше» — получишь задачу под свой уровень.": "Hit “Next” to get a task at your level.",
        "наставник смотрит…": "the mentor is looking…",
        "Твой код": "Your code",
        "Начать": "Start", "Дальше": "Next", "Проверить": "Check",
        "Сдаюсь": "I give up", "Стоп": "Stop", "Дальше →": "Next →",
        // Errors
        "Нет доступа к Claude — установите Claude Code (подписка) или введите ключ API в настройках CodeCoach":
            "No Claude access — install Claude Code (subscription) or paste an API key in CodeCoach settings",
        "Ключ не принят (401) — проверьте его в настройках": "Key rejected (401) — check it in settings",
        "Доступ запрещён (403) — нет прав на эту модель": "Forbidden (403) — no access to this model",
        "Слишком много запросов (429) — подождите немного": "Too many requests (429) — wait a bit",
        "Модель недоступна при нулевом хранении данных в организации (нужно 30 дней)":
            "The model is unavailable under zero data retention (30 days required)",
        "Сбой на стороне API (%d) — попробуйте ещё раз": "API-side failure (%d) — try again",
        "Ошибка API (%d): %@": "API error (%d): %@",
        "Модель отклонила запрос: %@": "The model declined the request: %@",
        "Модель отклонила запрос по правилам безопасности": "The model declined the request for safety reasons",
        "Нет связи с API: %@": "Cannot reach the API: %@",
        "Нет доступа к записи экрана — включите CodeCoach в «Конфиденциальность и безопасность → Запись экрана»":
            "No Screen Recording access — enable CodeCoach in Privacy & Security → Screen Recording",
        "Лимит подписки Claude исчерпан — попробуйте позже": "Claude subscription limit reached — try later",
        " (сброс в %@)": " (resets at %@)",
        "Вы не вошли в Claude Code — выполните claude login в терминале":
            "You are not logged into Claude Code — run claude login in a terminal",
        "Нет связи с Claude — проверьте интернет": "Cannot reach Claude — check your connection",
        "Claude Code завершился без ответа (%@)": "Claude Code finished without an answer (%@)",
        "Claude Code завершился с ошибкой (код %d)": "Claude Code failed (code %d)",
        "Не удалось сохранить ключ в %@": "Could not save the key to %@",
    ]

    static let uk: [String: String] = [
        "Разобрать задачу": "Розібрати задачу",
        "⚠️ Нет доступа к Универсальному доступу": "⚠️ Немає дозволу «Універсальний доступ»",
        "⚠️ Нет доступа к записи экрана": "⚠️ Немає дозволу на запис екрана",
        "Тренировка Python…": "Тренування Python…",
        "История разборов…": "Історія розборів…",
        "Настройки…": "Налаштування…",
        "Проверить обновления…": "Перевірити оновлення…",
        "О CodeCoach": "Про CodeCoach",
        "Выйти из CodeCoach": "Вийти з CodeCoach",
        "Тренажёр по задачам для технических собеседований": "Тренажер із задач для технічних співбесід",
        "Настройки CodeCoach": "Налаштування CodeCoach",
        "История разборов": "Історія розборів",
        "Тренировка Python": "Тренування Python",
        "Язык": "Мова",
        "Язык приложения и ответов": "Мова застосунку та відповідей",
        "Доступ": "Дозволи",
        "Универсальный доступ": "Універсальний доступ",
        "нужен, чтобы слышать горячую клавишу": "потрібен, щоб чути гарячу клавішу",
        "Запись экрана": "Запис екрана",
        "нужен, чтобы снимать условие задачи; после выдачи перезапустите CodeCoach":
            "потрібен, щоб знімати умову задачі; після надання перезапустіть CodeCoach",
        "Разрешение уже выдано, но не работает — сбросить":
            "Дозвіл надано, але не працює — скинути",
        "Открыть": "Відкрити",
        "Доступ к Claude": "Доступ до Claude",
        "Подписка Claude — через Claude Code": "Підписка Claude — через Claude Code",
        "Claude Code найден, подсказки идут от подписки — ключ API не нужен":
            "Claude Code знайдено, підказки йдуть від підписки — ключ API не потрібен",
        "установите Claude Code и войдите в него, либо введите ключ API ниже":
            "встановіть Claude Code і ввійдіть у нього, або введіть ключ API нижче",
        "sk-ant-… (не нужен, если есть Claude Code)": "sk-ant-… (не потрібен, якщо є Claude Code)",
        "Сохранить": "Зберегти",
        "Ключ сохранён": "Ключ збережено",
        "Ключ хранится в %@ с правами 0600. Без ключа подсказки идут через Claude Code от вашей подписки; ключ, если задан, имеет приоритет.":
            "Ключ зберігається в %@ із правами 0600. Без ключа підказки йдуть через Claude Code від вашої підписки; ключ, якщо задано, має пріоритет.",
        "Горячая клавиша": "Гаряча клавіша",
        "Нажмите клавишу…": "Натисніть клавішу…",
        "Отмена": "Скасувати",
        "Изменить": "Змінити",
        "Нажатие — новая задача. Ещё раз — следующий уровень подсказки. Esc — закрыть.":
            "Натискання — нова задача. Ще раз — наступний рівень підказки. Esc — закрити.",
        "⚠️ Эта клавиша печатает символ в активное окно. Лучше выбрать модификатор или F-клавишу.":
            "⚠️ Ця клавіша друкує символ в активне вікно. Краще обрати модифікатор або F-клавішу.",
        "Решение": "Розв'язок",
        "Язык кода": "Мова коду",
        "Определять по экрану": "Визначати з екрана",
        "Уровень разбора": "Рівень розбору",
        "Джун": "Джун", "Мидл": "Мідл", "Синьор": "Сеньйор",
        "Каким по грейду должен быть код решения: джуну — просто и читаемо, синьору — с инвариантами и трейд-оффами.":
            "Яким за грейдом має бути код розв'язку: джуну — просто й читабельно, сеньйору — з інваріантами та трейд-офами.",
        "Только код, без пояснений": "Лише код, без пояснень",
        "Решение приходит одним блоком кода — быстрее и сразу вставляется. Комментарии внутри кода остаются.":
            "Розв'язок приходить одним блоком коду — швидше й одразу вставляється. Коментарі в коді лишаються.",
        "Сразу показывать решение": "Одразу показувати розв'язок",
        "Режим для сравнения грейдов: каждое нажатие — новый снимок и сразу уровень 3, без лестницы подсказок. Для тренировки выключите.":
            "Режим для порівняння грейдів: кожне натискання — новий знімок і одразу рівень 3, без драбини підказок. Для тренування вимкніть.",
        "Хранить историю разборов": "Зберігати історію розборів",
        "Задачи и ответы лежат в %@. В логи они не пишутся никогда.":
            "Задачі та відповіді лежать у %@. У логи вони не пишуться ніколи.",
        "Намёк": "Натяк", "Подход": "Підхід",
        "Снимаю экран…": "Знімаю екран…",
        "Читаю задачу…": "Читаю задачу…",
        "модель думает": "модель думає",
        "с": "с",
        "Esc — закрыть": "Esc — закрити",
        "‹ › — уровни · хоткей — дальше · Esc — закрыть": "‹ › — рівні · хоткей — далі · Esc — закрити",
        "Хоткей — новая задача · Esc — закрыть": "Хоткей — нова задача · Esc — закрити",
        "Ещё раз хоткей — следующий уровень · Esc — закрыть": "Ще раз хоткей — наступний рівень · Esc — закрити",
        "Пустой ответ — попробуйте снять экран ещё раз": "Порожня відповідь — спробуйте зняти екран ще раз",
        "Повторить": "Повторити",
        "Переснять экран этим же уровнем": "Перезняти екран цим самим рівнем",
        "Открыть историю разборов": "Відкрити історію розборів",
        "Скопировать только код": "Скопіювати лише код",
        "Скопировать весь ответ": "Скопіювати всю відповідь",
        "Предыдущий уровень": "Попередній рівень",
        "Следующий из уже полученных": "Наступний з уже отриманих",
        "Закрыть (Esc)": "Закрити (Esc)",
        "Выберите задачу": "Оберіть задачу",
        "Слева — разобранные задачи, свежие сверху.": "Ліворуч — розібрані задачі, свіжі згори.",
        "Без описания": "Без опису",
        "Удалить": "Видалити",
        "Очистить всё": "Очистити все",
        "Удалить всю историю разборов?": "Видалити всю історію розборів?",
        "Скриншоты и ответы будут удалены с диска безвозвратно.":
            "Скриншоти та відповіді буде безповоротно видалено з диска.",
        "Первое знакомство": "Перше знайомство",
        "Карта знаний": "Карта знань",
        "задача %d из %d": "задача %d з %d",
        "Переменные и типы": "Змінні й типи", "Строки": "Рядки",
        "Списки и кортежи": "Списки й кортежі", "Словари и множества": "Словники й множини",
        "Условия и циклы": "Умови й цикли", "Функции": "Функції",
        "Ошибки и исключения": "Помилки й винятки", "Классы и ООП": "Класи й ООП",
        "не начинал": "не починав", "начал": "почав", "уверенно": "упевнено", "освоил": "опанував",
        "Пять коротких задач, чтобы понять, что ты уже знаешь. Пиши код прямо здесь, в поле ниже; когда готов — жми «Проверить».":
            "П'ять коротких задач, щоб зрозуміти, що ти вже знаєш. Пиши код просто тут, у полі нижче; коли готовий — тисни «Перевірити».",
        "Нажми «Дальше» — получишь задачу под свой уровень.": "Натисни «Далі» — отримаєш задачу під свій рівень.",
        "наставник смотрит…": "наставник дивиться…",
        "Твой код": "Твій код",
        "Начать": "Почати", "Дальше": "Далі", "Проверить": "Перевірити",
        "Сдаюсь": "Здаюся", "Стоп": "Стоп", "Дальше →": "Далі →",
        "Нет доступа к Claude — установите Claude Code (подписка) или введите ключ API в настройках CodeCoach":
            "Немає доступу до Claude — встановіть Claude Code (підписка) або введіть ключ API в налаштуваннях CodeCoach",
        "Ключ не принят (401) — проверьте его в настройках": "Ключ не прийнято (401) — перевірте його в налаштуваннях",
        "Доступ запрещён (403) — нет прав на эту модель": "Доступ заборонено (403) — немає прав на цю модель",
        "Слишком много запросов (429) — подождите немного": "Забагато запитів (429) — зачекайте трохи",
        "Модель недоступна при нулевом хранении данных в организации (нужно 30 дней)":
            "Модель недоступна за нульового зберігання даних в організації (потрібно 30 днів)",
        "Сбой на стороне API (%d) — попробуйте ещё раз": "Збій на боці API (%d) — спробуйте ще раз",
        "Ошибка API (%d): %@": "Помилка API (%d): %@",
        "Модель отклонила запрос: %@": "Модель відхилила запит: %@",
        "Модель отклонила запрос по правилам безопасности": "Модель відхилила запит за правилами безпеки",
        "Нет связи с API: %@": "Немає зв'язку з API: %@",
        "Нет доступа к записи экрана — включите CodeCoach в «Конфиденциальность и безопасность → Запись экрана»":
            "Немає доступу до запису екрана — увімкніть CodeCoach у «Конфіденційність і безпека → Запис екрана»",
        "Лимит подписки Claude исчерпан — попробуйте позже": "Ліміт підписки Claude вичерпано — спробуйте пізніше",
        " (сброс в %@)": " (скидання о %@)",
        "Вы не вошли в Claude Code — выполните claude login в терминале":
            "Ви не ввійшли в Claude Code — виконайте claude login у терміналі",
        "Нет связи с Claude — проверьте интернет": "Немає зв'язку з Claude — перевірте інтернет",
        "Claude Code завершился без ответа (%@)": "Claude Code завершився без відповіді (%@)",
        "Claude Code завершился с ошибкой (код %d)": "Claude Code завершився з помилкою (код %d)",
        "Не удалось сохранить ключ в %@": "Не вдалося зберегти ключ у %@",
    ]
}

/// Translate a Russian base string.
func L(_ ru: String) -> String { Localization.shared.translate(ru) }

/// Translate a Russian format string, then substitute the arguments.
func LF(_ ru: String, _ args: CVarArg...) -> String {
    String(format: Localization.shared.translate(ru), arguments: args)
}
