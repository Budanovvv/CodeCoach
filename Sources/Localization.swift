import Foundation
import SwiftUI

/// One setting drives both the UI language and the language the model answers
/// in. Same pattern as Dictate's Localization.swift, including the base
/// language: the keys ARE the English strings (owner's call — English is the
/// base), and the tables translate them. A missing entry degrades to English.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, ru, en, uk
    var id: String { rawValue }

    /// Shown in the picker in its own language, so everyone can find theirs.
    var label: String {
        switch self {
        case .system:
            switch Localization.systemLanguage {
            case .uk: return "Як у системі"
            case .ru: return "Как в системе"
            default: return "Follow system"
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

    func translate(_ en: String) -> String {
        switch resolved {
        case .ru: return Self.ru[en] ?? en
        case .uk: return Self.uk[en] ?? en
        default: return en
        }
    }

    /// The line injected into every system prompt: which language the model
    /// answers in. The prompts themselves are English scaffolding; only this
    /// rule switches with the setting.
    var answerRule: String {
        switch resolved {
        case .ru: return "Answer in Russian (по-русски)."
        case .uk: return "Answer in Ukrainian (українською)."
        default: return "Answer in English."
        }
    }

    /// The answer language, named for embedding into user messages. The
    /// system-prompt rule alone loses to stray language cues inside the user
    /// message (a Russian task title in the avoid-list flipped whole answers) —
    /// each request states its language explicitly.
    var answerLanguageName: String {
        switch resolved {
        case .ru: return "Russian (русский)"
        case .uk: return "Ukrainian (українська)"
        default: return "English"
        }
    }

    // MARK: - Tables (English key → translation)

    static let ru: [String: String] = [
        "Ready to train": "Готов тренироваться",
        "Something went wrong": "Что-то пошло не так",
        "Name (optional)": "Имя (необязательно)",
        "The trainer's mentor will use it. Stays on this Mac.":
            "Наставник в тренировке будет обращаться по имени. Остаётся на этом Mac.",
        "%@: %@ — click to train this topic next":
            "%@: %@ — нажми, чтобы тренировать эту тему следующей",
        "Under 13": "До 12",
        "13–17": "13–17",
        "Adult": "Взрослый",
        "Prefer not to say": "Не указывать",
        "Never wrote code": "Никогда не писал код",
        "Tried it, know the basics": "Пробовал, знаю основы",
        "Write confidently": "Пишу уверенно",
        "Experienced developer": "Опытный разработчик",
        "Quick setup": "Быстрая настройка",
        "Two optional questions to pick the right tone and difficulty. A short probe follows and adjusts everything to your actual level.":
            "Два необязательных вопроса, чтобы подобрать тон и сложность. Дальше — короткая проба, она подстроит всё под твой реальный уровень.",
        "Age (optional)": "Возраст (необязательно)",
        "How well do you know Python? (optional)": "Насколько хорошо ты знаешь Python? (необязательно)",
        "Everything stays on this Mac and is used only to pick the tone and task difficulty.":
            "Всё остаётся на этом Mac и используется только для подбора тона и сложности задач.",
        "Set up again: age, level and a fresh probe": "Настроить заново: возраст, уровень и новая проба",
        "The probe showed a higher level than you said — the map follows your actual answers.":
            "Проба показала уровень выше заявленного — карта настроена по твоим реальным ответам.",
        "The probe showed a lower level than you said — no problem, the map follows your actual answers.":
            "Проба показала уровень ниже заявленного — не страшно, карта настроена по твоим реальным ответам.",
        "A few short tasks to see what you already know. Write code right here in the field below; when ready, hit “Check”.":
            "Несколько коротких задач, чтобы понять, что ты уже знаешь. Пиши код прямо здесь, в поле ниже; когда готов — жми «Проверить».",
        "Task":
            "Задача",
        "Solve the problem":
            "Разобрать задачу",
        "⚠️ Accessibility permission missing":
            "⚠️ Нет доступа к Универсальному доступу",
        "⚠️ Screen Recording permission missing":
            "⚠️ Нет доступа к записи экрана",
        "Python Training…":
            "Тренировка Python…",
        "History…":
            "История разборов…",
        "Settings…":
            "Настройки…",
        "Check for Updates…":
            "Проверить обновления…",
        "About CodeCoach":
            "О CodeCoach",
        "Quit CodeCoach":
            "Выйти из CodeCoach",
        "A trainer for technical-interview problems":
            "Тренажёр по задачам для технических собеседований",
        "CodeCoach Settings":
            "Настройки CodeCoach",
        "History":
            "История разборов",
        "Python Training":
            "Тренировка Python",
        "Language":
            "Язык",
        "App and answer language":
            "Язык приложения и ответов",
        "Permissions":
            "Доступ",
        "Accessibility":
            "Универсальный доступ",
        "needed to hear the hotkey":
            "нужен, чтобы слышать горячую клавишу",
        "Screen Recording":
            "Запись экрана",
        "needed to capture the problem; restart CodeCoach after granting":
            "нужен, чтобы снимать условие задачи; после выдачи перезапустите CodeCoach",
        "Permission granted but not working — reset":
            "Разрешение уже выдано, но не работает — сбросить",
        "Open":
            "Открыть",
        "Claude access":
            "Доступ к Claude",
        "Claude subscription — via Claude Code":
            "Подписка Claude — через Claude Code",
        "Claude Code found; hints run on your subscription — no API key needed":
            "Claude Code найден, подсказки идут от подписки — ключ API не нужен",
        "install and log into Claude Code, or paste an API key below":
            "установите Claude Code и войдите в него, либо введите ключ API ниже",
        "sk-ant-… (not needed with Claude Code)":
            "sk-ant-… (не нужен, если есть Claude Code)",
        "Save":
            "Сохранить",
        "Key saved":
            "Ключ сохранён",
        "The key is stored at %@ with 0600 permissions. Without a key, hints run through Claude Code on your subscription; a key, when set, takes priority.":
            "Ключ хранится в %@ с правами 0600. Без ключа подсказки идут через Claude Code от вашей подписки; ключ, если задан, имеет приоритет.",
        "Hotkey":
            "Горячая клавиша",
        "Press a key…":
            "Нажмите клавишу…",
        "Cancel":
            "Отмена",
        "Change":
            "Изменить",
        "Press — new problem. Press again — next hint level. Esc — close.":
            "Нажатие — новая задача. Ещё раз — следующий уровень подсказки. Esc — закрыть.",
        "⚠️ This key types a character into the active window. Prefer a modifier or an F-key.":
            "⚠️ Эта клавиша печатает символ в активное окно. Лучше выбрать модификатор или F-клавишу.",
        "Solution":
            "Решение",
        "Code language":
            "Язык кода",
        "Detect from screen":
            "Определять по экрану",
        "Solution register":
            "Уровень разбора",
        "Junior":
            "Джун",
        "Middle":
            "Мидл",
        "Senior":
            "Синьор",
        "What grade the solution code targets: junior — simple and readable, senior — invariants and trade-offs.":
            "Каким по грейду должен быть код решения: джуну — просто и читаемо, синьору — с инвариантами и трейд-оффами.",
        "Code only, no explanations":
            "Только код, без пояснений",
        "The solution arrives as one code block — faster and paste-ready. In-code comments stay.":
            "Решение приходит одним блоком кода — быстрее и сразу вставляется. Комментарии внутри кода остаются.",
        "Show the solution right away":
            "Сразу показывать решение",
        "A register-comparison mode: every press is a fresh capture straight to level 3, no hint ladder. Turn off for actual practice.":
            "Режим для сравнения грейдов: каждое нажатие — новый снимок и сразу уровень 3, без лестницы подсказок. Для тренировки выключите.",
        "Keep history":
            "Хранить историю разборов",
        "Problems and answers live in %@. They are never written to logs.":
            "Задачи и ответы лежат в %@. В логи они не пишутся никогда.",
        "Nudge":
            "Намёк",
        "Approach":
            "Подход",
        "Capturing the screen…":
            "Снимаю экран…",
        "Reading the problem…":
            "Читаю задачу…",
        "the model is thinking":
            "модель думает",
        "s":
            "с",
        "Esc — close":
            "Esc — закрыть",
        "‹ › — levels · hotkey — next · Esc — close":
            "‹ › — уровни · хоткей — дальше · Esc — закрыть",
        "Hotkey — new problem · Esc — close":
            "Хоткей — новая задача · Esc — закрыть",
        "Hotkey again — next level · Esc — close":
            "Ещё раз хоткей — следующий уровень · Esc — закрыть",
        "Empty answer — try capturing again":
            "Пустой ответ — попробуйте снять экран ещё раз",
        "Retry":
            "Повторить",
        "Recapture at the same level":
            "Переснять экран этим же уровнем",
        "Open history":
            "Открыть историю разборов",
        "Copy code only":
            "Скопировать только код",
        "Copy the whole answer":
            "Скопировать весь ответ",
        "Previous level":
            "Предыдущий уровень",
        "Next of the already fetched":
            "Следующий из уже полученных",
        "Close (Esc)":
            "Закрыть (Esc)",
        "Select a problem":
            "Выберите задачу",
        "Solved problems on the left, newest first.":
            "Слева — разобранные задачи, свежие сверху.",
        "No description":
            "Без описания",
        "Delete":
            "Удалить",
        "Clear all":
            "Очистить всё",
        "Delete the entire history?":
            "Удалить всю историю разборов?",
        "Screenshots and answers will be permanently removed from disk.":
            "Скриншоты и ответы будут удалены с диска безвозвратно.",
        "Getting to know you":
            "Первое знакомство",
        "Knowledge map":
            "Карта знаний",
        "task %d of %d":
            "задача %d из %d",
        "Variables and types":
            "Переменные и типы",
        "Strings":
            "Строки",
        "Lists and tuples":
            "Списки и кортежи",
        "Dicts and sets":
            "Словари и множества",
        "Conditions and loops":
            "Условия и циклы",
        "Functions":
            "Функции",
        "Errors and exceptions":
            "Ошибки и исключения",
        "Classes and OOP":
            "Классы и ООП",
        "not started":
            "не начинал",
        "started":
            "начал",
        "confident":
            "уверенно",
        "mastered":
            "освоил",
        "Five short tasks to see what you already know. Write code right here in the field below; when ready, hit “Check”.":
            "Пять коротких задач, чтобы понять, что ты уже знаешь. Пиши код прямо здесь, в поле ниже; когда готов — жми «Проверить».",
        "Hit “Next” to get a task at your level.":
            "Нажми «Дальше» — получишь задачу под свой уровень.",
        "the mentor is looking…":
            "наставник смотрит…",
        "Your code":
            "Твой код",
        "Start":
            "Начать",
        "Next":
            "Дальше",
        "Check":
            "Проверить",
        "I give up":
            "Сдаюсь",
        "Stop":
            "Стоп",
        "Next →":
            "Дальше →",
        "No Claude access — install Claude Code (subscription) or paste an API key in CodeCoach settings":
            "Нет доступа к Claude — установите Claude Code (подписка) или введите ключ API в настройках CodeCoach",
        "Key rejected (401) — check it in settings":
            "Ключ не принят (401) — проверьте его в настройках",
        "Forbidden (403) — no access to this model":
            "Доступ запрещён (403) — нет прав на эту модель",
        "Too many requests (429) — wait a bit":
            "Слишком много запросов (429) — подождите немного",
        "The model is unavailable under zero data retention (30 days required)":
            "Модель недоступна при нулевом хранении данных в организации (нужно 30 дней)",
        "API-side failure (%d) — try again":
            "Сбой на стороне API (%d) — попробуйте ещё раз",
        "API error (%d): %@":
            "Ошибка API (%d): %@",
        "The model declined the request: %@":
            "Модель отклонила запрос: %@",
        "The model declined the request for safety reasons":
            "Модель отклонила запрос по правилам безопасности",
        "Cannot reach the API: %@":
            "Нет связи с API: %@",
        "No Screen Recording access — enable CodeCoach in Privacy & Security → Screen Recording":
            "Нет доступа к записи экрана — включите CodeCoach в «Конфиденциальность и безопасность → Запись экрана»",
        "Claude subscription limit reached — try later":
            "Лимит подписки Claude исчерпан — попробуйте позже",
        " (resets at %@)":
            " (сброс в %@)",
        "You are not logged into Claude Code — run claude login in a terminal":
            "Вы не вошли в Claude Code — выполните claude login в терминале",
        "Cannot reach Claude — check your connection":
            "Нет связи с Claude — проверьте интернет",
        "Claude Code finished without an answer (%@)":
            "Claude Code завершился без ответа (%@)",
        "Claude Code failed (code %d)":
            "Claude Code завершился с ошибкой (код %d)",
        "Could not save the key to %@":
            "Не удалось сохранить ключ в %@",
        "Could not determine which display to capture":
            "Не удалось определить экран для снимка",
        "Could not encode the screenshot":
            "Не удалось закодировать снимок экрана",
    ]

    static let uk: [String: String] = [
        "Ready to train": "Готовий тренуватися",
        "Something went wrong": "Щось пішло не так",
        "Name (optional)": "Ім'я (необов'язково)",
        "The trainer's mentor will use it. Stays on this Mac.":
            "Наставник у тренуванні звертатиметься на ім'я. Лишається на цьому Mac.",
        "%@: %@ — click to train this topic next":
            "%@: %@ — натисни, щоб тренувати цю тему наступною",
        "Under 13": "До 12",
        "13–17": "13–17",
        "Adult": "Дорослий",
        "Prefer not to say": "Не вказувати",
        "Never wrote code": "Ніколи не писав код",
        "Tried it, know the basics": "Пробував, знаю основи",
        "Write confidently": "Пишу впевнено",
        "Experienced developer": "Досвідчений розробник",
        "Quick setup": "Швидке налаштування",
        "Two optional questions to pick the right tone and difficulty. A short probe follows and adjusts everything to your actual level.":
            "Два необов'язкові запитання, щоб підібрати тон і складність. Далі — коротка проба, вона підлаштує все під твій реальний рівень.",
        "Age (optional)": "Вік (необов'язково)",
        "How well do you know Python? (optional)": "Наскільки добре ти знаєш Python? (необов'язково)",
        "Everything stays on this Mac and is used only to pick the tone and task difficulty.":
            "Усе лишається на цьому Mac і використовується лише для підбору тону та складності задач.",
        "Set up again: age, level and a fresh probe": "Налаштувати заново: вік, рівень і нова проба",
        "The probe showed a higher level than you said — the map follows your actual answers.":
            "Проба показала рівень вищий за заявлений — карта налаштована за твоїми реальними відповідями.",
        "The probe showed a lower level than you said — no problem, the map follows your actual answers.":
            "Проба показала рівень нижчий за заявлений — не страшно, карта налаштована за твоїми реальними відповідями.",
        "A few short tasks to see what you already know. Write code right here in the field below; when ready, hit “Check”.":
            "Кілька коротких задач, щоб зрозуміти, що ти вже знаєш. Пиши код просто тут, у полі нижче; коли готовий — тисни «Перевірити».",
        "Task":
            "Задача",
        "Solve the problem":
            "Розібрати задачу",
        "⚠️ Accessibility permission missing":
            "⚠️ Немає дозволу «Універсальний доступ»",
        "⚠️ Screen Recording permission missing":
            "⚠️ Немає дозволу на запис екрана",
        "Python Training…":
            "Тренування Python…",
        "History…":
            "Історія розборів…",
        "Settings…":
            "Налаштування…",
        "Check for Updates…":
            "Перевірити оновлення…",
        "About CodeCoach":
            "Про CodeCoach",
        "Quit CodeCoach":
            "Вийти з CodeCoach",
        "A trainer for technical-interview problems":
            "Тренажер із задач для технічних співбесід",
        "CodeCoach Settings":
            "Налаштування CodeCoach",
        "History":
            "Історія розборів",
        "Python Training":
            "Тренування Python",
        "Language":
            "Мова",
        "App and answer language":
            "Мова застосунку та відповідей",
        "Permissions":
            "Дозволи",
        "Accessibility":
            "Універсальний доступ",
        "needed to hear the hotkey":
            "потрібен, щоб чути гарячу клавішу",
        "Screen Recording":
            "Запис екрана",
        "needed to capture the problem; restart CodeCoach after granting":
            "потрібен, щоб знімати умову задачі; після надання перезапустіть CodeCoach",
        "Permission granted but not working — reset":
            "Дозвіл надано, але не працює — скинути",
        "Open":
            "Відкрити",
        "Claude access":
            "Доступ до Claude",
        "Claude subscription — via Claude Code":
            "Підписка Claude — через Claude Code",
        "Claude Code found; hints run on your subscription — no API key needed":
            "Claude Code знайдено, підказки йдуть від підписки — ключ API не потрібен",
        "install and log into Claude Code, or paste an API key below":
            "встановіть Claude Code і ввійдіть у нього, або введіть ключ API нижче",
        "sk-ant-… (not needed with Claude Code)":
            "sk-ant-… (не потрібен, якщо є Claude Code)",
        "Save":
            "Зберегти",
        "Key saved":
            "Ключ збережено",
        "The key is stored at %@ with 0600 permissions. Without a key, hints run through Claude Code on your subscription; a key, when set, takes priority.":
            "Ключ зберігається в %@ із правами 0600. Без ключа підказки йдуть через Claude Code від вашої підписки; ключ, якщо задано, має пріоритет.",
        "Hotkey":
            "Гаряча клавіша",
        "Press a key…":
            "Натисніть клавішу…",
        "Cancel":
            "Скасувати",
        "Change":
            "Змінити",
        "Press — new problem. Press again — next hint level. Esc — close.":
            "Натискання — нова задача. Ще раз — наступний рівень підказки. Esc — закрити.",
        "⚠️ This key types a character into the active window. Prefer a modifier or an F-key.":
            "⚠️ Ця клавіша друкує символ в активне вікно. Краще обрати модифікатор або F-клавішу.",
        "Solution":
            "Розв'язок",
        "Code language":
            "Мова коду",
        "Detect from screen":
            "Визначати з екрана",
        "Solution register":
            "Рівень розбору",
        "Junior":
            "Джун",
        "Middle":
            "Мідл",
        "Senior":
            "Сеньйор",
        "What grade the solution code targets: junior — simple and readable, senior — invariants and trade-offs.":
            "Яким за грейдом має бути код розв'язку: джуну — просто й читабельно, сеньйору — з інваріантами та трейд-офами.",
        "Code only, no explanations":
            "Лише код, без пояснень",
        "The solution arrives as one code block — faster and paste-ready. In-code comments stay.":
            "Розв'язок приходить одним блоком коду — швидше й одразу вставляється. Коментарі в коді лишаються.",
        "Show the solution right away":
            "Одразу показувати розв'язок",
        "A register-comparison mode: every press is a fresh capture straight to level 3, no hint ladder. Turn off for actual practice.":
            "Режим для порівняння грейдів: кожне натискання — новий знімок і одразу рівень 3, без драбини підказок. Для тренування вимкніть.",
        "Keep history":
            "Зберігати історію розборів",
        "Problems and answers live in %@. They are never written to logs.":
            "Задачі та відповіді лежать у %@. У логи вони не пишуться ніколи.",
        "Nudge":
            "Натяк",
        "Approach":
            "Підхід",
        "Capturing the screen…":
            "Знімаю екран…",
        "Reading the problem…":
            "Читаю задачу…",
        "the model is thinking":
            "модель думає",
        "s":
            "с",
        "Esc — close":
            "Esc — закрити",
        "‹ › — levels · hotkey — next · Esc — close":
            "‹ › — рівні · хоткей — далі · Esc — закрити",
        "Hotkey — new problem · Esc — close":
            "Хоткей — нова задача · Esc — закрити",
        "Hotkey again — next level · Esc — close":
            "Ще раз хоткей — наступний рівень · Esc — закрити",
        "Empty answer — try capturing again":
            "Порожня відповідь — спробуйте зняти екран ще раз",
        "Retry":
            "Повторити",
        "Recapture at the same level":
            "Перезняти екран цим самим рівнем",
        "Open history":
            "Відкрити історію розборів",
        "Copy code only":
            "Скопіювати лише код",
        "Copy the whole answer":
            "Скопіювати всю відповідь",
        "Previous level":
            "Попередній рівень",
        "Next of the already fetched":
            "Наступний з уже отриманих",
        "Close (Esc)":
            "Закрити (Esc)",
        "Select a problem":
            "Оберіть задачу",
        "Solved problems on the left, newest first.":
            "Ліворуч — розібрані задачі, свіжі згори.",
        "No description":
            "Без опису",
        "Delete":
            "Видалити",
        "Clear all":
            "Очистити все",
        "Delete the entire history?":
            "Видалити всю історію розборів?",
        "Screenshots and answers will be permanently removed from disk.":
            "Скриншоти та відповіді буде безповоротно видалено з диска.",
        "Getting to know you":
            "Перше знайомство",
        "Knowledge map":
            "Карта знань",
        "task %d of %d":
            "задача %d з %d",
        "Variables and types":
            "Змінні й типи",
        "Strings":
            "Рядки",
        "Lists and tuples":
            "Списки й кортежі",
        "Dicts and sets":
            "Словники й множини",
        "Conditions and loops":
            "Умови й цикли",
        "Functions":
            "Функції",
        "Errors and exceptions":
            "Помилки й винятки",
        "Classes and OOP":
            "Класи й ООП",
        "not started":
            "не починав",
        "started":
            "почав",
        "confident":
            "упевнено",
        "mastered":
            "опанував",
        "Five short tasks to see what you already know. Write code right here in the field below; when ready, hit “Check”.":
            "П'ять коротких задач, щоб зрозуміти, що ти вже знаєш. Пиши код просто тут, у полі нижче; коли готовий — тисни «Перевірити».",
        "Hit “Next” to get a task at your level.":
            "Натисни «Далі» — отримаєш задачу під свій рівень.",
        "the mentor is looking…":
            "наставник дивиться…",
        "Your code":
            "Твій код",
        "Start":
            "Почати",
        "Next":
            "Далі",
        "Check":
            "Перевірити",
        "I give up":
            "Здаюся",
        "Stop":
            "Стоп",
        "Next →":
            "Далі →",
        "No Claude access — install Claude Code (subscription) or paste an API key in CodeCoach settings":
            "Немає доступу до Claude — встановіть Claude Code (підписка) або введіть ключ API в налаштуваннях CodeCoach",
        "Key rejected (401) — check it in settings":
            "Ключ не прийнято (401) — перевірте його в налаштуваннях",
        "Forbidden (403) — no access to this model":
            "Доступ заборонено (403) — немає прав на цю модель",
        "Too many requests (429) — wait a bit":
            "Забагато запитів (429) — зачекайте трохи",
        "The model is unavailable under zero data retention (30 days required)":
            "Модель недоступна за нульового зберігання даних в організації (потрібно 30 днів)",
        "API-side failure (%d) — try again":
            "Збій на боці API (%d) — спробуйте ще раз",
        "API error (%d): %@":
            "Помилка API (%d): %@",
        "The model declined the request: %@":
            "Модель відхилила запит: %@",
        "The model declined the request for safety reasons":
            "Модель відхилила запит за правилами безпеки",
        "Cannot reach the API: %@":
            "Немає зв'язку з API: %@",
        "No Screen Recording access — enable CodeCoach in Privacy & Security → Screen Recording":
            "Немає доступу до запису екрана — увімкніть CodeCoach у «Конфіденційність і безпека → Запис екрана»",
        "Claude subscription limit reached — try later":
            "Ліміт підписки Claude вичерпано — спробуйте пізніше",
        " (resets at %@)":
            " (скидання о %@)",
        "You are not logged into Claude Code — run claude login in a terminal":
            "Ви не ввійшли в Claude Code — виконайте claude login у терміналі",
        "Cannot reach Claude — check your connection":
            "Немає зв'язку з Claude — перевірте інтернет",
        "Claude Code finished without an answer (%@)":
            "Claude Code завершився без відповіді (%@)",
        "Claude Code failed (code %d)":
            "Claude Code завершився з помилкою (код %d)",
        "Could not save the key to %@":
            "Не вдалося зберегти ключ у %@",
        "Could not determine which display to capture":
            "Не вдалося визначити екран для знімка",
        "Could not encode the screenshot":
            "Не вдалося закодувати знімок екрана",
    ]
}

/// Translate an English base string.
func L(_ en: String) -> String { Localization.shared.translate(en) }

/// Translate an English format string, then substitute the arguments.
func LF(_ en: String, _ args: CVarArg...) -> String {
    String(format: Localization.shared.translate(en), arguments: args)
}
