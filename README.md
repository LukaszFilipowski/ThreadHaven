# ThreadHaven

A native macOS home for your Claude Code and Codex CLI chats.

ThreadHaven lists every chat on your Mac grouped by project, shows which ones are working, waiting for your approval or done, and runs them in a real terminal right inside the app. Switch between chats without losing a running session, get a notification when one needs you, and keep an eye on how many tokens each chat burns. Your transcripts are only read, never changed.

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

**Chats**

- **A real terminal in the app.** Open any chat and keep working with Claude Code or Codex exactly as in Terminal: slash commands, approvals and shortcuts included. Chats keep running while you switch between them, and the History tab shows the conversation as readable messages.
- **One list, grouped by project.** Running chats stay on top in a fixed order, the rest are grouped by project with counts and collapsible sections. Star a chat to keep it under Favorites, search by title, folder, branch or last prompt.
- **Close a chat in one click.** The ✕ next to a running chat stops Claude or Codex and everything it started, such as running commands and MCP servers. The conversation stays in the list and can be resumed.
- **Keep the history clean.** Delete a finished chat from its context menu. The conversation goes to the Trash, so you can put it back.
- **Private mode.** One toolbar switch hides everything but the chats that are running right now, handy when you share your screen.
- **New chat in a folder.** <kbd>⌘N</kbd> starts a chat in any recent folder, continuing the previous thread when it is not already open.
- **Quick switcher.** Press <kbd>⌃⌥Space</kbd> anywhere to search your chats and jump to one; <kbd>⌘1</kbd>–<kbd>⌘9</kbd> switch between running chats in the window.
- **Notifications.** A notification, a Dock badge and a Dock bounce when a chat finishes its turn or waits for your approval.
- **Codex CLI.** Codex sessions show up next to Claude Code chats, with live status through the optional notify script.

**Tokens**

- **Context at a glance.** Every chat shows how full its context window is, with a token usage panel for re-read context, cold cache rebuilds and the heaviest tool results.
- **Compaction and handoff.** Send `/compact` with one click or automatically above a token threshold, get a warning before continuing a chat whose prompt cache has expired, or hand a long chat off to a fresh one through a short note.

**Projects**

- **Workspace window** (<kbd>⇧⌘I</kbd>). What every chat in a project starts with, per-project switches for MCP servers and plugins, the project's CLAUDE.md, memory and handoff notes, and the plugin marketplaces it shares with your team.

**Everywhere else**

- **Remote access (preview).** Check chats, get notifications and send prompts from your phone over Tailscale. See [Remote access](#remote-access).
- **Linux (preview).** A GTK app that lists your sessions and resumes them. See [Linux](#linux).
- **Native and small.** SwiftUI, light and dark mode, English and Polish.
## Requirements

- macOS 15 Sequoia or later
- [Claude Code](https://docs.claude.com/en/docs/claude-code) CLI
- Swift 6 toolchain (Xcode 16 or later) to build from source

## Install

### Download

Grab the latest `ThreadHaven-x.y.z.zip` from the [releases page](../../releases), unzip it and move `ThreadHaven.app` to your Applications folder.

Releases are not signed with an Apple Developer ID yet, so macOS refuses to open the app the first time. Right-click it and choose **Open**, or run `xattr -dr com.apple.quarantine ThreadHaven.app`. The release workflow signs and notarizes builds automatically once Developer ID secrets are configured (see [CONTRIBUTING.md](CONTRIBUTING.md)).

### Build from source

```sh
git clone <repository-url> threadhaven
cd threadhaven
make run
```

`make run` builds a release binary, wraps it into `ThreadHaven.app`, installs it into `~/Applications` and opens it. Use `make app` to only build `build/ThreadHaven.app`, or grab a ready-made zip from the releases page.

On first launch, click **Install hook** in the sidebar. ThreadHaven adds a small hook to `~/.claude/settings.json` (your existing hooks are kept, and the file is backed up to `settings.json.threadhaven-backup` first). Restart running Claude Code sessions to pick it up.

## How it works

ThreadHaven combines these read-only sources:

| Source | Location | Used for |
| --- | --- | --- |
| Transcripts | `~/.claude/projects/**/*.jsonl` | Titles, folders, messages, context usage |
| Hook events | `~/.threadhaven/events.jsonl` | Live status, notifications, terminal tab |
| Codex CLI sessions | `~/.codex/sessions/**/rollout-*.jsonl` | Titles, folders, messages, context usage |
| Codex notify events | `~/.threadhaven/events.jsonl` | Live status and notifications for Codex CLI |

The hook is a tiny POSIX shell script (`~/.threadhaven/hook.sh`) registered for `SessionStart`, `UserPromptSubmit`, `PostToolUse`, `Notification`, `Stop` and `SessionEnd`. It appends one JSON line per event together with the terminal and TTY of the session, and rotates the file at 5 MB.

For Codex CLI, **Settings → Notifications → Codex CLI notify** sets the top-level `notify` key in `~/.codex/config.toml` to `~/.threadhaven/codex-notify.sh`. Codex runs it after every turn, and it appends one line with the session id, folder, last reply and terminal, never your prompts. Only that line of the file changes, and the original is backed up once to `config.toml.threadhaven-backup`. If `notify` already runs another program, ThreadHaven leaves it alone; call `~/.threadhaven/codex-notify.sh` from your program with the same JSON argument to use both. Codex reports only finished turns, so there is no approval status for Codex sessions.

Chats opened in ThreadHaven run in an embedded terminal ([SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)) through your login shell, so they see the same `PATH` and environment as in Terminal. For chats that run in Terminal or iTerm2, switching to their tab and sending a prompt use AppleScript, so macOS asks once for permission to control your terminal.

## Remote access

Remote access is a preview of a phone companion that works from any network through [Tailscale](https://tailscale.com). ThreadHaven serves a small web app on your Mac and you publish it inside your tailnet with `tailscale serve`. Nothing is exposed to the public internet.

1. Install Tailscale on your Mac and your phone and sign in to the same tailnet.
2. Turn on **Settings → Remote access**. ThreadHaven starts a server on `127.0.0.1` and shows a `tailscale serve --bg --https=443 http://127.0.0.1:<port>` command. Run it once in a terminal.
3. Scan the QR code with your phone. It opens the web app and pairs that phone with its own key.
4. Add the page to your home screen and tap **Turn on notifications** to get a push when a chat finishes or needs your approval (iOS 16.4 or later, or Android).

By default only your own Tailscale user can connect; Settings can allow other tailnet users. From the phone you can see running and recent chats, read their recent messages and send a prompt to a chat that runs in Terminal or iTerm2. Every remote prompt also shows a notification on the Mac. Approving permission prompts and starting new chats stay on the Mac for now, and a chat that waits for an approval does not accept remote prompts. Each paired device can be revoked in Settings, and turning remote access off, or leaving it idle for the period you choose, signs out every device. See [SECURITY.md](SECURITY.md#remote-access) for the protections and [the design](docs/design/remote-access.md) for what comes next.

## Privacy

Everything stays on your Mac. ThreadHaven has no server in the cloud and no analytics. Its only network features are remote access, which is off by default, and the encrypted push notifications it sends to the phones you pair. Dictation uses Apple's on-device speech recognition when available. Prompt polishing runs your local `claude` CLI, so that text goes to Anthropic the same way your other Claude Code prompts do.

See [SECURITY.md](SECURITY.md) for details and how to report a vulnerability.

## Permissions

| Permission | Why |
| --- | --- |
| Notifications | Alerts when a chat finishes or needs approval |
| Automation (Terminal / iTerm2) | Only for chats that run in those apps: switching to their tab and sending prompts |
| Microphone, Speech Recognition | Dictation, only when you use it |
## Terminal support

Chats run best inside ThreadHaven. Chats that are already open in another terminal stay there, and ThreadHaven can still follow them:

| Terminal | Live status | Switch to tab | Send prompt |
| --- | --- | --- | --- |
| ThreadHaven | ✓ | ✓ | ✓ |
| Terminal | ✓ | ✓ | ✓ |
| iTerm2 | ✓ | ✓ | ✓ |
| Ghostty and others | ✓ | app only | – |
## Uninstall

Open **Settings → Notifications** and click **Remove** next to the hook (and next to Codex CLI notify if you installed it), then delete `ThreadHaven.app` and `~/.threadhaven`.

## Linux

Status: preview. The Linux app is a GTK4 and libadwaita app built with [Adwaita for Swift](https://git.aparoksha.dev/aparoksha/adwaita-swift). It lists your Claude Code and Codex CLI sessions from the last 14 days with their project and context usage, shows recent messages and token usage of a session, and resumes a session in your terminal. Live status, notifications and the hook are macOS only for now.

The Flatpak reads `~/.claude` and `~/.codex` read-only and uses `flatpak-spawn --host` only to open a terminal (`xdg-terminal-exec`, `kgx`, `gnome-terminal`, `konsole` or `x-terminal-emulator`) that runs `claude --resume` or `codex resume`.

Every CI run builds a `ThreadHaven.flatpak` bundle you can download from the run's artifacts. To build it yourself, install `flatpak-builder` and run:

```sh
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak-builder --user --install-deps-from=flathub --force-clean --install build-dir linux/app.threadhaven.ThreadHaven.yml
flatpak run app.threadhaven.ThreadHaven
```

The build needs network access to fetch Swift packages, so it is not ready for Flathub yet.

## Development

```sh
swift build
make test
make app
```

On Linux, `swift build --product threadhaven-stats` builds the stats command and `swift test` runs the core tests.

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines and the release process, and [CHANGELOG.md](CHANGELOG.md) for what changed in each version.

## Roadmap

Done so far: token savings, the Workspace window, the embedded terminal, Codex CLI support and previews of the Linux app and the phone companion. Next up are a self-hostable end-to-end encrypted relay for phones without Tailscale, native phone apps and team profiles. See [ROADMAP.md](ROADMAP.md) for details.
## License

[MIT](LICENSE)

ThreadHaven is an independent project and is not affiliated with or endorsed by Anthropic. Claude and Claude Code are trademarks of Anthropic.
