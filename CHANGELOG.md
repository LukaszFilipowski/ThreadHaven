# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Quick switcher: press ⌃⌥Space anywhere to search chats and jump to one
- Token usage panel for every chat with re-read context, cold cache rebuilds and the heaviest tool results
- Hand Off: a cheap model writes a note from a long chat and a fresh session continues from it
- A warning before continuing a large chat whose prompt cache has expired
- `threadhaven-stats` (`make stats`): a local report of context usage, cold cache rebuilds and simulated compaction savings
- `ThreadHavenCore`, a Foundation-only library with the token analytics
- `ThreadHavenCore` and `threadhaven-stats` build and pass their tests on Linux
- Per-session token analytics: context growth, cache usage, cold cache rebuilds and heaviest tool results
- Read-only workspace inventory of CLAUDE.md files, memory, skills, commands, agents, MCP servers and plugins with estimated startup tokens
- Workspace window (⇧⌘W) that shows what every chat in a project starts with and compares it with the measured start-up context
- Knowledge tab in the Workspace window that keeps a project's CLAUDE.md, memory and handoff notes together, with a preview and a fresh chat from any note
- Read-only OpenAI Codex CLI sessions next to Claude Code chats, with search, recent messages, context usage and resuming through `codex resume`

### Changed

- Auto-compact uses an absolute token threshold (150k by default) instead of a share of the context window

### Security

- Summaries and prompt polishing run the claude CLI without tools, MCP servers or skills, and leave no session behind
- The hook no longer stores prompt text, and ThreadHaven files are readable only by your user account
- Terminal and app identifiers from the environment are sanitized before they are used
- Text is never sent to a terminal whose Claude Code process is stopped or in the background
- A chat started from a handoff note reviews it and waits for confirmation instead of acting on it
- Links in transcripts open only for http and https
- Workflows use pinned actions, read-only CI permissions and step-scoped secrets

### Fixed

- Universal app build on CI runners
- Hook events from concurrent sessions no longer get lost
- Hook installation works with home folders that contain spaces and keeps unrelated hooks, symlinks and permissions in settings.json
- Dictation no longer brings back text after it was sent or polished
- Running chats are detected for Claude Code installed through npm
- A chat whose terminal tab was reused by a new chat no longer shows as running
- Only approval and question prompts mark a chat as waiting for you
- The attention dot clears on the chat you are looking at
- A first message starting with a dash is no longer read as a command-line option

## [0.1.0] - 2026-10-31

### Added

- Session list with running and recent Claude Code chats, search and context usage
- Live status and notifications through a Claude Code hook
- Switching to a chat's tab in Terminal and iTerm2, with ⌘1–⌘9 shortcuts
- New chat in a folder with `claude --continue` and resuming past chats
- Manual and automatic `/compact`
- Dictation with on-device speech recognition and prompt polishing
- Menu bar extra
- English and Polish localization
