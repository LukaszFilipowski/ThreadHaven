# Security Policy

## Reporting a vulnerability

Please report security issues privately through [GitHub security advisories](../../security/advisories/new). Do not open a public issue.

Include what you found, how to reproduce it and what an attacker could achieve. You can expect a first reply within a week. Fixes are released as soon as they are ready and credited in the changelog unless you prefer otherwise.

## Supported versions

Only the latest release receives security fixes.

## How ThreadHaven handles your data

- Everything runs locally. ThreadHaven has no server, telemetry or network access of its own.
- Claude Code transcripts in `~/.claude/projects` are only read, never modified.
- The hook writes session events to `~/.threadhaven/events.jsonl`. Prompt text is not stored there. The folder is private to your user account (mode 700) and its files are mode 600.
- Claude Code transcripts and `~/.claude.json` are never modified. Other Claude Code files change only when you ask for it:
  - `~/.claude/settings.json` when you install or remove the hook. The original is backed up once to `settings.json.threadhaven-backup`, and other hooks are left untouched.
  - A project's `.claude/settings.local.json` when you switch an MCP server off or on for that project.
  - Plugin and marketplace settings through the official `claude plugin` commands when you switch a plugin per project or add a team marketplace. Adding a team marketplace writes the project's `.claude/settings.json`, which your teammates receive through git.
- Prompt polishing and handoff notes run your local `claude` CLI with tools, MCP servers, skills and session persistence disabled, so text from a transcript cannot make it run commands. A new chat started from a handoff note is asked to review the note and wait for your confirmation.
- Text is sent to a terminal only for chats whose Claude Code process runs in the foreground of that terminal.
- Release builds are produced by GitHub Actions with pinned actions, read-only CI permissions and secrets scoped to the steps that need them.
