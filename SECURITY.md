# Security Policy

## Reporting a vulnerability

Please report security issues privately through [GitHub security advisories](../../security/advisories/new). Do not open a public issue.

Include what you found, how to reproduce it and what an attacker could achieve. You can expect a first reply within a week. Fixes are released as soon as they are ready and credited in the changelog unless you prefer otherwise.

## Supported versions

Only the latest release receives security fixes.

## How ThreadHaven handles your data

- Everything runs locally. ThreadHaven has no telemetry and no cloud service. Its only network features are remote access (below), which is off by default, and the Web Push messages it sends to your paired phones.
- Claude Code transcripts in `~/.claude/projects` are only read, never modified.
- The hook writes session events to `~/.threadhaven/events.jsonl`. Prompt text is not stored there. The folder is private to your user account (mode 700) and its files are mode 600.
- Claude Code transcripts and `~/.claude.json` are never modified. Other Claude Code files change only when you ask for it:
  - `~/.claude/settings.json` when you install or remove the hook. The original is backed up once to `settings.json.threadhaven-backup`, and other hooks are left untouched.
  - A project's `.claude/settings.local.json` when you switch an MCP server off or on for that project.
  - Plugin and marketplace settings through the official `claude plugin` commands when you switch a plugin per project or add a team marketplace. Adding a team marketplace writes the project's `.claude/settings.json`, which your teammates receive through git.
- Prompt polishing and handoff notes run your local `claude` CLI with tools, MCP servers, skills and session persistence disabled, so text from a transcript cannot make it run commands. A new chat started from a handoff note is asked to review the note and wait for your confirmation.
- Text is sent to a terminal only for chats whose Claude Code process runs in the foreground of that terminal.
- Release builds are produced by GitHub Actions with pinned actions, read-only CI permissions and secrets scoped to the steps that need them.

## Remote access

Remote access (Settings → Remote access, off by default) lets a phone check chats and send prompts through your Tailscale network. It adds a small HTTP server to the app, so it is the main attack surface of ThreadHaven. These protections apply:

- **Local listener only.** The server listens on `127.0.0.1` on a random port, only while remote access is on, and rejects connections from any other address. `tailscale serve` publishes it inside your tailnet with HTTPS. ThreadHaven never runs commands that change Tailscale settings, and it refuses to start, or turns itself off, when `tailscale funnel status` shows that the port is exposed to the internet.
- **Per-device tokens.** Every paired device gets its own random 256-bit token, stored in the macOS Keychain and compared in constant time. The pairing QR code carries the token in the URL fragment, which browsers do not send to servers. Devices can be revoked one by one in Settings, and turning remote access off, manually or after the idle period you choose (8 hours by default), revokes all of them.
- **Tailscale identity.** A device is bound to the `Tailscale-User-Login` of its first request and rejected when it shows up as another tailnet user. You can also limit access to a list of tailnet users. Local processes on the Mac can reach the port directly and can set this header, so the identity check protects against other tailnet users, not against software running on your Mac.
- **Rate limiting.** After 10 failed attempts within 5 minutes, requests from that tailnet user are refused for 15 minutes. Failures are counted in Settings and logged to the unified log (subsystem `app.threadhaven`, category `remote-access`).
- **Strict HTTP handling.** Request lines, headers and bodies have size limits (16 KB of headers, 64 KB of body), `Transfer-Encoding` is refused, slow requests time out, and connections and event streams are capped. Requests must name the tailnet host or the local address in `Host`, which blocks DNS rebinding.
- **Narrow API.** The API lists chats, returns recent message text, streams status changes, accepts prompts and registers Web Push. It reads no files by path, starts no chats, answers no permission prompts and runs no shell commands. Chat IDs are matched against the chats ThreadHaven already shows.
- **Prompts.** Prompts are limited to 4,000 characters, control and invisible formatting characters are removed, and prompts starting with `!` (Claude Code's shell mode) are refused. They are sent only to chats whose Claude Code process runs in the foreground of Terminal or iTerm2, the same rule as on the Mac, and every remote prompt shows a notification on the Mac.
- **Web app.** The web app is static HTML, CSS and JavaScript bundled with ThreadHaven, with no third-party scripts, fonts or CDNs. Every response carries a strict Content Security Policy (`default-src 'none'`, scripts and styles only from the app itself, no framing) and `nosniff`, `no-referrer` and HSTS headers. Transcript text is inserted with `textContent` only, never as HTML. The service worker caches the app shell and never caches API responses.
- **Web Push.** Notifications use VAPID (RFC 8292) with a key pair generated on the Mac and kept in the Keychain, and payloads are encrypted for each device (RFC 8291), so the push service sees only ciphertext. Subscriptions are accepted only for the push services of Apple, Google, Mozilla and Microsoft. Notifications contain the chat title and status; message text is included only when you turn on message previews.
- **Ports left behind.** `tailscale serve --bg` keeps forwarding to the port after ThreadHaven quits. Another local user could then listen on that port and receive requests from your phone. Run `tailscale serve --https=443 off` when you stop using remote access, and keep the Mac's user accounts trusted.

