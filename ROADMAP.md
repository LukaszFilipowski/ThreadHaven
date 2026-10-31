# Roadmap

ThreadHaven aims to be the place where you and your team run Claude Code: every chat in one view, and every token spent on purpose. The plan below is a direction, not a promise; items can move between versions.

## 0.2 · Token Saver

Long chats are where most tokens go. Each turn re-reads the whole context, and coming back to a large chat after its prompt cache expired rebuilds all of it.

- Token insights for every chat: context per turn, cold cache rebuilds and the heaviest tool outputs
- Compaction triggered by an absolute token threshold instead of a share of the context window
- A warning before you continue a large chat whose prompt cache has gone cold
- Handoff: a cheap model writes a note from the chat, and a fresh session starts from it instead of the full history
- `threadhaven stats`: a command that measures all of the above on your own transcripts, so every number we publish can be reproduced

## 0.3 · Workspace

- A breakdown of the context every session starts with: CLAUDE.md files, memory, skills, MCP servers and plugins, with their weight in tokens
- Turning skills, MCP servers and plugins on and off per project
- A knowledge base per project that keeps CLAUDE.md, memory and handoff notes together

## 0.4 · Teams

- Shared skills and knowledge bases distributed through a Git repository
- Team profiles that set up hooks, skills and settings in one step
- Opt-in team usage insights that stay on your own infrastructure

## Platforms

- **Core library.** The transcript reader, hook handling and token insights move into a Foundation-only `ThreadHavenCore` package that builds on macOS and Linux.
- **Linux.** A native desktop app built on the core library.
- **iPhone.** A companion app paired with a Mac: notifications, approvals, sending prompts and handoffs on the go. Sessions keep running on the host.
- **Android.** The same companion for Linux and Mac hosts.

## Later

- Codex CLI sessions
- A global hotkey with a quick switcher
- Signed and notarized releases distributed through a Homebrew cask
