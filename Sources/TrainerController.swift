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
        profile = Self.loadProfile()
        probeIndex = profile.probeDone ? nil : 0
    }

    var isBusy: Bool { phase == .generating || phase == .responding }

    var currentTaskTitle: String {
        taskText.split(separator: "\n").first.map {
            $0.replacingOccurrences(of: "НАЗВАНИЕ:", with: "").trimmingCharacters(in: .whitespaces)
        } ?? "Задача"
    }

    // MARK: - Session flow

    /// "Начать" / "Дальше": settle the finished task into the map, then fetch
    /// the next one (probe order while probing, weakest topic afterwards).
    func nextTask() {
        guard !isBusy else { return }
        settleCurrentTask()

        let topic: Trainer.Topic
        if let index = probeIndex {
            if index >= Trainer.probeTopics.count {
                finishProbe()
                topic = Trainer.nextTopic(for: profile)
            } else {
                topic = Trainer.probeTopics[index]
            }
        } else {
            topic = Trainer.nextTopic(for: profile)
        }
        currentTopic = topic
        lastVerdict = nil
        gaveUp = false
        taskText = ""
        responseText = ""
        codeInput = ""
        phase = .generating
        Log.d("trainer: generating topic=\(topic.rawValue) probe=\(probeIndex.map(String.init) ?? "-")")

        run(collectInto: \.taskText,
            userText: TrainerPrompts.generateTask(
                topic: topic, level: profile.level(of: topic),
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
            probeIndex = index + 1
        } else {
            profile = Trainer.updated(profile, topic: topic, verdict: verdict, gaveUp: gaveUp)
        }
        profile.solved.append(Trainer.SolvedTask(
            topic: topic, title: currentTaskTitle, date: Date(),
            verdict: gaveUp ? "сдался" : verdict.rawValue))
        persist()
    }

    private func finishProbe() {
        profile.map = Trainer.mapFromProbe(probeVerdicts)
        profile.probeDone = true
        probeIndex = nil
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
                    system: TrainerPrompts.system, userText: userText,
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
