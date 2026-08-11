import AppKit
import SwiftUI

/// Drives one training session: probe or regular, task by task. The learner
/// writes code in their own editor (PyCharm); "Проверить" captures the screen
/// and reviews THEIR attempt. All model output streams into the window.
@MainActor
final class TrainerController: ObservableObject {

    enum Phase: Equatable {
        case idle              // no task yet (start of session)
        case generating        // task being written by the model
        case working           // task on screen, learner is coding
        case responding        // review/hint/solution streaming in
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var taskText = ""
    @Published var responseText = ""
    /// The learner's code, typed right in the trainer window.
    @Published var codeInput = ""
    @Published var profile: Trainer.Profile
    @Published var currentTopic: Trainer.Topic?
    /// Probe position: nil when past the probe, else index into probeTopics.
    @Published var probeIndex: Int?
    /// One-shot line after the probe when it disagreed with the
    /// self-assessment; cleared on the next task.
    @Published var probeNote: String?

    /// The self-assessment now lives in the app-wide profile level; the
    /// trainer profile's own copy is a fallback for profiles from before the
    /// unification.
    var effectiveSelfLevel: Trainer.SelfLevel? {
        Settings.shared.userLevel?.trainerLevel ?? profile.selfLevel
    }

    /// The probe list sized by the self-assessment.
    var activeProbeTopics: [Trainer.Topic] { Trainer.probeTopics(for: effectiveSelfLevel) }

    /// Topic explicitly chosen by clicking its chip; overrides the automatic
    /// weakest-topic pick for the next task, then clears.
    private var chosenTopic: Trainer.Topic?

    /// Verdict of the latest review of the current task; drives the map update
    /// when the learner moves on.
    private var lastVerdict: Trainer.Verdict?
    private var gaveUp = false
    private var probeVerdicts: [Trainer.Topic: Trainer.Verdict] = [:]
    private var task: Task<Void, Never>?

    private static let profileURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CodeCoach/trainer.json")

    init() {
        let loaded = Self.loadProfile()
        profile = loaded
        // Resume the probe where it stopped: the settled verdicts are the
        // position. A fresh counter after a relaunch read as a broken one.
        for (raw, verdictRaw) in loaded.probeVerdicts ?? [:] {
            if let topic = Trainer.Topic(rawValue: raw),
               let verdict = Trainer.Verdict(rawValue: verdictRaw) {
                probeVerdicts[topic] = verdict
            }
        }
        probeIndex = loaded.probeDone ? nil : probeVerdicts.count
    }

    var isBusy: Bool { phase == .generating || phase == .responding }

    /// Saves the onboarding answers. Both are optional; the probe corrects
    /// whatever they claim.
    func completeOnboarding(age: Trainer.AgeBand?, level: UserLevel?) {
        profile.ageBand = age
        profile.selfLevel = level?.trainerLevel
        // The level is a property of the person, not of the trainer: the same
        // answer drives the interview ladder's register.
        Settings.shared.userLevel = level
        profile.onboardingDone = true
        persist()
        Log.d("trainer: onboarding age=\(age?.rawValue ?? "-") level=\(level?.rawValue ?? "-")")
        nextTask()
    }

    /// "Set up again": redo onboarding and the probe from scratch. The task
    /// history stays — it is a log, not configuration.
    func redoSetup() {
        guard !isBusy else { return }
        profile.onboardingDone = false
        profile.probeDone = false
        profile.map = [:]
        profile.probeVerdicts = nil
        probeVerdicts = [:]
        chosenTopic = nil
        probeIndex = 0
        currentTopic = nil
        taskText = ""
        responseText = ""
        codeInput = ""
        probeNote = nil
        phase = .idle
        persist()
        Log.d("trainer: setup reset")
    }

    var currentTaskTitle: String {
        taskText.split(separator: "\n").first.map {
            $0.replacingOccurrences(of: "TITLE:", with: "").trimmingCharacters(in: .whitespaces)
        } ?? L("Task")
    }

    // MARK: - Session flow

    /// "Начать" / "Дальше": settle the finished task into the map, then fetch
    /// the next one (probe order while probing, weakest topic afterwards).
    func nextTask() {
        guard !isBusy else { return }
        settleCurrentTask()

        let topic: Trainer.Topic
        if let index = probeIndex {
            if index >= activeProbeTopics.count {
                finishProbe()
                topic = Trainer.nextTopic(for: profile)
            } else {
                topic = activeProbeTopics[index]
            }
        } else {
            topic = chosenTopic ?? Trainer.nextTopic(for: profile)
        }
        chosenTopic = nil
        currentTopic = topic
        lastVerdict = nil
        gaveUp = false
        taskText = ""
        responseText = ""
        codeInput = ""
        probeNote = nil
        phase = .generating
        Log.d("trainer: generating topic=\(topic.rawValue) probe=\(probeIndex.map(String.init) ?? "-")")

        // During the probe the difficulty comes from the self-assessment, not
        // from the (still empty) map.
        let level = probeIndex != nil
            ? Trainer.probeSeedLevel(for: effectiveSelfLevel)
            : profile.level(of: topic)
        run(collectInto: \.taskText,
            userText: TrainerPrompts.generateTask(
                topic: topic, level: level,
                avoidTitles: Trainer.recentTitles(of: profile)),
            imagePNG: nil,
            doneState: .working)
    }

    /// "Проверить": level-0 review of the code typed in the window. No
    /// screenshot — the trainer is a single surface, and the exact text beats
    /// a picture of it anyway.
    func review() {
        guard case .working = phaseOrResponding(), !taskText.isEmpty else { return }
        let code = codeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        responseText = ""
        phase = .responding
        streamResponse(TrainerPrompts.review(taskText: taskText, code: code),
                       imagePNG: nil) { [weak self] answer in
            guard let self else { return }
            self.lastVerdict = Trainer.parseVerdict(from: answer)
            Log.d("trainer: review verdict=\(self.lastVerdict?.rawValue ?? "?")")
        }
    }

    /// "Намёк": a nudge without the path.
    func hint() {
        guard case .working = phaseOrResponding(), !taskText.isEmpty else { return }
        responseText = ""
        phase = .responding
        streamResponse(TrainerPrompts.hint(taskText: taskText), imagePNG: nil)
    }

    /// "Сдаюсь": the taught solution; the topic takes the hit when settling.
    func giveUp() {
        guard case .working = phaseOrResponding(), !taskText.isEmpty else { return }
        gaveUp = true
        responseText = ""
        phase = .responding
        streamResponse(TrainerPrompts.solution(taskText: taskText), imagePNG: nil)
    }

    /// The way out of a failed request. A failed GENERATION left no task, so
    /// every button used to be disabled — a dead end the owner hit mid-probe.
    func recoverFromFailure() {
        guard case .failed = phase else { return }
        if taskText.isEmpty {
            phase = .idle
            nextTask()          // regenerate the same position
        } else {
            phase = .working    // task intact — the failure was a review/hint
        }
    }

    /// Chip click: train THIS topic next. Not during the probe (its sequence
    /// is the measurement) and not mid-request.
    func chooseTopic(_ topic: Trainer.Topic) {
        guard probeIndex == nil, !isBusy else { return }
        chosenTopic = topic
        nextTask()
    }

    func cancel() {
        task?.cancel()
        task = nil
        if phase == .generating { phase = .idle }
        if phase == .responding { phase = .working }
    }

    // MARK: - Internals

    /// While a response streams the learner is still "working" on the task —
    /// review/hint may be asked several times per task.
    private func phaseOrResponding() -> Phase {
        phase == .responding ? .working : phase
    }

    private func settleCurrentTask() {
        guard let topic = currentTopic, !taskText.isEmpty else { return }
        let verdict = lastVerdict ?? .failed

        if let index = probeIndex {
            probeVerdicts[topic] = gaveUp ? .failed : verdict
            profile.probeVerdicts = probeVerdicts.reduce(into: [:]) {
                $0[$1.key.rawValue] = $1.value.rawValue
            }
            probeIndex = index + 1
        } else {
            profile = Trainer.updated(profile, topic: topic, verdict: verdict, gaveUp: gaveUp)
        }
        profile.solved.append(Trainer.SolvedTask(
            topic: topic, title: currentTaskTitle, date: Date(),
            verdict: gaveUp ? "gave up" : verdict.rawValue))
        persist()
    }

    private func finishProbe() {
        var map = Trainer.mapFromProbe(probeVerdicts)
        // Unprobed topics take the self-assessment prior, so an experienced
        // person is not dragged through OOP from zero. The first real task per
        // topic corrects it either way.
        let prior = Trainer.priorLevel(for: effectiveSelfLevel)
        for topic in Trainer.Topic.allCases where map[topic.rawValue] == nil {
            map[topic.rawValue] = prior
        }
        profile.map = map
        profile.probeDone = true
        profile.probeVerdicts = nil
        probeIndex = nil

        switch Trainer.probeSurprise(selfLevel: effectiveSelfLevel, verdicts: probeVerdicts) {
        case .higher:
            probeNote = L("The probe showed a higher level than you said — the map follows your actual answers.")
        case .lower:
            probeNote = L("The probe showed a lower level than you said — no problem, the map follows your actual answers.")
        case .asExpected:
            probeNote = nil
        }
        persist()
        Log.d("trainer: probe finished, map=\(profile.map.mapValues(\.rawValue))")
    }

    /// Fires a generic trainer call and streams the answer into the given
    /// published property.
    private func run(
        collectInto keyPath: ReferenceWritableKeyPath<TrainerController, String>,
        userText: String, imagePNG: Data?, doneState: Phase,
        onDone: (@MainActor (String) -> Void)? = nil
    ) {
        task = Task { [weak self] in
            guard let self else { return }
            var collected = ""
            do {
                try await ClaudeCodeCLI.run(
                    system: TrainerPrompts.system(
                        age: self.profile.ageBand, name: Settings.shared.userName),
                    userText: userText,
                    imagePNG: imagePNG, model: "sonnet", label: "trainer"
                ) { [weak self] event in
                    guard case .text(let text) = event else { return }
                    collected += text
                    Task { @MainActor in self?[keyPath: keyPath] += text }
                }
                guard !Task.isCancelled else { return }
                self.phase = doneState
                onDone?(collected)
            } catch {
                if !Task.isCancelled { self.fail(error) }
            }
            self.task = nil
        }
    }

    private func streamResponse(
        _ userText: String, imagePNG: Data?, onDone: (@MainActor (String) -> Void)? = nil
    ) {
        run(collectInto: \.responseText, userText: userText, imagePNG: imagePNG,
            doneState: .working, onDone: onDone)
    }

    private func fail(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        phase = .failed(message)
        Log.d("trainer: failed — \(message)")
    }

    // MARK: - Persistence

    private static func loadProfile() -> Trainer.Profile {
        guard let data = try? Data(contentsOf: profileURL),
              let profile = try? History.makeDecoder().decode(Trainer.Profile.self, from: data)
        else { return Trainer.Profile() }
        return profile
    }

    private func persist() {
        let snapshot = profile
        Task.detached {
            guard let data = try? History.makeEncoder().encode(snapshot) else { return }
            try? data.write(to: Self.profileURL, options: .atomic)
        }
    }
}
