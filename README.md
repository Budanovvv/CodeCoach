# CodeCoach

**A trainer for algorithmic problems, for technical-interview preparation.**

Press a key — the screen with the problem statement is captured. A hint
unfolds under the menu bar. Press again — the hint goes one level deeper.

Three levels, and they are the whole point:

| Level | What it gives | What it deliberately withholds |
| --- | --- | --- |
| **Nudge** | how the problem was understood, a guiding observation, which data structure fits | the algorithm, complexity, code |
| **Approach** | the algorithm step by step, complexity, edge cases | code |
| **Solution** | working code and what the interviewer will probe | — |

The ladder exists so that you solve it yourself. The first level will not let
you transcribe an answer even if you badly want to — and the third takes two
deliberate presses to reach. This is a tool for preparing **before** an
interview, not during one.

There is also a separate **Python training mode** for a learner: the app
generates tasks against a per-topic knowledge map, the learner types code
right in the window, and a mentor reviews the attempt without leaking the
solution.

## Requirements

- macOS 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- Claude access: a subscription (via an installed [Claude Code](https://claude.com/claude-code)) or an API key

## Building

```bash
./build.sh              # Release
./build.sh --install    # Release + install into /Applications
./build.sh --debug      # fast Debug build
./test.sh               # unit tests
./release.sh            # signed, notarized DMGs + Sparkle appcast
```

The Xcode project is generated from `project.yml` — the `.xcodeproj` itself
is not committed.

## First run

1. Give the app Claude access — either way works:
   - **Claude subscription** (Pro/Max): an installed and logged-in
     [Claude Code](https://claude.com/claude-code) is enough. CodeCoach runs
     requests through its headless mode (`claude -p`) — no key needed, usage
     is billed to the subscription. A subscription does not grant direct
     Messages-API access, which is why the path goes through Claude Code.
   - **API key**: paste it in Settings. It is stored at
     `~/.config/codecoach/api-key` with `0600` permissions. A key, when set,
     takes priority over the subscription.
2. Grant two macOS permissions:
   - **Accessibility** — to hear the hotkey;
   - **Screen Recording** — to capture the problem statement.

The app lives in the menu bar and takes no Dock space.

## Controls

| Action | What happens |
| --- | --- |
| Right ⌘ | new problem: a screen capture and the first hint level |
| Right ⌘ again | the next level for the same problem |
| `Esc` | close the panel and end the session |

The key is changed in Settings by pressing the new one. Right ⌘ is the
default because almost nobody uses it, and because right ⌥ is taken by
[Dictate](https://github.com/Budanovvv/Dictate).

## Languages

The UI and the model's answers follow one setting: English, Russian or
Ukrainian (or the system language). English is the base.

## Privacy

Screenshots and solved problems are stored only on your Mac, in
`~/Library/Application Support/CodeCoach`. They are never written to logs —
logs carry only state transitions and error shapes. History can be switched
off in Settings.

Solving a problem requires a Claude request: the screenshot goes to
Anthropic. That is the only thing that leaves the computer.

## License

[GPL-3.0](LICENSE) — same as [Dictate](https://github.com/Budanovvv/Dictate).

## Stack

Swift, SwiftUI and AppKit. The global hotkey is a `CGEventTap`, the capture
is ScreenCaptureKit, the analysis is Claude with the answer streamed straight
into the panel. Updates ship through Sparkle.
