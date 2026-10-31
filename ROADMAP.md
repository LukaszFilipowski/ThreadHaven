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

A first measurement shows that files on disk (CLAUDE.md, memory, skill descriptions) are only a small part of the context a session starts with. Most of it is the system prompt and built-in tools. Claude Code already defers MCP tool definitions by default, so switching off servers, connectors and plugins a project does not need mainly saves their names, instructions and skill descriptions.

- ~~A breakdown of the context every session starts with~~ (done)
- ~~Turning MCP servers and plugins on and off per project~~ (done)
- ~~A knowledge base per project that keeps CLAUDE.md, memory and handoff notes together~~ (done)

## 0.4 · Teams

- ~~Team skills through Claude Code plugin marketplaces: show what a project enables and add a team marketplace in a click, instead of a separate sharing system~~ (done)
- Team profiles that set up the ThreadHaven hook, plugins and settings in one step
- Opt-in team usage insights that stay on your own infrastructure

## Platforms

- **Core library.** The transcript reader, hook handling and token insights move into a Foundation-only `ThreadHavenCore` package that builds on macOS and Linux.
- **Linux.** A native desktop app built on the core library.
- **Phone companion over Tailscale.** A web app served by ThreadHaven inside your tailnet: chat status, notifications and sending prompts from iPhone or Android, from any network. See [the design](docs/design/remote-access.md).
- **Self-hostable relay.** An open-source, end-to-end encrypted relay for teams without Tailscale.
- **Native iPhone and Android apps** on the same API, with richer notifications and approvals.

## Later

- Live status for Codex CLI sessions
- Signed and notarized releases distributed through a Homebrew cask
