# ThreadHaven

A lightweight native macOS app for keeping track of your Claude Code chats.

ThreadHaven lists every Claude Code session on your Mac, tells you which ones are working, waiting for your approval or done, and takes you to the right terminal tab in one click. It lives in your menu bar and a small window, and it never touches your transcripts.

## Why it saves tokens

Every reply re-reads the whole conversation, so the size of a chat matters more than the length of your prompts. Letting chats grow, or coming back to a big chat after its prompt cache expired, quietly multiplies what each reply costs against your plan.

Measured with `make stats` on one developer's interactive Claude Code sessions over 14 days (47 sessions, 19,149 replies):

| Measure | Result |
| --- | --- |
| Average context per reply | 412k tokens |
| Context before the first prompt (median) | 49k tokens |
| Cache writes caused by returning to a cold chat | 78% |
| Context processed if chats were compacted at 150k (simulated) | 74% less, about 3.8× more replies for the same volume |

How to read this: the numbers measure context volume, which drives API cost and usage limits. Anthropic does not publish exactly how cached tokens count toward subscription limits, so treat the factor as what compaction can give at most, not as a guarantee. The simulation restarts each compacted chat from its first-reply context plus a 20k summary and counts the context read by the compaction itself. Compaction keeps a summary, not every detail.

Measure your own usage with `make stats`. The report is computed locally from `~/.claude/projects` and never leaves your Mac.

## Features

- **All chats in one list.** Running chats on top, recent ones below, grouped by status, searchable by title, folder or last prompt.
- **Instant switching.** Double-click a chat or press <kbd>⌘1</kbd>–<kbd>⌘9</kbd> to jump straight to its tab in Terminal or iTerm2.
- **Notifications.** Get a notification when a chat finishes its turn or needs your approval. Clicking it opens the right tab.
- **New chat in a folder.** <kbd>⌘N</kbd> starts `claude --continue` in any recent folder, so you pick up the previous thread right away.
- **Context awareness.** Every chat shows how full its context window is. Send `/compact` with one click, or let ThreadHaven do it automatically above a threshold you choose.
- **Dictation.** Dictate prompts with on-device speech recognition, then turn a rough note into a clean prompt with one click (uses your own `claude` CLI).
- **Native and small.** SwiftUI, a universal binary under 3 MB, light and dark mode, English and Polish.

## Requirements

- macOS 14 Sonoma or later
- [Claude Code](https://docs.claude.com/en/docs/claude-code) CLI
- Swift 6 toolchain (Xcode 16 or later) to build from source

## Install

### Download

Grab the latest `ThreadHaven-x.y.z.zip` from the [releases page](../../releases), unzip it and move `ThreadHaven.app` to your Applications folder.

Official releases are signed with a Developer ID and notarized by Apple. If you run a build that is not notarized, macOS will refuse to open it the first time; right-click the app and choose **Open**, or run `xattr -dr com.apple.quarantine ThreadHaven.app`.

### Build from source

```sh
git clone <repository-url> threadhaven
cd threadhaven
make run
```

`make run` builds a release binary, wraps it into `ThreadHaven.app`, installs it into `~/Applications` and opens it. Use `make app` to only build `build/ThreadHaven.app`, or grab a ready-made zip from the releases page.

On first launch, click **Install hook** in the sidebar. ThreadHaven adds a small hook to `~/.claude/settings.json` (your existing hooks are kept, and the file is backed up to `settings.json.threadhaven-backup` first). Restart running Claude Code sessions to pick it up.

## How it works

ThreadHaven combines two read-only sources:

| Source | Location | Used for |
| --- | --- | --- |
| Transcripts | `~/.claude/projects/**/*.jsonl` | Titles, folders, messages, context usage |
| Hook events | `~/.threadhaven/events.jsonl` | Live status, notifications, terminal tab |

The hook is a tiny POSIX shell script (`~/.threadhaven/hook.sh`) registered for `SessionStart`, `UserPromptSubmit`, `PostToolUse`, `Notification`, `Stop` and `SessionEnd`. It appends one JSON line per event together with the terminal and TTY of the session, and rotates the file at 5 MB.

Switching tabs and sending prompts use AppleScript, so macOS will ask once for permission to control your terminal.

## Privacy

Everything stays on your Mac. ThreadHaven has no server, no analytics and no network access of its own. Dictation uses Apple's on-device speech recognition when available. Prompt polishing runs your local `claude` CLI, so that text goes to Anthropic the same way your other Claude Code prompts do.

See [SECURITY.md](SECURITY.md) for details and how to report a vulnerability.

## Permissions

| Permission | Why |
| --- | --- |
| Notifications | Alerts when a chat finishes or needs approval |
| Automation (Terminal / iTerm2) | Switching to a chat's tab and sending prompts |
| Microphone, Speech Recognition | Dictation, only when you use it |

## Terminal support

| Terminal | Switch to tab | Send prompt | New chat |
| --- | --- | --- | --- |
| Terminal | ✓ | ✓ | ✓ |
| iTerm2 | ✓ | ✓ | ✓ |
| Ghostty | app only | – | ✓ |
| Others | app only | – | – |

## Uninstall

Open **Settings → Notifications** and click **Remove** next to the hook, then delete `ThreadHaven.app` and `~/.threadhaven`.

## Development

```sh
swift build
make test
make app
```

On Linux, `swift build --product threadhaven-stats` builds the stats command and `swift test` runs the core tests.

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines and the release process, and [CHANGELOG.md](CHANGELOG.md) for what changed in each version.

## Roadmap

Next up are token savings (0.2), a workspace manager for skills, MCP servers and project knowledge (0.3) and team features (0.4), followed by Linux, iPhone and Android apps. See [ROADMAP.md](ROADMAP.md) for details.

## License

[MIT](LICENSE)

ThreadHaven is an independent project and is not affiliated with or endorsed by Anthropic. Claude and Claude Code are trademarks of Anthropic.
