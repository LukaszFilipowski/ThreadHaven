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
- Text is sent to a terminal only for chats whose Claude Code process runs in the foreground of that terminal. The foreground process of the tab is checked again in the same AppleScript, right before the text is typed.
- Release builds are produced by GitHub Actions with pinned actions, read-only CI permissions and secrets scoped to the steps that need them.

## Remote access

Remote access (Settings → Remote access, off by default) lets a phone check chats and send prompts through your Tailscale network. It adds a small HTTP server to the app, so it is the main attack surface of ThreadHaven. These protections apply:

- **Local listener only.** The server listens on `127.0.0.1` on a port chosen at random once, only while remote access is on, and rejects connections from any other address. `tailscale serve` publishes it inside your tailnet with HTTPS. ThreadHaven never runs commands that change Tailscale settings. It refuses to start, or turns itself off, when `tailscale funnel status` shows the port exposed to the internet or cannot be read, and it rejects every request that carries the `Tailscale-Funnel-Request` header.
- **Per-device tokens.** Every paired device gets its own random 256-bit token. Only its SHA-256 hash is stored, in the macOS Keychain, and hashes are compared in constant time. The pairing QR code carries the token in the URL fragment, which browsers do not send to servers. Devices can be revoked one by one in Settings, and turning remote access off, manually or after the idle period you choose (8 hours by default), revokes all of them.
- **Tailscale identity.** `tailscale serve` adds the `Tailscale-User-Login` of the tailnet user behind each request. By default only the user signed in to Tailscale on the Mac is accepted; you can replace that with a list of tailnet users. When ThreadHaven cannot read your login (for example on a tagged device) and the list is empty, every request is refused. Local processes on the Mac can reach the port directly and can set this header, so the identity check protects against other tailnet users, not against software running on your Mac.
- **Rate limiting.** A valid token is always accepted. Only requests that present a well-formed but unknown bearer token count as failures: after 10 within 5 minutes, unknown tokens from that tailnet user are refused for 15 minutes. Requests without a token, `OPTIONS` requests and API requests that a browser marks as cross-site (`Sec-Fetch-Site`) are answered before authentication and never count, so a web page cannot lock you out. Failures are counted in Settings and logged to the unified log (subsystem `app.threadhaven`, category `remote-access`).
- **Strict HTTP handling.** Request lines, headers and bodies have size limits (16 KB of headers, 64 KB of body), `Transfer-Encoding` is refused, slow requests time out, connections and event streams are capped, and event streams close after 15 minutes and reconnect. Requests must name the tailnet host or the local address in `Host`, which blocks DNS rebinding.
- **Narrow API.** The API lists chats, returns recent message text, streams status changes, accepts prompts and registers Web Push. It reads no files by path, starts no chats and runs no shell commands. Chat IDs are matched against the chats ThreadHaven already shows.
- **Prompts.** Prompts are limited to 4,000 characters, control and invisible formatting characters are removed, and prompts starting with `!` (Claude Code's shell mode) are refused. A chat that is waiting for a permission or question answer gets no remote prompts, so a reply like `1` or `y` cannot approve anything; approvals stay on the Mac. Prompts are sent only to chats whose Claude Code process runs in the foreground of Terminal or iTerm2, the same rule as on the Mac, and every remote prompt shows a notification on the Mac.
- **Web app.** The web app is static HTML, CSS and JavaScript bundled with ThreadHaven, with no third-party scripts, fonts or CDNs. Every response carries a strict Content Security Policy (`default-src 'none'`, scripts and styles only from the app itself, no framing) and `nosniff`, `no-referrer` and HSTS headers. Transcript text is inserted with `textContent` only, never as HTML. The service worker caches the app shell and never caches API responses.
- **Web Push.** Notifications use VAPID (RFC 8292) with a key pair generated on the Mac and kept in the Keychain, and payloads are encrypted for each device (RFC 8291), so the push service sees only ciphertext. The VAPID contact is a neutral placeholder unless you enter your own in Settings; the Mac's tailnet name is never sent to push services. Subscriptions are accepted only for the push services of Apple, Google, Mozilla and Microsoft, and redirects are not followed. Notifications contain the chat title and status; message text is included only when you turn on message previews.
- **Ports left behind.** `tailscale serve --bg` keeps forwarding to the port after ThreadHaven quits, and another local user could listen on that port and receive requests from your phone. If the saved port is taken when remote access starts, ThreadHaven does not move to another port silently: it turns remote access off, signs out every device and shows a warning. Settings also warn when devices are paired but `tailscale serve` does not forward to the port. Run `tailscale serve --https=443 off` when you stop using remote access, and keep the Mac's user accounts trusted.
- **Known limits.** The server cannot tell requests forwarded by `tailscale serve` from other local connections, because both come from `127.0.0.1`, so they share one connection limit. Software running as your user on the Mac is trusted, as it is for the rest of ThreadHaven.
